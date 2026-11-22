'use strict';
// Milestone 12: SaaS super-admin callables.
//
// Platform admins are identified ONLY by the Firebase Auth custom claim
// `platformAdmin: true`, granted out-of-band with tools/grant_platform_admin.js.
// Tenant membership never grants platform access, and these endpoints never
// return private financial records (payments, ledgers) — only counts.
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {FieldValue, FieldPath} = require('firebase-admin/firestore');
const {getAuth} = require('firebase-admin/auth');

const region = 'asia-south1';
const statuses = new Set(['active', 'suspended']);
const bad = message => { throw new HttpsError('invalid-argument', message); };

function id(value, label = 'identifier') {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]{1,180}$/.test(value)) bad(`Invalid ${label}.`);
  return value;
}
function requireAdmin(req) {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  if (req.auth.token?.platformAdmin !== true) throw new HttpsError('permission-denied', 'Platform administrator access required.');
  return req.auth.uid;
}
function validateList(data = {}) {
  const limit = data.limit ?? 25;
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > 50) bad('Limit must be 1–50.');
  const status = data.status ?? '';
  if (status !== '' && !statuses.has(status)) bad('Invalid status filter.');
  const after = data.after ? id(data.after, 'page cursor') : '';
  return {limit, status, after};
}
function validateStatus(data = {}) {
  const status = data.status;
  if (!statuses.has(status)) bad('Status must be active or suspended.');
  const reason = typeof data.reason === 'string' ? data.reason.trim() : '';
  if (reason.length > 500) bad('Reason must be at most 500 characters.');
  if (status === 'suspended' && reason.length < 3) bad('Give a reason for suspension.');
  return {businessId: id(data.businessId, 'business'), status, reason};
}
const millis = value => (value && typeof value.toMillis === 'function' ? value.toMillis() : null);

async function ownerEmails(uids) {
  const unique = [...new Set(uids.filter(Boolean))];
  if (!unique.length) return {};
  const result = await getAuth().getUsers(unique.map(uid => ({uid})));
  return Object.fromEntries(result.users.map(u => [u.uid, u.email || u.phoneNumber || '']));
}

module.exports = function register(db) {
  const callable = handler => onCall({region, maxInstances: 10, timeoutSeconds: 60}, handler);
  function summary(doc, emails) {
    return {
      id: doc.id,
      name: String(doc.get('name') || ''),
      city: String(doc.get('city') || ''),
      phone: String(doc.get('phone') || ''),
      status: String(doc.get('status') || ''),
      ownerId: String(doc.get('ownerId') || ''),
      ownerEmail: emails[doc.get('ownerId')] || '',
      createdAt: millis(doc.get('createdAt')),
      statusReason: String(doc.get('statusReason') || ''),
    };
  }

  const adminListBusinesses = callable(async req => {
    requireAdmin(req);
    const {limit, status, after} = validateList(req.data || {});
    let query = db().collection('businesses');
    if (status) query = query.where('status', '==', status);
    query = query.orderBy(FieldPath.documentId()).limit(limit + 1);
    if (after) query = query.startAfter(after);
    const snapshot = await query.get();
    const docs = snapshot.docs.slice(0, limit);
    const emails = await ownerEmails(docs.map(d => d.get('ownerId')));
    return {
      businesses: docs.map(d => summary(d, emails)),
      next: snapshot.docs.length > limit ? docs[docs.length - 1].id : null,
    };
  });

  const adminGetBusiness = callable(async req => {
    requireAdmin(req);
    const businessId = id(req.data?.businessId, 'business');
    const base = db().collection('businesses').doc(businessId);
    const business = await base.get();
    if (!business.exists) throw new HttpsError('not-found', 'Business not found.');
    const countOf = async name => (await base.collection(name).count().get()).data().count;
    const [members, storefront, subscription, ...counts] = await Promise.all([
      base.collection('members').get(),
      base.collection('settings').doc('storefront').get(),
      base.collection('settings').doc('subscription').get(),
      ...['customers', 'inquiries', 'publicInquiries', 'quotations', 'bookings'].map(countOf),
    ]);
    const emails = await ownerEmails([business.get('ownerId'), ...members.docs.map(m => m.id)]);
    const config = storefront.exists ? storefront.get('config') || {} : {};
    return {
      business: summary(business, emails),
      members: members.docs.map(m => ({uid: m.id, email: emails[m.id] || '', role: String(m.get('role') || ''), active: m.get('active') === true})),
      usage: Object.fromEntries(['customers', 'inquiries', 'publicInquiries', 'quotations', 'bookings'].map((k, i) => [k, counts[i]])),
      storefront: storefront.exists ? {slug: String(config.slug || ''), published: config.published === true} : null,
      subscription: subscription.exists ? {plan: String(subscription.get('plan') || ''), status: String(subscription.get('status') || ''), currentPeriodEnd: millis(subscription.get('currentPeriodEnd'))} : null,
    };
  });

  const adminSetBusinessStatus = callable(async req => {
    const adminUid = requireAdmin(req);
    const input = validateStatus(req.data || {});
    const base = db().collection('businesses').doc(input.businessId);
    const logRef = db().collection('platformAuditLogs').doc();
    return db().runTransaction(async tx => {
      const business = await tx.get(base);
      if (!business.exists) throw new HttpsError('not-found', 'Business not found.');
      const previous = business.get('status');
      if (previous === input.status) return {status: input.status, unchanged: true};
      tx.update(base, {
        status: input.status,
        statusReason: input.status === 'suspended' ? input.reason : FieldValue.delete(),
        statusChangedAt: FieldValue.serverTimestamp(),
        statusChangedBy: adminUid,
      });
      tx.create(logRef, {
        action: input.status === 'suspended' ? 'business.suspend' : 'business.reactivate',
        businessId: input.businessId, previous: previous ?? null, next: input.status,
        reason: input.reason, actorUid: adminUid, actorEmail: String(req.auth.token.email || ''),
        createdAt: FieldValue.serverTimestamp(),
      });
      return {status: input.status};
    });
  });

  const adminListAuditLog = callable(async req => {
    requireAdmin(req);
    const limit = req.data?.limit ?? 50;
    if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100) bad('Limit must be 1–100.');
    let query = db().collection('platformAuditLogs').orderBy('createdAt', 'desc').limit(limit);
    if (req.data?.businessId) query = db().collection('platformAuditLogs').where('businessId', '==', id(req.data.businessId, 'business')).limit(limit);
    const snapshot = await query.get();
    const entries = snapshot.docs.map(d => ({id: d.id, ...d.data(), createdAt: millis(d.get('createdAt'))}));
    entries.sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0));
    return {entries};
  });

  return {adminListBusinesses, adminGetBusiness, adminSetBusinessStatus, adminListAuditLog};
};
module.exports.validation = {requireAdmin, validateList, validateStatus};
