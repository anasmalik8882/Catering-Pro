const { before, after, beforeEach, test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { serverTimestamp } = require('firebase/firestore');

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'catering-pro-rules-test',
    firestore: { rules: fs.readFileSync(path.resolve(__dirname, '..', '..', 'firebase', 'firestore.rules'), 'utf8'), host: '127.0.0.1', port: 8080 },
  });
});
after(async () => { if (env) await env.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); });

async function provisionOwner(uid) {
  const ctx = env.authenticatedContext(uid);
  const db = ctx.firestore();
  const bizId = `owner_${uid}`;
  const business = db.doc(`businesses/${bizId}`);
  const batch = db.batch();
  batch.set(business, { name: `${uid} Catering`, city: 'Karachi', phone: '03001234567', ownerId: uid, status: 'active', createdAt: serverTimestamp() });
  batch.set(db.doc(`businesses/${bizId}/members/${uid}`), { uid, role: 'owner', active: true, joinedAt: new Date() });
  batch.set(db.doc(`users/${uid}`), { activeBusinessId: bizId, updatedAt: new Date() });
  await assertSucceeds(batch.commit());
  return { ctx, db, bizId };
}

test('first-owner bootstrap creates business, member and user atomically', async () => {
  const {db,bizId} = await provisionOwner('alice');
  await assertSucceeds(db.doc(`businesses/${bizId}`).get());
  await assertSucceeds(db.doc(`businesses/${bizId}/members/alice`).get());
});

test('one tenant cannot read or edit another tenant data', async () => {
  const alice = await provisionOwner('alice');
  const bob = await provisionOwner('bob');
  await assertFails(alice.db.doc(`businesses/${bob.bizId}`).get());
  await assertFails(alice.db.doc(`businesses/${bob.bizId}/members/bob`).get());
  await assertFails(alice.db.doc(`businesses/${bob.bizId}`).update({name:'stolen'}));
  await assertFails(bob.db.doc(`users/alice`).get());
});

test('user cannot self-promote to an existing business owner', async () => {
  const alice = await provisionOwner('alice');
  const mallory = env.authenticatedContext('mallory').firestore();
  await assertFails(mallory.doc(`businesses/${alice.bizId}/members/mallory`).set({uid:'mallory',role:'owner',active:true,joinedAt:new Date()}));
  await assertFails(mallory.doc(`users/mallory`).set({activeBusinessId:alice.bizId,updatedAt:new Date()}));
  await assertFails(mallory.doc('businesses/some_other_name').set({name:'Fake Business',city:'Karachi',phone:'03001234567',ownerId:'mallory',status:'active',createdAt:serverTimestamp()}));
});

test('members cannot create arbitrary data in future modules', async () => {
  const alice = await provisionOwner('alice');
  await assertFails(alice.db.doc(`businesses/${alice.bizId}/payments/payment1`).set({amount:100}));
});

test('owner can create and update own customer, but cannot cross tenants', async () => {
  const alice = await provisionOwner('alice');
  const bob = await provisionOwner('bob');
  const ref = alice.db.doc(`businesses/${alice.bizId}/customers/customer1`);
  await assertSucceeds(ref.set({name:'Customer Test',phone:'03001234567',email:'',notes:'',createdBy:'alice',createdAt:serverTimestamp(),updatedAt:new Date()}));
  await assertSucceeds(ref.update({notes:'Requested walima',updatedAt:new Date()}));
  await assertFails(bob.db.doc(ref.path).get());
  await assertFails(bob.db.doc(ref.path).update({notes:'stolen'}));
  await assertFails(alice.db.doc(`businesses/${bob.bizId}/customers/fake`).set({name:'Fake',phone:'03001234567',email:'',notes:'',createdBy:'alice',createdAt:serverTimestamp(),updatedAt:new Date()}));
});

test('sales quotation revision and header must be committed together', async () => {
  const alice = await provisionOwner('alice');
  const customer = alice.db.doc(`businesses/${alice.bizId}/customers/customer1`);
  await assertSucceeds(customer.set({name:'Customer Test',phone:'03001234567',email:'',notes:'',createdBy:'alice',createdAt:serverTimestamp(),updatedAt:new Date()}));
  const quote = alice.db.doc(`businesses/${alice.bizId}/quotations/q1`);
  const revision = quote.collection('revisions').doc('1');
  const batch = alice.db.batch();
  batch.set(quote,{customerId:'customer1',inquiryId:'',eventType:'Walima',guests:100,eventDate:new Date(),validUntil:null,status:'draft',revision:1,totalPaisa:10000,createdBy:'alice',createdAt:serverTimestamp(),updatedAt:new Date()});
  batch.set(revision,{revision:1,lines:[{itemId:'a',title:'Meal',quantity:1,unitPaisa:10000,totalPaisa:10000}],subtotalPaisa:10000,extraPaisa:0,discountPaisa:0,totalPaisa:10000,notes:'',createdAt:serverTimestamp()});
  await assertSucceeds(batch.commit());
  await assertFails(alice.db.doc(revision.path).update({totalPaisa:1}));
  await assertFails(alice.db.doc(quote.path).update({totalPaisa:1}));
  await assertFails(alice.db.doc(`businesses/${alice.bizId}/payments/fake`).set({amount:1}));
});

test('accepted quote converts to one immutable-priced tentative booking', async () => {
  const alice = await provisionOwner('alice');
  const customer = alice.db.doc(`businesses/${alice.bizId}/customers/c1`);
  await assertSucceeds(customer.set({name:'Wedding Customer',phone:'03001234567',email:'',notes:'',createdBy:'alice',createdAt:serverTimestamp(),updatedAt:new Date()}));
  const q = alice.db.doc(`businesses/${alice.bizId}/quotations/q1`);
  const batch = alice.db.batch();
  batch.set(q,{customerId:'c1',inquiryId:'',eventType:'Walima',guests:100,eventDate:new Date('2026-12-10T10:00:00Z'),validUntil:null,status:'draft',revision:1,totalPaisa:1000000,createdBy:'alice',createdAt:serverTimestamp(),updatedAt:new Date()});
  batch.set(q.collection('revisions').doc('1'),{revision:1,lines:[{itemId:'a',title:'Meal',quantity:100,unitPaisa:10000,totalPaisa:1000000}],subtotalPaisa:1000000,extraPaisa:0,discountPaisa:0,totalPaisa:1000000,notes:'',createdAt:serverTimestamp()});
  await assertSucceeds(batch.commit());
  await assertSucceeds(q.update({status:'sent',updatedAt:new Date()}));
  await assertSucceeds(q.update({status:'accepted',updatedAt:new Date()}));
  const ref=alice.db.doc(`businesses/${alice.bizId}/bookings/q1`);
  const booking={quotationId:'q1',quotationRevision:1,customerId:'c1',eventType:'Walima',eventDate:new Date('2026-12-10T10:00:00Z'),guests:100,totalPaisa:1000000,status:'tentative',createdBy:'alice',createdAt:serverTimestamp(),updatedAt:serverTimestamp()};
  await assertSucceeds(ref.set(booking));
  await assertFails(ref.update({totalPaisa:1}));
  await assertFails(ref.update({status:'closed'}));
  await assertFails(ref.update({status:'confirmed',updatedAt:serverTimestamp()}));
  const bob=await provisionOwner('bob');
  await assertFails(bob.db.doc(ref.path).get());
  await assertFails(bob.db.doc(ref.path).update({status:'cancelled'}));
});
