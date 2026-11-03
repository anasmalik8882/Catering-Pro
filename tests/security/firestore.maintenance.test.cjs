'use strict';
const { before, after, beforeEach, test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');

const projectId = 'demo-caterer-maintenance';
const businessId = 'owner_alice';
const root = path.resolve(__dirname, '../..');
let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: fs.readFileSync(path.join(root, 'firebase/firestore.maintenance.rules'), 'utf8'),
      host: '127.0.0.1', port: 8080,
    },
  });
});
after(async () => { if (env) await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    const batch = db.batch();
    batch.set(db.doc(`businesses/${businessId}`), {name:'Demo', ownerId:'alice', status:'active'});
    batch.set(db.doc(`businesses/${businessId}/members/alice`), {role:'owner', active:true, uid:'alice'});
    batch.set(db.doc('users/alice'), {activeBusinessId:businessId});
    batch.set(db.doc(`businesses/${businessId}/customers/customer1`), {name:'Existing Customer'});
    batch.set(db.doc(`businesses/${businessId}/quotations/q1`), {status:'sent'});
    batch.set(db.doc(`businesses/${businessId}/bookings/b1`), {status:'confirmed'});
    batch.set(db.doc(`businesses/${businessId}/payments/p1`), {amountPaisa:500});
    batch.set(db.doc(`businesses/${businessId}/capacityDays/2026-11-02`), {reservedGuests:100});
    batch.set(db.doc(`businesses/${businessId}/settings/capacity`), {maxGuestsPerDay:250});
    batch.set(db.doc(`businesses/${businessId}/eventTasks/t1`), {title:'Prep'});
    await batch.commit();
  });
});

test('maintenance preserves existing owner reads', async () => {
  const db = env.authenticatedContext('alice').firestore();
  for (const ref of [
    'users/alice', `businesses/${businessId}`, `businesses/${businessId}/members/alice`,
    `businesses/${businessId}/customers/customer1`, `businesses/${businessId}/quotations/q1`,
    `businesses/${businessId}/bookings/b1`, `businesses/${businessId}/payments/p1`,
    `businesses/${businessId}/capacityDays/2026-11-02`,
    `businesses/${businessId}/settings/capacity`, `businesses/${businessId}/eventTasks/t1`,
  ]) await assertSucceeds(db.doc(ref).get());
});

test('maintenance retains cross-tenant and unauthenticated read isolation', async () => {
  const outsider = env.authenticatedContext('bob').firestore();
  const anonymous = env.unauthenticatedContext().firestore();
  for (const db of [outsider, anonymous]) {
    await assertFails(db.doc(`businesses/${businessId}`).get());
    await assertFails(db.doc(`businesses/${businessId}/bookings/b1`).get());
    await assertFails(db.doc(`businesses/${businessId}/settings/capacity`).get());
  }
});

test('maintenance rejects all client creates, updates and deletes, including onboarding', async () => {
  const db = env.authenticatedContext('alice').firestore();
  for (const pathPart of [
    'users/alice', `businesses/${businessId}`, `businesses/${businessId}/members/alice`,
    `businesses/${businessId}/customers/customer1`, `businesses/${businessId}/quotations/q1`,
    `businesses/${businessId}/bookings/b1`, `businesses/${businessId}/payments/p1`,
    `businesses/${businessId}/capacityDays/2026-11-02`,
    `businesses/${businessId}/settings/capacity`, `businesses/${businessId}/eventTasks/t1`,
  ]) {
    const ref = db.doc(pathPart);
    await assertFails(ref.set({maintenanceProbe:true}));
    await assertFails(ref.update({maintenanceProbe:true}));
    await assertFails(ref.delete());
  }
  await assertFails(db.doc('businesses/owner_new').set({ownerId:'alice'}));
  await assertFails(db.doc(`businesses/${businessId}/customers/newCustomer`).set({name:'New'}));
  await assertFails(db.doc(`businesses/${businessId}/inquiries/newInquiry`).set({status:'new'}));
  await assertFails(db.doc(`businesses/${businessId}/expenses/newExpense`).set({amountPaisa:1}));
  const batch = db.batch();
  batch.update(db.doc(`businesses/${businessId}/customers/customer1`), {name:'Changed'});
  batch.update(db.doc(`businesses/${businessId}/bookings/b1`), {status:'cancelled'});
  await assertFails(batch.commit());
});

test('maintenance does not mutate existing documents after rejected writes', async () => {
  const db = env.authenticatedContext('alice').firestore();
  const ref = db.doc(`businesses/${businessId}/settings/capacity`);
  await assertFails(ref.update({maxGuestsPerDay:1}));
  const snap = await assertSucceeds(ref.get());
  assert.equal(snap.data().maxGuestsPerDay, 250);
});
