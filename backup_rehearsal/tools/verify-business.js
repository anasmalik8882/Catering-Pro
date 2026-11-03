'use strict';
// Read-only record-level summary. Run from functions/ (has firebase-admin dependency).
const path = require('node:path');
const { createRequire } = require('node:module');
const projectRequire = createRequire(path.resolve(process.cwd(), 'package.json'));
const { initializeApp } = projectRequire('firebase-admin/app');
const { getFirestore } = projectRequire('firebase-admin/firestore');
const crypto = require('node:crypto');
const args = process.argv.slice(2);
function value(k) { const index = args.indexOf(k); return index >= 0 ? args[index + 1] : undefined; }
const project = value('--project');
const businessId = value('--business');
const output = value('--output');
if (!project || !/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/.test(project)) throw Error('Provide --project PROJECT_ID');
if (!businessId || !/^[a-zA-Z0-9_-]{1,180}$/.test(businessId)) throw Error('Provide --business BUSINESS_DOC_ID');
if (process.env.FIRESTORE_EMULATOR_HOST) throw Error('Unset FIRESTORE_EMULATOR_HOST; this verifier is for independently hosted Firestore projects.');
initializeApp({ projectId: project });
const db = getFirestore();
const collections = ['bookings', 'payments', 'capacityDays', 'paymentBalances'];
const stable = (v) => {
  if (v === null || typeof v !== 'object') return v;
  if (typeof v.toDate === 'function') return { _timestamp: v.toDate().toISOString() };
  if (Array.isArray(v)) return v.map(stable);
  if (v instanceof Uint8Array) return { _bytes: Buffer.from(v).toString('base64') };
  return Object.fromEntries(Object.keys(v).sort().map(k => [k, stable(v[k])]));
};
async function go() {
 const business = db.collection('businesses').doc(businessId);
 const exists = await business.get();
 if (!exists.exists) throw Error(`Business ${businessId} not found in ${project}`);
 const result = { project, businessId, checkedAt: new Date().toISOString(), counts: {}, fingerprints: {} };
 for (const collection of collections) {
   const snap = await business.collection(collection).get();
   const entries = snap.docs.map(doc => [doc.id, stable(doc.data())]).sort((a,b)=>a[0].localeCompare(b[0]));
   result.counts[collection] = entries.length;
   result.fingerprints[collection] = crypto.createHash('sha256').update(JSON.stringify(entries)).digest('hex');
 }
 const json = JSON.stringify(result, null, 2);
 if (output) {
   const fs = require('node:fs');
   if (fs.existsSync(output)) throw Error('Refusing to overwrite existing verification file');
   fs.writeFileSync(output, json + '\n', { flag: 'wx' });
 }
 console.log(json);
}
go().catch(e => { console.error(e.message); process.exitCode = 1; });
