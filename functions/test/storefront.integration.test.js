'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {initializeApp, getApps} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {getAuth} = require('firebase-admin/auth');
const PROJECT = 'demo-caterer-stage';
const url = `http://127.0.0.1:5001/${PROJECT}/asia-south1`;
const draft = (slug='test-caterer') => ({slug, displayName:'Test Caterer', description:'Public description', phone:'', email:'', location:'', services:'Catering', logoUrl:'', heroUrl:'', published:true, menus:[{id:'dish', description:'Public menu description', imageUrl:'', showPrice:false}], packages:[{id:'package', description:'Public package description', imageUrl:'', showPrice:true}]});
async function invoke(name, data, token) {
  const response = await fetch(`${url}/${name}`, {method:'POST',headers:{'Content-Type':'application/json', ...(token ? {Authorization:`Bearer ${token}`} : {})},body:JSON.stringify({data})});
  const body = await response.json();
  return {result:body.result, error:body.error};
}
async function user(email) {
  const auth = getAuth();
  const record = await auth.createUser({email,password:'emulator-password-123'});
  const response = await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-key', {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email,password:'emulator-password-123',returnSecureToken:true})});
  const {idToken} = await response.json();
  assert.ok(idToken);
  return {uid:record.uid,token:idToken};
}
test('storefront authorization, visibility, slug reservation and anonymous intake', {timeout:240000}, async () => {
  assert.equal(process.env.GCLOUD_PROJECT,PROJECT,'Use isolated demo emulators only');
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST,'127.0.0.1:8080');
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST,'127.0.0.1:9099');
  if (!getApps().length) initializeApp({projectId:PROJECT});
  const db = getFirestore();
  const alice = await user('website-alice@example.invalid');
  const bob = await user('website-bob@example.invalid');
  const staff = await user('website-staff@example.invalid');
  for (const [bid, account] of [['web-alice',alice],['web-bob',bob]]) {
    const base = db.collection('businesses').doc(bid);
    await base.set({name:'Private name',status:'active',ownerId:account.uid,privateNotes:'Secret'});
    await base.collection('members').doc(account.uid).set({role:'owner',active:true});
    await base.collection('menuItems').doc('dish').set({name:'Biryani',active:true,pricePaisa:50000,unit:'plate',description:'Private recipe',costPaisa:123});
    await base.collection('packages').doc('package').set({name:'Wedding feast',active:true,pricePaisa:150000,pricingMode:'per_head',minimumGuests:50,secret:'secret'});
  }
  const base = db.collection('businesses').doc('web-alice');
  await base.collection('members').doc(staff.uid).set({role:'manager',active:true});
  const save = (account, businessId, config) => invoke('saveStorefront',{businessId,config},account?.token);
  assert.equal((await save(null,'web-alice',draft())).error.status,'UNAUTHENTICATED');
  assert.equal((await save(bob,'web-alice',draft())).error.status,'PERMISSION_DENIED');
  assert.equal((await save(staff,'web-alice',draft())).error.status,'PERMISSION_DENIED');
  assert.equal((await invoke('getStorefrontSettings',{businessId:'web-alice'},bob.token)).error.status,'PERMISSION_DENIED');
  assert.equal((await save(alice,'web-alice',{...draft(),slug:'../x'})).error.status,'INVALID_ARGUMENT');
  assert.equal((await save(alice,'web-alice',{...draft(),menus:[{id:'missing',description:'',imageUrl:'',showPrice:false}]})).error.status,'FAILED_PRECONDITION');
  const claims = await Promise.all([save(alice,'web-alice',draft()),save(bob,'web-bob',draft())]);
  assert.equal(claims.filter(r => !r.error).length,1);
  assert.equal(claims.filter(r => r.error?.status === 'ALREADY_EXISTS').length,1);
  // Give Alice her own stable URL regardless of who won the concurrent claim.
  assert.ok(!(await save(alice,'web-alice',draft('alice-catering'))).error);
  const publicResult = await invoke('getPublicStorefront',{slug:'alice-catering'});
  assert.equal(publicResult.result.displayName,'Test Caterer');
  assert.equal(publicResult.result.menus[0].pricePaisa,undefined);
  assert.equal(publicResult.result.packages[0].pricePaisa,150000);
  for (const secret of ['costPaisa','Private recipe','privateNotes','ownerId','businessId','createdBy']) assert.ok(!JSON.stringify(publicResult.result).includes(secret),secret);
  assert.equal((await invoke('getPublicStorefront',{slug:'missing-business'})).error.status,'NOT_FOUND');
  assert.equal((await invoke('getPublicStorefront',{slug:'a/b'})).error.status,'INVALID_ARGUMENT');
  const payload = {slug:'alice-catering',requestId:'request-1',name:'Public Visitor',phone:'03001234567',email:'',eventType:'Wedding',eventDate:new Date(Date.now()+86400000*10).toISOString().slice(0,10),guests:100,packageId:'package',requirements:'Vegetarian options',businessId:'web-bob',status:'confirmed'};
  assert.equal((await invoke('submitStorefrontInquiry',{...payload,guests:0})).error.status,'INVALID_ARGUMENT');
  assert.equal((await invoke('submitStorefrontInquiry',{...payload,packageId:'private-package'})).error.status,'INVALID_ARGUMENT');
  const [first,retry] = await Promise.all([invoke('submitStorefrontInquiry',payload),invoke('submitStorefrontInquiry',payload)]);
  assert.ok(first.result,JSON.stringify(first));
  assert.equal(first.result.inquiryId,retry.result.inquiryId);
  const stored = await base.collection('publicInquiries').doc(first.result.inquiryId).get();
  assert.equal(stored.get('businessId'),'web-alice');
  assert.equal(stored.get('status'),'new');
  assert.ok(stored.get('createdAt').toDate());
  assert.equal((await db.collection('businesses').doc('web-bob').collection('publicInquiries').get()).size,0);
  assert.equal((await base.collection('bookings').get()).size,0);
  assert.equal((await invoke('submitStorefrontInquiry',{...payload,guests:101})).error.status,'ALREADY_EXISTS');
  for (let i=2;i<=3;i++) assert.ok((await invoke('submitStorefrontInquiry',{...payload,requestId:`request-${i}`})).result);
  assert.equal((await invoke('submitStorefrontInquiry',{...payload,requestId:'request-4'})).error.status,'RESOURCE_EXHAUSTED');
  await save(alice,'web-alice',{...draft('alice-catering'),published:false});
  assert.equal((await invoke('getPublicStorefront',{slug:'alice-catering'})).error.status,'NOT_FOUND');
  assert.equal((await invoke('submitStorefrontInquiry',{...payload,requestId:'unpublished'})).error.status,'NOT_FOUND');
  // Unpublishing reserves the slug for its owner.
  assert.equal((await save(bob,'web-bob',draft('alice-catering'))).error.status,'ALREADY_EXISTS');
  await save(alice,'web-alice',draft('alice-renamed'));
  assert.equal((await invoke('getPublicStorefront',{slug:'alice-catering'})).error.status,'NOT_FOUND');
  await base.update({status:'disabled'});
  assert.equal((await invoke('getPublicStorefront',{slug:'alice-renamed'})).error.status,'NOT_FOUND');
  assert.equal((await save(alice,'web-alice',draft('alice-renamed'))).error.status,'FAILED_PRECONDITION');
});

test('existing trusted booking, payment and capacity endpoints work with new emulator fixtures', {timeout:180000}, async () => {
  assert.equal(process.env.GCLOUD_PROJECT, PROJECT);
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:8080');
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, '127.0.0.1:9099');
  if (!getApps().length) initializeApp({projectId:PROJECT});
  const {Timestamp} = require('firebase-admin/firestore');
  const db = getFirestore();
  const account = await user('web-trusted-smoke@example.invalid');
  const businessId = 'web-trusted-smoke';
  const base = db.collection('businesses').doc(businessId);
  await base.set({ownerId:account.uid,status:'active',name:'Synthetic trusted smoke'});
  await base.collection('members').doc(account.uid).set({active:true,role:'owner'});
  const init = await invoke('initializeDailyCapacity',{businessId,maxGuestsPerDay:300},account.token);
  assert.ok(init.result,JSON.stringify(init));
  await base.collection('bookings').doc('new-booking').set({status:'tentative',guests:100,totalPaisa:50000,eventDate:Timestamp.fromDate(new Date('2027-03-01T12:00:00Z'))});
  const transition = await invoke('transitionBooking',{businessId,bookingId:'new-booking',status:'confirmed'},account.token);
  assert.equal(transition.result?.status,'confirmed',JSON.stringify(transition));
  assert.equal((await base.collection('capacityDays').doc('2027-03-01').get()).get('reservedGuests'),100);
  const payment = {businessId,bookingId:'new-booking',amountPaisa:10000,kind:'payment',method:'cash',reference:'synthetic',requestId:'smoke-payment'};
  const collected = await invoke('recordBookingPayment',payment,account.token);
  assert.equal(collected.result?.netCollectedPaisa,10000,JSON.stringify(collected));
  assert.equal((await invoke('recordBookingPayment',payment,account.token)).result?.duplicate,true);
  const capacity = await invoke('updateDailyCapacity',{businessId,maxGuestsPerDay:500},account.token);
  assert.equal(capacity.result?.maxGuestsPerDay,500,JSON.stringify(capacity));
  assert.equal((await invoke('transitionBooking',{businessId,bookingId:'new-booking',status:'cancelled'},account.token)).result?.status,'cancelled');
  assert.equal((await base.collection('capacityDays').doc('2027-03-01').get()).get('reservedGuests'),0);
});

test('website inquiries convert into a tenant customer and sales inquiry (Milestone 11)', {timeout:240000}, async () => {
  assert.equal(process.env.GCLOUD_PROJECT, PROJECT);
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:8080');
  if (!getApps().length) initializeApp({projectId:PROJECT});
  const db = getFirestore();
  const owner = await user('pipeline-owner@example.invalid');
  const seller = await user('pipeline-sales@example.invalid');
  const cook = await user('pipeline-kitchen@example.invalid');
  const outsider = await user('pipeline-outsider@example.invalid');
  const businessId = 'pipeline-biz';
  const base = db.collection('businesses').doc(businessId);
  await base.set({name:'Pipeline Caterer', status:'active', ownerId:owner.uid});
  await base.collection('members').doc(owner.uid).set({role:'owner', active:true});
  await base.collection('members').doc(seller.uid).set({role:'sales', active:true});
  await base.collection('members').doc(cook.uid).set({role:'kitchen_staff', active:true});
  await base.collection('packages').doc('feast').set({name:'Wedding feast', active:true, pricePaisa:150000, pricingMode:'per head', minimumGuests:50});
  const inquiry = (name, phone) => ({name, phone, email:'visitor@example.invalid', eventType:'Walima', eventDate:'2027-04-10', guests:250,
    packageId:'feast', requirements:'Live BBQ station', businessId, slug:'pipeline', contentHash:'x', status:'new', source:'public_storefront', createdAt:new Date()});
  await base.collection('publicInquiries').doc('pub-1').set(inquiry('Ayesha Khan', '03001112222'));
  await base.collection('publicInquiries').doc('pub-2').set(inquiry('Bilal Ahmed', '03009998888'));
  await base.collection('customers').doc('existing').set({name:'Bilal Ahmed', phone:'03009998888', email:'', notes:'', createdBy:owner.uid, createdAt:new Date(), updatedAt:new Date()});
  const review = (account, data) => invoke('reviewPublicInquiry', {businessId, ...data}, account?.token);

  assert.equal((await review(null, {inquiryId:'pub-1', action:'contacted'})).error.status, 'UNAUTHENTICATED');
  assert.equal((await review(cook, {inquiryId:'pub-1', action:'contacted'})).error.status, 'PERMISSION_DENIED');
  assert.equal((await review(outsider, {inquiryId:'pub-1', action:'contacted'})).error.status, 'PERMISSION_DENIED');
  assert.equal((await review(seller, {inquiryId:'missing', action:'contacted'})).error.status, 'NOT_FOUND');
  assert.equal((await review(seller, {inquiryId:'pub-1', action:'reopen'})).error.status, 'FAILED_PRECONDITION');
  assert.equal((await review(seller, {inquiryId:'pub-1', action:'contacted'})).result.status, 'contacted');

  // Concurrent conversions of the same inquiry yield one customer + one sales inquiry.
  const [a, b] = await Promise.all([review(seller, {inquiryId:'pub-1', action:'convert'}), review(seller, {inquiryId:'pub-1', action:'convert'})]);
  assert.ok(a.result && b.result, JSON.stringify([a, b]));
  assert.equal(a.result.salesInquiryId, b.result.salesInquiryId);
  assert.equal(a.result.customerId, b.result.customerId);
  const customer = await base.collection('customers').doc(a.result.customerId).get();
  assert.equal(customer.get('name'), 'Ayesha Khan');
  assert.equal(customer.get('createdBy'), seller.uid);
  const salesInquiry = await base.collection('inquiries').doc(a.result.salesInquiryId).get();
  assert.equal(salesInquiry.get('source'), 'Website');
  assert.equal(salesInquiry.get('status'), 'new');
  assert.equal(salesInquiry.get('guests'), 250);
  assert.equal(salesInquiry.get('customerId'), customer.id);
  assert.ok(salesInquiry.get('notes').includes('Wedding feast'));
  assert.ok(salesInquiry.get('notes').includes('Live BBQ station'));
  const converted = await base.collection('publicInquiries').doc('pub-1').get();
  assert.equal(converted.get('status'), 'converted');
  assert.equal(converted.get('handledBy'), seller.uid);
  assert.equal((await review(seller, {inquiryId:'pub-1', action:'dismiss'})).error.status, 'FAILED_PRECONDITION');

  // Matching phone reuses the existing customer instead of duplicating.
  const reuse = await review(owner, {inquiryId:'pub-2', action:'convert'});
  assert.equal(reuse.result.customerId, 'existing', JSON.stringify(reuse));
  assert.equal(reuse.result.customerCreated, false);
  assert.equal((await base.collection('customers').get()).size, 2);

  // Dismiss / reopen cycle, and cross-tenant customer ids are rejected.
  await base.collection('publicInquiries').doc('pub-3').set(inquiry('Spam Bot', '03000000000'));
  assert.equal((await review(seller, {inquiryId:'pub-3', action:'dismiss', reason:'spam'})).result.status, 'dismissed');
  assert.equal((await base.collection('publicInquiries').doc('pub-3').get()).get('dismissReason'), 'spam');
  assert.equal((await review(seller, {inquiryId:'pub-3', action:'reopen'})).result.status, 'new');
  assert.equal((await review(seller, {inquiryId:'pub-3', action:'convert', customerId:'not-here'})).error.status, 'NOT_FOUND');

  // No booking, quotation, payment or capacity state was touched.
  for (const c of ['bookings', 'quotations', 'payments', 'capacityDays']) assert.equal((await base.collection(c).get()).size, 0, c);
});

test('platform admin lists, inspects, suspends and reactivates tenants (Milestone 12)', {timeout:240000}, async () => {
  assert.equal(process.env.GCLOUD_PROJECT, PROJECT);
  if (!getApps().length) initializeApp({projectId:PROJECT});
  const db = getFirestore();
  const admin = await user('platform-admin@example.invalid');
  await getAuth().setCustomUserClaims(admin.uid, {platformAdmin:true});
  const refreshed = await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-key', {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:'platform-admin@example.invalid',password:'emulator-password-123',returnSecureToken:true})});
  const adminToken = (await refreshed.json()).idToken;
  const owner = await user('tenant-owner@example.invalid');
  const businessId = 'admin-tenant';
  const base = db.collection('businesses').doc(businessId);
  await base.set({name:'Admin Tenant', city:'Lahore', phone:'03001234567', status:'active', ownerId:owner.uid, privateNotes:'ledger'});
  await base.collection('members').doc(owner.uid).set({role:'owner', active:true});
  await base.collection('customers').doc('c1').set({name:'Customer'});

  // Tenant owners are not platform admins.
  for (const name of ['adminListBusinesses', 'adminGetBusiness', 'adminSetBusinessStatus', 'adminListAuditLog']) {
    assert.equal((await invoke(name, {businessId, status:'suspended', reason:'test'}, owner.token)).error.status, 'PERMISSION_DENIED', name);
    assert.equal((await invoke(name, {businessId}, null)).error.status, 'UNAUTHENTICATED', name);
  }
  const listed = await invoke('adminListBusinesses', {limit:50}, adminToken);
  assert.ok(listed.result.businesses.some(b => b.id === businessId && b.ownerEmail === 'tenant-owner@example.invalid'), JSON.stringify(listed));
  const detail = await invoke('adminGetBusiness', {businessId}, adminToken);
  assert.equal(detail.result.usage.customers, 1);
  assert.equal(detail.result.members[0].role, 'owner');
  assert.ok(!JSON.stringify(detail.result).includes('ledger'));
  assert.equal((await invoke('adminSetBusinessStatus', {businessId, status:'suspended', reason:''}, adminToken)).error.status, 'INVALID_ARGUMENT');
  assert.equal((await invoke('adminSetBusinessStatus', {businessId, status:'suspended', reason:'Unpaid invoice'}, adminToken)).result.status, 'suspended');
  assert.equal((await base.get()).get('status'), 'suspended');
  // Suspension blocks trusted tenant operations.
  const blocked = await invoke('initializeDailyCapacity', {businessId, maxGuestsPerDay:100}, owner.token);
  assert.equal(blocked.error.status, 'FAILED_PRECONDITION');
  assert.match(blocked.error.message, /suspended/);
  const suspendedOnly = await invoke('adminListBusinesses', {status:'suspended'}, adminToken);
  assert.ok(suspendedOnly.result.businesses.every(b => b.status === 'suspended'));
  assert.equal((await invoke('adminSetBusinessStatus', {businessId, status:'active'}, adminToken)).result.status, 'active');
  assert.ok((await invoke('initializeDailyCapacity', {businessId, maxGuestsPerDay:100}, owner.token)).result);
  const log = await invoke('adminListAuditLog', {businessId}, adminToken);
  assert.deepEqual(log.result.entries.map(e => e.action), ['business.reactivate', 'business.suspend']);
  assert.equal(log.result.entries[1].reason, 'Unpaid invoice');
});
