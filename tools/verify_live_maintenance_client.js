'use strict';
// Explicitly opt-in, production-only Firebase *client SDK* rules probe.
// NEVER invokes the Admin SDK or writes historical business records.
const { createRequire } = require('node:module');
const path = require('node:path');
const crypto = require('node:crypto');
const requireFirebase = createRequire(path.resolve(__dirname, '../tests/security/package.json'));
const { initializeApp, deleteApp } = requireFirebase('firebase/app');
const { getAuth, signInWithEmailAndPassword, signOut } = requireFirebase('firebase/auth');
const { getFirestore, doc, getDocFromServer, setDoc, serverTimestamp } = requireFirebase('firebase/firestore');

const projectId = 'catering-pro-b001d';
const businessId = 'aY8cWeFOjGBgJtxCc7Fk';
const config = {
  apiKey: 'AIzaSyBq8n_x4AgoSmBtSrA51d4zbVZwgW69f08',
  authDomain: `${projectId}.firebaseapp.com`,
  projectId,
  appId: '1:541019459394:web:006de4d4692a2113ec42db',
};
async function main() {
  if (process.argv.includes('--preflight')) {
    console.log(`PREFLIGHT ONLY: client project=${projectId}; business=${businessId}`);
    console.log('Probe disabled until --run-live is explicitly supplied. No connection or write was attempted.');
    return;
  }
  if (!process.argv.includes('--run-live') || process.env.CONFIRM_LIVE_RULES_PROBE !== 'YES') {
    throw new Error('STOP: live probe requires --run-live and CONFIRM_LIVE_RULES_PROBE=YES');
  }
  if (process.env.FIRESTORE_EMULATOR_HOST || process.env.FIREBASE_AUTH_EMULATOR_HOST) {
    throw new Error('STOP: emulator environment variables detected');
  }
  const email = process.env.PROBE_EMAIL;
  const password = process.env.PROBE_PASSWORD;
  delete process.env.PROBE_PASSWORD;
  if (!email || !password) throw new Error('STOP: PROBE_EMAIL or PROBE_PASSWORD missing');
  const app = initializeApp(config, `live-maintenance-probe-${process.pid}`);
  const auth = getAuth(app);
  try {
    const user = (await signInWithEmailAndPassword(auth, email, password)).user;
    const db = getFirestore(app);
    const membership = await getDocFromServer(doc(db, 'businesses', businessId, 'members', user.uid));
    if (!membership.exists() || membership.data().active !== true || !['owner','manager','sales'].includes(membership.data().role)) {
      throw new Error('STOP: account does not have an active sales-capable membership in the demo business');
    }
    const id = `maintenance_probe_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`;
    const pathLabel = `businesses/${businessId}/customers/${id}`;
    console.log(`Authenticated as UID ${user.uid}; testing a disposable, previously absent path: ${pathLabel}`);
    const customer = doc(db, pathLabel);
    try {
      await setDoc(customer, {
        name: 'Maintenance Probe', phone: '03000000000', email: '', notes: 'DISPOSABLE MAINTENANCE TEST: REMOVE IF CREATED',
        createdBy: user.uid, createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
      });
      console.error('FAIL: CLIENT WRITE SUCCEEDED! Freeze NOT enforced. Stop cutover immediately.');
      console.error(`A new disposable document was created at: ${pathLabel}`);
      console.error('Do NOT run migration. Do NOT remove using client SDK during maintenance; arrange authorized cleanup separately.');
      process.exitCode = 2;
    } catch (error) {
      if (error.code === 'permission-denied') {
        console.log('PASS: production Firestore rejected an authenticated, otherwise-valid customer create (permission-denied).');
        console.log('Only this one client route was tested; ensure freeze propagation and all writer controls before migration.');
      } else {
        console.error(`INCONCLUSIVE: ${error.code || error.name}: ${error.message}`);
        process.exitCode = 3;
      }
    }
  } finally {
    try { await signOut(auth); } catch (_) {}
    await deleteApp(app);
  }
}
main().catch(err => { console.error('STOP:', err.message); process.exitCode = 1; });
