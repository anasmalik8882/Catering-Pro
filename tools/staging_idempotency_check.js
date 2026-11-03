'use strict';
// Read-only verification of an ALREADY-COMMITTED payment using its original
// idempotency key. Only callable requests are sent; a correct backend makes
// no writes. Do not run against production.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
// Resolve Firebase Admin using the Functions package's dependency tree.
// Its modular imports are package exports, not physical /app or /firestore folders.
const { createRequire } = require('node:module');
const functionsRequire = createRequire(path.resolve(__dirname, '../functions/package.json'));
let initializeApp, getFirestore;
try {
  ({ initializeApp } = functionsRequire('firebase-admin/app'));
  ({ getFirestore } = functionsRequire('firebase-admin/firestore'));
} catch (error) {
  if (error.code === 'MODULE_NOT_FOUND') {
    throw Error('Firebase Admin dependencies are missing. Run npm --prefix functions ci (or npm --prefix functions install if no lockfile), then retry.');
  }
  throw error;
}

const PROJECT = 'caterer-pro-staging';
const BUSINESS = 'owner_jKETux10VVcEuJ04LW2WiYcAGCG2';
const BOOKING = 'vrqkEe7QNVyNl1HrdTcJ';
const REGION = 'asia-south1';

async function invoke(token, data) {
  const uri = `https://${REGION}-${PROJECT}.cloudfunctions.net/recordBookingPayment`;
  const res = await fetch(uri, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ data }),
    signal: AbortSignal.timeout(30000),
  });
  const body = await res.text();
  let parsed;
  try { parsed = JSON.parse(body); }
  catch { throw new Error(`Callable returned non-JSON HTTP ${res.status}: ${body.slice(0,200)}`); }
  return { httpStatus: res.status, result: parsed.result, error: parsed.error };
}

async function run() {
  if (process.argv.length !== 2 || process.env.CONFIRM_STAGING_REPLAY !== 'YES') {
    throw Error('Refusing to run without CONFIRM_STAGING_REPLAY=YES; no positional arguments permitted.');
  }
  if (process.env.FIRESTORE_EMULATOR_HOST || process.env.FIREBASE_AUTH_EMULATOR_HOST) {
    throw Error('Unset emulator variables; this verifier is only for deployed staging.');
  }
  if (process.env.GCLOUD_PROJECT !== PROJECT || process.env.GOOGLE_CLOUD_PROJECT && process.env.GOOGLE_CLOUD_PROJECT !== PROJECT) {
    throw Error('GCLOUD_PROJECT must explicitly equal caterer-pro-staging.');
  }
  const email = process.env.STAGING_TEST_EMAIL;
  const password = process.env.STAGING_TEST_PASSWORD;
  if (!email || !password) throw Error('Provide staging test email and password via environment variables (never command-line arguments).');
  const jsonPath = path.resolve(__dirname, '../android/app/src/staging/google-services.json');
  const nativeConfig = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));
  if (nativeConfig.project_info.project_id !== PROJECT) throw Error('Staging Google Services JSON points to a different Firebase project.');
  const client = nativeConfig.client.find(c => c.client_info.android_client_info.package_name === 'com.example.catering_pro.staging');
  const apiKey = client?.api_key?.[0]?.current_key;
  if (!apiKey) throw Error('Staging Android API key not found in src/staging/google-services.json.');

  const login = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${encodeURIComponent(apiKey)}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
    signal: AbortSignal.timeout(30000),
  });
  const auth = await login.json();
  if (!login.ok || !auth.idToken || !auth.localId) throw Error(`Staging test sign-in failed: ${auth.error?.message ?? login.status}`);
  if (BUSINESS !== `owner_${auth.localId}`) throw Error('Authenticated user is not the designated isolated staging test-business owner.');
  initializeApp({ projectId: PROJECT });
  const db = getFirestore();
  const base = db.collection('businesses').doc(BUSINESS);
  const business = await base.get();
  if (!business.exists || business.get('name') !== 'Test Business' || business.get('ownerId') !== auth.localId) {
    throw Error('Staging business guard failed; refusing to send any callable request.');
  }
  const member = await base.collection('members').doc(auth.localId).get();
  if (!member.exists || member.get('active') !== true || member.get('role') !== 'owner') throw Error('Staging owner membership missing.');
  const booking = await base.collection('bookings').doc(BOOKING).get();
  // Diagnose precise preflight discrepancy without exposing customer details.
  if (!booking.exists) {
    const all = await base.collection('bookings').get();
    console.log('READ-ONLY PREFLIGHT: configured booking ID absent; available booking metadata:');
    for (const d of all.docs) {
      const b = d.data();
      console.log(JSON.stringify({id:d.id,status:b.status,totalPaisa:b.totalPaisa,guests:b.guests}));
    }
    throw Error(`Configured booking ${BOOKING} does not exist in the isolated staging business. No callable request sent.`);
  }
  const actualStatus = booking.get('status');
  const actualTotal = booking.get('totalPaisa');
  if (actualStatus !== 'confirmed' || actualTotal !== 2500000) {
    console.log('READ-ONLY PREFLIGHT: booking metadata differs from expected:', JSON.stringify({
      bookingId: BOOKING, status: actualStatus ?? null, totalPaisa: actualTotal ?? null,
      statusMatches: actualStatus === 'confirmed', totalMatches: actualTotal === 2500000,
    }));
    throw Error('Booking guard mismatch; no callable request sent. Do not edit records to match the test.');
  }
  const balances = base.collection('paymentBalances').doc(BOOKING);
  const paymentsRef = base.collection('payments');
  const listPayments = async () => (await paymentsRef.get()).docs;
  const beforePayments = await listPayments();
  const prior = beforePayments.filter(doc => {
    const p = doc.data();
    return p.bookingId === BOOKING && p.createdBy === auth.localId && p.kind === 'payment' && p.amountPaisa === 500000;
  });
  if (prior.length !== 1) throw Error(`Expected exactly one existing Rs 5,000 payment by test owner; found ${prior.length}.`);
  const original = prior[0];
  const p = original.data();
  if (!/^[a-zA-Z0-9-]{1,100}$/.test(original.id)) throw Error('Original payment document ID is not a valid request ID.');
  if (typeof p.method !== 'string' || typeof p.reference !== 'string') throw Error('Original payment fields are incomplete.');
  const beforeBalance = (await balances.get()).get('netCollectedPaisa');
  if (beforeBalance !== 400000) throw Error(`Expected Rs 4,000 after refund, found paisa=${beforeBalance}; stop and inspect before replay.`);
  const request = {businessId: BUSINESS, bookingId: BOOKING, requestId:original.id,
    amountPaisa:p.amountPaisa, kind:p.kind, method:p.method, reference:p.reference};
  console.log(`Guard passed: project=${PROJECT}, business=Test Business, booking=${BOOKING}.`);
  console.log(`Baseline: ${beforePayments.length} total ledger documents, balance=${beforeBalance} paisa.`);
  console.log('Replaying previously committed Rs 5,000 payment with unchanged original request ID.');
  const replay = await invoke(auth.idToken, request);
  assert.equal(replay.error, undefined, `Replay failed: ${JSON.stringify(replay.error)}`);
  assert.equal(replay.result?.duplicate, true, 'Replay was NOT identified as duplicate.');
  assert.equal(replay.result?.paymentId, original.id, 'Replayed payment ID mismatch.');
  console.log('PASS: duplicate:true returned from deployed staging callable.');
  const alteredAmount = p.amountPaisa === 100 ? 101 : p.amountPaisa - 100;
  const conflict = await invoke(auth.idToken, {...request, amountPaisa:alteredAmount});
  assert.ok(conflict.error, 'Conflicting request ID unexpectedly accepted!');
  console.log(`PASS: altered payload with same request ID rejected (${conflict.error.status || 'error'}).`);
  const afterPayments = await listPayments();
  const afterBalance = (await balances.get()).get('netCollectedPaisa');
  assert.deepEqual(afterPayments.map(x=>x.id).sort(),beforePayments.map(x=>x.id).sort(), 'Ledger document IDs changed.');
  assert.equal(afterBalance,beforeBalance,'Payment balance changed.');
  console.log(`PASS: ledger unchanged (${afterPayments.length} documents), balance unchanged (${afterBalance} paisa).`);
  console.log('STAGING IDEMPOTENCY VERIFICATION PASSED. No production data was accessed by this script.');
}
run().catch(err => { console.error(`VERIFICATION FAILED: ${err.message}`); process.exitCode = 1; });
