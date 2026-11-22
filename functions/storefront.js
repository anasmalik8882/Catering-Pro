'use strict';
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {FieldValue, Timestamp} = require('firebase-admin/firestore');
const {createHash} = require('node:crypto');
const region = 'asia-south1';
const bad = message => { throw new HttpsError('invalid-argument', message); };
function text(value, max, min = 0) {
  if (typeof value !== 'string' || value.trim().length < min || value.length > max) bad('Check the supplied text fields.');
  return value.trim();
}
function id(value) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]{1,180}$/.test(value)) bad('Invalid identifier.');
  return value;
}
function slug(value) {
  if (typeof value !== 'string' || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(value) || value.length < 3 || value.length > 60) bad('Use a slug of 3–60 lowercase letters, numbers and single hyphens.');
  return value;
}
function image(value) {
  const url = text(value, 1600);
  if (!url) return '';
  let parsed;
  try { parsed = new URL(url); } catch { bad('Invalid image URL.'); }
  if (parsed.protocol !== 'https:' || parsed.username || parsed.password || parsed.port || !['firebasestorage.googleapis.com', 'storage.googleapis.com', 'images.unsplash.com'].includes(parsed.hostname)) bad('Use an HTTPS image hosted on Firebase Storage, Google Storage or Unsplash.');
  return url;
}
function selection(value) {
  if (!Array.isArray(value) || value.length > 40) bad('Select up to 40 items per section.');
  const seen = new Set();
  return value.map(item => {
    if (!item || typeof item !== 'object' || Array.isArray(item)) bad('Invalid catalog selection.');
    const itemId = id(item.id);
    if (seen.has(itemId) || typeof item.showPrice !== 'boolean') bad('Invalid selection.');
    seen.add(itemId);
    return {id: itemId, description: text(item.description, 1000), showPrice: item.showPrice, imageUrl: image(item.imageUrl)};
  });
}
function config(data) {
  if (!data || typeof data.published !== 'boolean') bad('Invalid publishing status.');
  const phone = text(data.phone, 30);
  const email = text(data.email, 160);
  if (phone && (!/^[+\d() .-]{7,30}$/.test(phone) || phone.replace(/\D/g, '').length < 7 || phone.replace(/\D/g, '').length > 15)) bad('Enter a valid public phone number.');
  if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) bad('Enter a valid public email address.');
  return {slug: slug(data.slug), displayName: text(data.displayName, 120, 3), description: text(data.description, 3000),
    phone, email, location: text(data.location, 200),
    services: text(data.services, 1000), logoUrl: image(data.logoUrl), heroUrl: image(data.heroUrl),
    published: data.published, menus: selection(data.menus), packages: selection(data.packages)};
}
function inquiry(data, now = new Date()) {
  const date = text(data.eventDate, 10, 10);
  const parsed = new Date(`${date}T00:00:00.000Z`);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || !Number.isFinite(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== date || date < now.toISOString().slice(0, 10) || parsed.getTime() > now.getTime() + 366 * 3 * 86400000) bad('Choose a valid event date within the next three years.');
  if (!Number.isSafeInteger(data.guests) || data.guests < 1 || data.guests > 100000) bad('Enter 1–100000 guests.');
  const phone = text(data.phone, 30, 7);
  const email = text(data.email, 160);
  if (!/^[+\d() .-]{7,30}$/.test(phone) || phone.replace(/\D/g, '').length < 7 || phone.replace(/\D/g, '').length > 15 || (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))) bad('Enter valid contact details.');
  return {name: text(data.name, 120, 2), phone, email, eventType: text(data.eventType, 60, 2),
    eventDate: date, guests: data.guests, packageId: data.packageId ? id(data.packageId) : '', requirements: text(data.requirements, 2000)};
}
const hash = value => createHash('sha256').update(value).digest('hex');
module.exports = function register(db) {
  const callable = handler => onCall({region, maxInstances: 20, timeoutSeconds: 30}, handler);
  function refs(businessId, uid) {
    const base = db().collection('businesses').doc(id(businessId));
    return {base, member: base.collection('members').doc(uid), settings: base.collection('settings').doc('storefront')};
  }
  function owner(business, member, uid) {
    if (!business.exists || business.get('ownerId') !== uid || !member.exists || member.get('active') !== true || member.get('role') !== 'owner') throw new HttpsError('permission-denied', 'Business owner access required.');
  }
  const getStorefrontSettings = callable(async req => {
    if (!req.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
    const r = refs(req.data?.businessId, req.auth.uid);
    return db().runTransaction(async tx => {
      const [business, member, settings] = await tx.getAll(r.base, r.member, r.settings);
      owner(business, member, req.auth.uid);
      return {config: settings.exists ? settings.get('config') : null};
    });
  });
  const saveStorefront = callable(async req => {
    if (!req.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
    const c = config(req.data?.config);
    const r = refs(req.data.businessId, req.auth.uid);
    return db().runTransaction(async tx => {
      const [business, member, previous] = await tx.getAll(r.base, r.member, r.settings);
      owner(business, member, req.auth.uid);
      if (business.get('status') !== 'active' && c.published) throw new HttpsError('failed-precondition', 'This business cannot publish.');
      const publicRef = db().collection('publicStorefronts').doc(c.slug);
      const existing = await tx.get(publicRef);
      if (existing.exists && existing.get('businessId') !== r.base.id) throw new HttpsError('already-exists', 'This slug is already reserved.');
      const sources = [...c.menus.map(i => r.base.collection('menuItems').doc(i.id)), ...c.packages.map(i => r.base.collection('packages').doc(i.id))];
      const docs = sources.length ? await tx.getAll(...sources) : [];
      function publishItem(item, index, packageItem) {
        const source = docs[index];
        if (!source.exists || source.get('active') !== true) throw new HttpsError('failed-precondition', 'A selected menu or package is missing or inactive.');
        const result = {id: item.id, name: text(source.get('name'), 120, 1), description: item.description, imageUrl: item.imageUrl};
        if (packageItem) {
          result.minimumGuests = source.get('minimumGuests') || 0;
          result.pricingMode = text(source.get('pricingMode') || '', 50);
        } else result.unit = text(source.get('unit') || '', 50);
        if (item.showPrice) {
          const amount = source.get('pricePaisa');
          if (!Number.isSafeInteger(amount) || amount < 0 || amount > 1e13) bad('Invalid catalog price.');
          result.pricePaisa = amount;
        }
        return result;
      }
      const publicData = {...c, menus: c.menus.map((v, i) => publishItem(v, i, false)), packages: c.packages.map((v, i) => publishItem(v, i + c.menus.length, true))};
      const previousSlug = previous.get('config')?.slug;
      if (previousSlug && previousSlug !== c.slug) tx.delete(db().collection('publicStorefronts').doc(previousSlug));
      tx.set(r.settings, {config: c, updatedBy: req.auth.uid, updatedAt: FieldValue.serverTimestamp()});
      tx.set(publicRef, {businessId: r.base.id, publicData, updatedAt: FieldValue.serverTimestamp()});
      return {slug: c.slug, published: c.published};
    });
  });
  async function visible(tx, value) {
    const snapshot = await tx.get(db().collection('publicStorefronts').doc(slug(value)));
    if (!snapshot.exists || snapshot.get('publicData.published') !== true) throw new HttpsError('not-found', 'Storefront unavailable.');
    const base = db().collection('businesses').doc(snapshot.get('businessId'));
    const business = await tx.get(base);
    if (!business.exists || business.get('status') !== 'active') throw new HttpsError('not-found', 'Storefront unavailable.');
    return {snapshot, base};
  }
  const getPublicStorefront = callable(req => db().runTransaction(async tx => {
    const {snapshot} = await visible(tx, req.data?.slug);
    return snapshot.get('publicData');
  }));
  const submitStorefrontInquiry = callable(async req => {
    const data = req.data || {};
    const validated = inquiry(data);
    const requestId = id(data.requestId);
    const contentHash = hash(JSON.stringify(validated));
    // Never trust a client-supplied tenant or forwarded header. Cloud Functions
    // supplies rawRequest.ip through its trusted proxy configuration.
    const ip = req.rawRequest.ip || req.rawRequest.socket?.remoteAddress || 'unknown';
    const window = Math.floor(Date.now() / 3600000);
    return db().runTransaction(async tx => {
      const {snapshot, base} = await visible(tx, data.slug);
      if (validated.packageId && !snapshot.get('publicData.packages').some(p => p.id === validated.packageId)) bad('Choose a published package.');
      const ref = base.collection('publicInquiries').doc(hash(`${data.slug}:${requestId}`));
      const prior = await tx.get(ref);
      if (prior.exists) {
        if (prior.get('contentHash') !== contentHash) throw new HttpsError('already-exists', 'Submission identifier already used.');
        return {inquiryId: ref.id};
      }
      const limits = [
        [hash(`ip:${ip}:${window}`), 20],
        [hash(`contact:${base.id}:${validated.phone.replace(/\D/g, '')}:${window}`), 3],
        [hash(`tenant:${base.id}:${window}`), 200],
      ];
      const limitRefs = limits.map(([key]) => db().collection('storefrontRateLimits').doc(key));
      const counters = await tx.getAll(...limitRefs);
      if (counters.some((c, i) => (c.get('count') || 0) >= limits[i][1])) throw new HttpsError('resource-exhausted', 'Too many requests. Please try again later.');
      counters.forEach((c, i) => tx.set(limitRefs[i], {count: (c.get('count') || 0) + 1, expiresAt: Timestamp.fromMillis((window + 2) * 3600000)}));
      tx.create(ref, {...validated, businessId: base.id, slug: data.slug, contentHash, status: 'new', source: 'public_storefront', createdAt: FieldValue.serverTimestamp()});
      return {inquiryId: ref.id};
    });
  });
  return {getStorefrontSettings, saveStorefront, getPublicStorefront, submitStorefrontInquiry};
};
module.exports.validation = {slug, config, inquiry, image};
