'use strict';
// Run only through Firebase Emulator Suite with the dedicated demo project.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {spawnSync} = require('node:child_process');
const path = require('node:path');
const {initializeApp, getApps} = require('firebase-admin/app');
const {getFirestore, Timestamp} = require('firebase-admin/firestore');
const {getAuth} = require('firebase-admin/auth');
const PROJECT='demo-caterer-stage';
const BUSINESS='synthetic-caterer';
const PORT=5001;
const FUNCTIONS_BASE=`http://127.0.0.1:${PORT}/${PROJECT}/asia-south1`;
const SCRIPT=path.resolve(__dirname,'../scripts/reconcile.js');

function assertEmulatorEnvironment() {
  if(process.env.GCLOUD_PROJECT!==PROJECT || process.env.FIRESTORE_EMULATOR_HOST!=='127.0.0.1:8080' ||
     process.env.FIREBASE_AUTH_EMULATOR_HOST!=='127.0.0.1:9099' ||
     !process.env.FIREBASE_EMULATOR_HUB || process.env.FIREBASE_CONFIG===undefined) {
    throw Error('Refusing to run: required Firebase Auth, Firestore and Functions emulator environment missing or wrong project.');
  }
}
async function invoke(name,token,data){
 const response=await fetch(`${FUNCTIONS_BASE}/${name}`,{
   method:'POST',headers:{'Content-Type':'application/json','Authorization':`Bearer ${token}`},
   body:JSON.stringify({data})
 });
 const body = await response.text();
 let parsed;
 try { parsed = JSON.parse(body); }
 catch {
   throw new Error(`Functions endpoint ${name} returned non-JSON HTTP ${response.status}: ${body.slice(0, 900)}. Check Functions emulator startup logs.`);
 }
 return {status:response.status,result:parsed.result??null,error:parsed.error??null};
}
function migrate(extra=[]) {
 const result=spawnSync(process.execPath,[SCRIPT,'--business',BUSINESS,'--max-guests','300',...extra],{
   cwd:path.resolve(__dirname,'..'),encoding:'utf8',
   env:{...process.env,GCLOUD_PROJECT:PROJECT,FIRESTORE_EMULATOR_HOST:'127.0.0.1:8080',CONFIRM_MAINTENANCE:'YES',ALLOW_LIVE_MIGRATION:''},
   timeout:60000
 });
 return result;
}

test('isolated migration and trusted transactions', {timeout:120000}, async()=>{
 assertEmulatorEnvironment();
 if(!getApps().length)initializeApp({projectId:PROJECT});
 const db=getFirestore();
 const base=db.collection('businesses').doc(BUSINESS);
 const user=await getAuth().createUser({email:'stage-owner@example.invalid',password:'not-a-real-secret-123'});
 const uid=user.uid;
 await base.set({name:'Synthetic Testing Caterer',ownerId:uid,status:'active'});
 await base.collection('members').doc(uid).set({active:true,role:'owner'});
 const authResponse=await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-key',{
  method:'POST',headers:{'Content-Type':'application/json'},
  body:JSON.stringify({email:'stage-owner@example.invalid',password:'not-a-real-secret-123',returnSecureToken:true})
 });
 assert.equal(authResponse.status,200,'Auth emulator must issue an ID token');
 const {idToken}=await authResponse.json();
 const date=Timestamp.fromDate(new Date('2026-10-29T10:00:00.000Z'));
 const books=base.collection('bookings');
 await books.doc('historical').set({status:'confirmed',guests:100,totalPaisa:1000000,eventDate:date});
 await books.doc('b1').set({status:'tentative',guests:120,totalPaisa:600000,eventDate:date});
 await books.doc('b2').set({status:'tentative',guests:100,totalPaisa:500000,eventDate:date});
 await books.doc('refundbook').set({status:'confirmed',guests:20,totalPaisa:1000000,eventDate:Timestamp.fromDate(new Date('2026-10-30T09:00:00.000Z'))});
 await base.collection('payments').doc('old-payment').set({bookingId:'historical',kind:'payment',amountPaisa:400000,method:'cash',reference:'',createdBy:uid});
 await base.collection('payments').doc('refund-old').set({bookingId:'refundbook',kind:'payment',amountPaisa:200000,method:'cash',reference:'',createdBy:uid});
 let result=migrate();assert.equal(result.status,0,`audit failed: ${result.stderr} ${result.stdout}`);
 const audit=JSON.parse(result.stdout);assert.deepEqual(audit.issues,[]);
 assert.equal(audit.capacityDays['2026-10-29'],100);
 assert.equal(audit.paymentBalances.historical,400000);
 result=migrate(['--apply','--confirm-business',BUSINESS]);
 assert.equal(result.status,0,`apply failed: ${result.stderr} ${result.stdout}`);
 assert.equal((await base.collection('capacityDays').doc('2026-10-29').get()).get('reservedGuests'),100);
 assert.equal((await base.collection('paymentBalances').doc('historical').get()).get('netCollectedPaisa'),400000);
 result=migrate(['--apply','--confirm-business',BUSINESS]);
 assert.notEqual(result.status,0,'second apply must not reinitialize/double-count existing counters');
 assert.equal((await base.collection('capacityDays').doc('2026-10-29').get()).get('reservedGuests'),100);
 // With only 200 places left, two overlapping requests (120 + 100) cannot both succeed.
 const [a,b]=await Promise.all([
  invoke('transitionBooking',idToken,{businessId:BUSINESS,bookingId:'b1',status:'confirmed'}),
  invoke('transitionBooking',idToken,{businessId:BUSINESS,bookingId:'b2',status:'confirmed'})
 ]);
 assert.equal([a,b].filter(r=>!r.error).length,1,JSON.stringify([a,b]));
 const capacity=(await base.collection('capacityDays').doc('2026-10-29').get()).get('reservedGuests');
 assert.ok(capacity===220||capacity===200,`unexpected reserved capacity ${capacity}`);
 // Owners can raise capacity, but cannot reduce it below existing reservations.
 const increase=await invoke('updateDailyCapacity',idToken,{businessId:BUSINESS,maxGuestsPerDay:350});
 assert.ok(!increase.error,JSON.stringify(increase));
 assert.equal((await base.collection('settings').doc('capacity').get()).get('maxGuestsPerDay'),350);
 const lower=await invoke('updateDailyCapacity',idToken,{businessId:BUSINESS,maxGuestsPerDay:50});
 assert.ok(lower.error,'cannot lower capacity below reserved guests');
 assert.equal((await base.collection('settings').doc('capacity').get()).get('maxGuestsPerDay'),350);
 const payment={businessId:BUSINESS,bookingId:'historical',amountPaisa:100000,kind:'payment',method:'cash',reference:'test',requestId:'test-idempotency-001'};
 const [p1,p2]=await Promise.all([invoke('recordBookingPayment',idToken,payment),invoke('recordBookingPayment',idToken,payment)]);
 assert.ok(!p1.error&&!p2.error,JSON.stringify([p1,p2]));
 assert.equal((await base.collection('paymentBalances').doc('historical').get()).get('netCollectedPaisa'),500000);
 assert.ok((await base.collection('payments').doc('test-idempotency-001').get()).exists);
 const conflict=await invoke('recordBookingPayment',idToken,{...payment,amountPaisa:200000});
 assert.ok(conflict.error,'conflicting reuse of idempotency key must fail');
 const excessive=await invoke('recordBookingPayment',idToken,{...payment,requestId:'test-refund-high',kind:'refund',amountPaisa:600000});
 assert.ok(excessive.error,'excessive refund must fail');
 const overpay=await invoke('recordBookingPayment',idToken,{...payment,requestId:'test-overpay',amountPaisa:600000});
 assert.ok(overpay.error,'overpayment must fail');
 assert.equal((await base.collection('payments').doc('test-refund-high').get()).exists,false);
 assert.equal((await base.collection('payments').doc('test-overpay').get()).exists,false);
 assert.equal((await base.collection('paymentBalances').doc('historical').get()).get('netCollectedPaisa'),500000);
});
