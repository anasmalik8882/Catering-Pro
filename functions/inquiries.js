'use strict';
// Milestone 11: website inquiry → sales pipeline.
//
// Public storefront submissions land in businesses/{bid}/publicInquiries and
// are never writable by clients. Sales staff move them through this trusted
// callable, which can convert one into a customer + internal sales inquiry.
// Conversion is idempotent (deterministic document ids) and never touches
// quotations, bookings, payments or capacity.
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {FieldValue, Timestamp} = require('firebase-admin/firestore');

const region = 'asia-south1';
const salesRoles = new Set(['owner', 'manager', 'sales']);
const dismissReasons = new Set(['spam', 'duplicate', 'unavailable', 'not_interested', 'other']);
// Legal public-inquiry status transitions per action.
const actions = {
  contacted: {from: ['new'], to: 'contacted'},
  convert: {from: ['new', 'contacted'], to: 'converted'},
  dismiss: {from: ['new', 'contacted'], to: 'dismissed'},
  reopen: {from: ['dismissed'], to: 'new'},
};

const bad = message => { throw new HttpsError('invalid-argument', message); };
function id(value, label = 'identifier') {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]{1,180}$/.test(value)) bad(`Invalid ${label}.`);
  return value;
}
const digits = value => String(value || '').replace(/\D/g, '');

// Public event dates are calendar days (YYYY-MM-DD) chosen by the visitor.
// Store them at Karachi midday so dayKey(Asia/Karachi) matches the chosen day.
function karachiEventDate(day) {
  if (typeof day !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(day)) {
    throw new HttpsError('failed-precondition', 'Website inquiry has an invalid event date.');
  }
  const date = new Date(`${day}T12:00:00+05:00`);
  if (!Number.isFinite(date.getTime())) throw new HttpsError('failed-precondition', 'Website inquiry has an invalid event date.');
  return Timestamp.fromDate(date);
}

function salesNotes(inquiry, packageName) {
  const parts = ['Website inquiry'];
  if (packageName) parts.push(`Package of interest: ${packageName}`);
  if (inquiry.get('email')) parts.push(`Email: ${inquiry.get('email')}`);
  const requirements = String(inquiry.get('requirements') || '').trim();
  if (requirements) parts.push(`Requirements: ${requirements}`);
  return parts.join('\n').slice(0, 2000);
}

function validate(data) {
  if (!data || typeof data !== 'object') bad('Invalid request.');
  const action = data.action;
  if (!Object.prototype.hasOwnProperty.call(actions, action)) bad('Unknown action.');
  const result = {businessId: id(data.businessId, 'business'), inquiryId: id(data.inquiryId, 'inquiry'), action};
  if (action === 'convert' && data.customerId != null && data.customerId !== '') result.customerId = id(data.customerId, 'customer');
  if (action === 'dismiss') {
    const reason = data.reason ?? 'other';
    if (!dismissReasons.has(reason)) bad('Invalid dismissal reason.');
    result.reason = reason;
  }
  return result;
}

module.exports = function register(db) {
  const reviewPublicInquiry = onCall({region, maxInstances: 20, timeoutSeconds: 30}, async req => {
    if (!req.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
    const input = validate(req.data);
    const uid = req.auth.uid;
    const base = db().collection('businesses').doc(input.businessId);
    const memberRef = base.collection('members').doc(uid);
    const inquiryRef = base.collection('publicInquiries').doc(input.inquiryId);
    return db().runTransaction(async tx => {
      const [business, member, inquiry] = await tx.getAll(base, memberRef, inquiryRef);
      if (!business.exists || !member.exists || member.get('active') !== true || !salesRoles.has(member.get('role'))) {
        throw new HttpsError('permission-denied', 'Owner, manager or sales access required.');
      }
      if (!inquiry.exists) throw new HttpsError('not-found', 'Website inquiry not found.');
      const current = inquiry.get('status');
      const rule = actions[input.action];
      // Idempotent retry of a completed conversion returns the original result.
      if (input.action === 'convert' && current === 'converted') {
        return {status: 'converted', customerId: inquiry.get('customerId'), salesInquiryId: inquiry.get('salesInquiryId'), duplicate: true};
      }
      if (!rule.from.includes(current)) throw new HttpsError('failed-precondition', `Cannot ${input.action} an inquiry that is ${current}.`);
      const audit = {status: rule.to, handledBy: uid, handledAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()};
      if (input.action !== 'convert') {
        if (input.action === 'dismiss') audit.dismissReason = input.reason;
        if (input.action === 'reopen') audit.dismissReason = FieldValue.delete();
        tx.update(inquiryRef, audit);
        return {status: rule.to};
      }

      // --- Conversion: all reads first, then writes. ---
      const salesRef = base.collection('inquiries').doc(inquiryRef.id);
      const packageId = inquiry.get('packageId');
      const reads = [tx.get(salesRef), packageId ? tx.get(base.collection('packages').doc(packageId)) : Promise.resolve(null)];
      let customerRef = null;
      let customerCreated = false;
      if (input.customerId) {
        customerRef = base.collection('customers').doc(input.customerId);
        reads.push(tx.get(customerRef));
      } else {
        // Reuse an existing customer with the same phone number.
        reads.push(tx.get(base.collection('customers').where('phone', '==', inquiry.get('phone')).limit(1)));
      }
      const [existingSales, packageDoc, customerLookup] = await Promise.all(reads);
      if (existingSales.exists) throw new HttpsError('failed-precondition', 'A sales inquiry already exists for this website inquiry.');
      if (input.customerId) {
        if (!customerLookup.exists) throw new HttpsError('not-found', 'Selected customer not found.');
      } else if (!customerLookup.empty && digits(customerLookup.docs[0].get('phone')) === digits(inquiry.get('phone'))) {
        customerRef = customerLookup.docs[0].ref;
      } else {
        // Deterministic id keeps conversion idempotent under concurrent retries.
        customerRef = base.collection('customers').doc(`web_${inquiryRef.id.slice(0, 40)}`);
        customerCreated = true;
      }
      const now = FieldValue.serverTimestamp();
      if (customerCreated) {
        tx.create(customerRef, {
          name: String(inquiry.get('name') || '').slice(0, 120),
          phone: String(inquiry.get('phone') || '').slice(0, 30),
          email: String(inquiry.get('email') || '').slice(0, 160),
          notes: 'Created from a website storefront inquiry.',
          createdBy: uid, createdAt: now, updatedAt: now,
        });
      }
      const packageName = packageDoc && packageDoc.exists ? String(packageDoc.get('name') || '') : '';
      tx.create(salesRef, {
        customerId: customerRef.id,
        eventType: String(inquiry.get('eventType') || 'Other').slice(0, 60),
        guests: inquiry.get('guests'),
        eventDate: karachiEventDate(inquiry.get('eventDate')),
        source: 'Website',
        notes: salesNotes(inquiry, packageName),
        status: 'new',
        followUpAt: null,
        publicInquiryId: inquiryRef.id,
        createdBy: uid, createdAt: now, updatedAt: now,
      });
      tx.update(inquiryRef, {...audit, customerId: customerRef.id, salesInquiryId: salesRef.id, customerCreated});
      return {status: 'converted', customerId: customerRef.id, salesInquiryId: salesRef.id, customerCreated};
    });
  });
  return {reviewPublicInquiry};
};
module.exports.validation = {validate, karachiEventDate, salesNotes};
