'use strict';
// Read-only inventory. Does not list email addresses, customer names, or account secrets.
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const project = process.env.GCLOUD_PROJECT;
if (project !== 'catering-pro-b001d') throw Error('Explicit production GCLOUD_PROJECT=catering-pro-b001d required');
if (process.env.FIRESTORE_EMULATOR_HOST) throw Error('Unsetting FIRESTORE_EMULATOR_HOST is required');
if (process.argv.slice(2).length) throw Error('No command-line arguments accepted');
initializeApp({ projectId: project });
const db = getFirestore();
async function main() {
  const businessSnapshot = await db.collection('businesses').get();
  const result = [];
  for (const business of businessSnapshot.docs) {
    const base = business.ref;
    const [bookings, payments, cap, balances, settings, state] = await Promise.all([
      base.collection('bookings').count().get(),
      base.collection('payments').count().get(),
      base.collection('capacityDays').count().get(),
      base.collection('paymentBalances').count().get(),
      base.collection('settings').doc('capacity').get(),
      base.collection('settings').doc('trustedOperations').get(),
    ]);
    result.push({
      businessId: business.id,
      bookings: bookings.data().count,
      payments: payments.data().count,
      capacityDayDocuments: cap.data().count,
      paymentBalanceDocuments: balances.data().count,
      capacityConfigured: settings.exists,
      trustedState: !state.exists ? 'absent' : state.get('status') === 'ready' ? 'ready' : 'not-ready',
    });
  }
  const output = { project, readOnly: true, businessCount: result.length, businesses: result };
  console.log(JSON.stringify(output, null, 2));
  if (result.length === 0) console.error('WARNING: No business records found. Verify project and access.');
}
main().catch(error => { console.error('Inventory failed:', error.message); process.exitCode = 1; });
