'use strict';
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {initializeApp} = require('firebase-admin/app');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
// Avoid initializing Admin services during function discovery. The emulator
// loads this module to discover exports before it invokes any callable.
let firestoreInstance;
function firestore() {
  if (!firestoreInstance) {
    initializeApp();
    firestoreInstance = getFirestore();
  }
  return firestoreInstance;
}
const region = 'asia-south1';
const roles = new Set(['owner', 'manager']);
const transitions = {
  tentative: ['confirmed','cancelled'],
  confirmed: ['preparation','cancelled'],
  preparation: ['ready','cancelled'],
  ready: ['in_progress','cancelled'],
  in_progress: ['completed'],
  completed: ['closed'],
};
const active = new Set(['confirmed','preparation','ready','in_progress','completed','closed']);
function fail(code, text) {throw new HttpsError(code,text);}
function string(v, max = 120) {return typeof v==='string' && v.length>0 && v.length<=max;}
async function authorize(req, businessId) {
  if (!req.auth) fail('unauthenticated','Sign in first.');
  if (!string(businessId,180)) fail('invalid-argument','Invalid business.');
  const base = firestore().collection('businesses').doc(businessId);
  const member = await base.collection('members').doc(req.auth.uid).get();
  if (!member.exists || member.get('active') !== true || !roles.has(member.get('role'))) {
    fail('permission-denied','Owner or manager permission required.');
  }
  return base;
}
const {dateKey, capacitySummary, paymentSummary} = require('./migration_core');
function dayKey(timestamp) {
  if (!timestamp || typeof timestamp.toDate !== 'function') fail('failed-precondition','Event date missing.');
  return dateKey(timestamp.toDate(), 'Asia/Karachi');
}
async function ensureMigrationReady(tx, base) {
  const state = await tx.get(base.collection('settings').doc('trustedOperations'));
  if (!state.exists || state.get('status') !== 'ready' || state.get('timezone') !== 'Asia/Karachi') {
    fail('failed-precondition','Trusted operations are not reconciled. Complete migration first.');
  }
}

exports.transitionBooking = onCall({region, enforceAppCheck:false}, async req => {
  const {businessId, bookingId, status} = req.data || {};
  if (!string(bookingId,180) || !string(status,30)) fail('invalid-argument','Invalid booking/status.');
  const base = await authorize(req,businessId);
  const bookingRef = base.collection('bookings').doc(bookingId);
  return firestore().runTransaction(async tx => {
    await ensureMigrationReady(tx, base);
    const snapshot = await tx.get(bookingRef);
    if (!snapshot.exists) fail('not-found','Booking not found.');
    const previous = snapshot.get('status');
    if (!(transitions[previous] || []).includes(status)) fail('failed-precondition','Invalid status transition.');
    const guests = snapshot.get('guests');
    if (!Number.isSafeInteger(guests) || guests < 1) fail('failed-precondition','Invalid guest count.');
    const key = dayKey(snapshot.get('eventDate'));
    const capacityRef = base.collection('capacityDays').doc(key);
    const configRef = base.collection('settings').doc('capacity');
    // Fetch ALL documents before any transaction writes.
    const [capacity, config] = await Promise.all([tx.get(capacityRef),tx.get(configRef)]);
    const entering = !active.has(previous) && active.has(status);
    const leaving = active.has(previous) && status==='cancelled';
    if (entering) {
      if (!config.exists) fail('failed-precondition','Configure capacity settings first.');
      const maximum = config.get('maxGuestsPerDay');
      if (!Number.isSafeInteger(maximum) || maximum<1) fail('failed-precondition','Invalid capacity configuration.');
      const current = capacity.exists ? capacity.get('reservedGuests') : 0;
      if (!Number.isSafeInteger(current) || current<0 || current+guests>maximum) {
        fail('resource-exhausted','Not enough daily catering capacity.');
      }
      tx.set(capacityRef, {reservedGuests: current+guests, day:key, updatedAt:FieldValue.serverTimestamp()}, {merge:true});
    }
    if (leaving) {
      const current = capacity.exists ? capacity.get('reservedGuests') : 0;
      if (!Number.isSafeInteger(current) || current<guests) fail('failed-precondition','Reservation counter inconsistent.');
      tx.set(capacityRef,{reservedGuests:current-guests,day:key,updatedAt:FieldValue.serverTimestamp()},{merge:true});
    }
    tx.update(bookingRef,{status,updatedAt:FieldValue.serverTimestamp()});
    return {bookingId,status,day:key};
  });
});
exports.recordBookingPayment = onCall({region,enforceAppCheck:false}, async req => {
  const {businessId,bookingId,amountPaisa,kind,method,reference,requestId} = req.data || {};
  if (!string(bookingId,180) || !string(requestId,100) || !/^[a-zA-Z0-9-]+$/.test(requestId) ||
      !Number.isSafeInteger(amountPaisa) || amountPaisa<1 || amountPaisa>1e12 ||
      !['payment','refund'].includes(kind) || !string(method,60) ||
      typeof reference!=='string' || reference.length>300) fail('invalid-argument','Invalid payment data.');
  const base = await authorize(req,businessId);
  const bookingRef = base.collection('bookings').doc(bookingId);
  const balanceRef = base.collection('paymentBalances').doc(bookingId);
  const paymentRef = base.collection('payments').doc(requestId);
  return firestore().runTransaction(async tx => {
    await ensureMigrationReady(tx, base);
    const [booking, balance, prior] = await Promise.all([tx.get(bookingRef),tx.get(balanceRef),tx.get(paymentRef)]);
    if (prior.exists) {
      if (prior.get('createdBy')!==req.auth.uid || prior.get('bookingId')!==bookingId || prior.get('amountPaisa')!==amountPaisa || prior.get('kind')!==kind || prior.get('method')!==method || prior.get('reference')!==reference) fail('already-exists','Idempotency key reused with different data.');
      return {paymentId:requestId,duplicate:true};
    }
    if (!booking.exists) fail('not-found','Booking not found.');
    if (booking.get('status')==='cancelled') fail('failed-precondition','Cancelled booking: manual reconciliation required.');
    const total = booking.get('totalPaisa');
    if (!Number.isSafeInteger(total) || total<0) fail('failed-precondition','Invalid contract total.');
    const current = balance.exists ? balance.get('netCollectedPaisa') : 0;
    if (!Number.isSafeInteger(current) || current<0 || current>total) fail('failed-precondition','Payment balance inconsistent; reconcile before continuing.');
    const next = current + (kind==='payment'?amountPaisa:-amountPaisa);
    if (next<0 || next>total) fail('failed-precondition','Payment exceeds balance or refund exceeds net collections.');
    tx.create(paymentRef,{bookingId,amountPaisa,kind,method,reference,createdBy:req.auth.uid,createdAt:FieldValue.serverTimestamp()});
    tx.set(balanceRef,{netCollectedPaisa:next,updatedAt:FieldValue.serverTimestamp()});
    return {paymentId:requestId,netCollectedPaisa:next};
  });
});

// Initial setup only. Refuse to initialize capacity if confirmed or later
// bookings exist, since their existing reservations must first be migrated.
exports.initializeDailyCapacity = onCall({region,enforceAppCheck:false},async req => {
  const {businessId,maxGuestsPerDay} = req.data || {};
  if (!Number.isSafeInteger(maxGuestsPerDay) || maxGuestsPerDay<1 || maxGuestsPerDay>100000) fail('invalid-argument','Invalid maximum guests.');
  const base = await authorize(req,businessId);
  const member = await base.collection('members').doc(req.auth.uid).get();
  if (member.get('role')!=='owner') fail('permission-denied','Only owner can initialize capacity.');
  const configRef = base.collection('settings').doc('capacity');
  const configured = await configRef.get();
  if (configured.exists) fail('already-exists','Capacity already initialized; use a controlled migration to change it.');
  const [anyBookings, anyPayments] = await Promise.all([
    base.collection('bookings').limit(1).get(), base.collection('payments').limit(1).get(),
  ]);
  if (!anyBookings.empty || !anyPayments.empty) fail('failed-precondition','Existing bookings or payments require reconciliation.');
  // Prevent racing initializations; recheck config inside transaction.
  return firestore().runTransaction(async tx=> {
    const stateRef = base.collection('settings').doc('trustedOperations');
    const [config, state] = await Promise.all([tx.get(configRef), tx.get(stateRef)]);
    if (state.exists) fail('already-exists','Trusted operations already initialized.');
    if (config.exists) fail('already-exists','Already initialized.');
    tx.create(configRef,{maxGuestsPerDay,timezone:'Asia/Karachi',createdBy:req.auth.uid,createdAt:FieldValue.serverTimestamp()});
    tx.create(stateRef,{status:'ready',timezone:'Asia/Karachi',version:1,createdAt:FieldValue.serverTimestamp()});
    return {maxGuestsPerDay};
  });
});

// Owner-only adjustment of an existing capacity limit. Read all reservation
// counters inside the same transaction as the configuration update, so a
// concurrent booking confirmation cannot evade the new limit.
exports.updateDailyCapacity = onCall({region,enforceAppCheck:false},async req => {
  const {businessId,maxGuestsPerDay} = req.data || {};
  if (!Number.isSafeInteger(maxGuestsPerDay) || maxGuestsPerDay<1 || maxGuestsPerDay>100000)
    fail('invalid-argument','Invalid maximum guests.');
  const base = await authorize(req,businessId);
  const member = await base.collection('members').doc(req.auth.uid).get();
  if (member.get('role')!=='owner') fail('permission-denied','Only owner can change capacity.');
  return firestore().runTransaction(async tx => {
    await ensureMigrationReady(tx,base);
    const configRef = base.collection('settings').doc('capacity');
    const [config,days] = await Promise.all([
      tx.get(configRef),tx.get(base.collection('capacityDays')),
    ]);
    if (!config.exists) fail('failed-precondition','Initialize or migrate capacity first.');
    let highestReserved = 0;
    for (const day of days.docs) {
      const reserved = day.get('reservedGuests');
      if (!Number.isSafeInteger(reserved) || reserved<0)
        fail('failed-precondition','Invalid capacity counter; reconcile before changing limit.');
      highestReserved = Math.max(highestReserved,reserved);
    }
    if (maxGuestsPerDay<highestReserved)
      fail('failed-precondition',`Cannot set capacity below ${highestReserved} already reserved guests.`);
    tx.update(configRef,{
      maxGuestsPerDay,
      updatedBy:req.auth.uid,
      updatedAt:FieldValue.serverTimestamp(),
    });
    return {maxGuestsPerDay,highestReserved};
  });
});
