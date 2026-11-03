 'use strict';
// Read-only by default. APPLY is designed for staging or a coordinated write freeze.
const {initializeApp}=require('firebase-admin/app');
const {getFirestore,FieldValue}=require('firebase-admin/firestore');
const fs=require('node:fs');const path=require('node:path');
const {capacitySummary,paymentSummary}=require('../migration_core');
const args=process.argv.slice(2);const flag=(name)=>{const i=args.indexOf(name);return i<0?null:args[i+1];};
const businessId=flag('--business');const mode=args.includes('--apply')?'apply':'audit';
if(!businessId||!(/^[A-Za-z0-9_-]{1,180}$/.test(businessId))) throw Error('Use --business ID');
if(mode==='apply' && (process.env.CONFIRM_MAINTENANCE!=='YES'||flag('--confirm-business')!==businessId))throw Error('Apply requires CONFIRM_MAINTENANCE=YES and --confirm-business ID');
const emulator=process.env.FIRESTORE_EMULATOR_HOST;
const project=process.env.GCLOUD_PROJECT||process.env.GOOGLE_CLOUD_PROJECT;
if(!project)throw Error('Set GCLOUD_PROJECT explicitly');
if(!emulator && mode==='apply' && process.env.ALLOW_LIVE_MIGRATION!=='YES')throw Error('Live apply disabled; set ALLOW_LIVE_MIGRATION=YES after backup and freeze');
initializeApp({projectId:project});const db=getFirestore();
const stamp=FieldValue.serverTimestamp();
async function readCollection(ref){const snap=await ref.get();return snap.docs.map(d=>({id:d.id,...d.data()}));}
function fromFirestoreDate(v){return v&&typeof v.toDate==='function'?v.toDate():null;}
async function run(){
 const base=db.collection('businesses').doc(businessId);const [bookDocs,payDocs,capacityDocs,balanceDocs,capConfig,readyState]=await Promise.all([
  readCollection(base.collection('bookings')),readCollection(base.collection('payments')),
  readCollection(base.collection('capacityDays')),readCollection(base.collection('paymentBalances')),
  base.collection('settings').doc('capacity').get(),base.collection('settings').doc('trustedOperations').get()]);
 const books=bookDocs.map(b=>({...b,eventDate:fromFirestoreDate(b.eventDate)}));
 const cap=capacitySummary(books);const pays=paymentSummary(books,payDocs);
 const max=Number(flag('--max-guests')|| (capConfig.exists?capConfig.get('maxGuestsPerDay'):0));
 const issues=[...cap.issues,...pays.issues];
 if(!Number.isSafeInteger(max)||max<1)issues.push('Provide a valid --max-guests number or preconfigure settings/capacity');
 for(const [day,count] of Object.entries(cap.days))if(count>max)issues.push(`Existing capacity ${day}: ${count} exceeds max ${max}`);
 if(capacityDocs.length||balanceDocs.length||readyState.exists)issues.push('Trusted counters or migration state already exist: manual reconciliation needed; refusing overwrite');
 const report={project,businessId,mode,timezone:'Asia/Karachi',bookings:books.length,payments:payDocs.length,capacityDays:cap.days,paymentBalances:pays.balances,maxGuestsPerDay:max,issues};
 const dir=path.resolve(process.cwd(),'migration-reports');fs.mkdirSync(dir,{recursive:true});
 const reportFile=path.join(dir,`${businessId}-${Date.now()}-audit.json`);fs.writeFileSync(reportFile,JSON.stringify(report,null,2));
 console.log(JSON.stringify({reportFile,...report},null,2));
 if(mode==='audit')return;
 if(issues.length)throw Error('Migration blocked by audit issues');
 // Fail closed in a maintenance window. Use admin-only writes. A backup is mandatory before live apply.
 // All target docs and gate are committed in one batch (limit 500 operations).
 const targetWrites=Object.keys(cap.days).length+Object.keys(pays.balances).length+(capConfig.exists?0:1)+1;
 if(targetWrites>450)throw Error('Too many counters for one atomic batch; use a reviewed migration plan');
 const batch=db.batch();
 if(!capConfig.exists)batch.create(base.collection('settings').doc('capacity'),{maxGuestsPerDay:max,timezone:'Asia/Karachi',createdAt:stamp});
 for(const [day,reservedGuests]of Object.entries(cap.days))batch.create(base.collection('capacityDays').doc(day),{day,reservedGuests,updatedAt:stamp});
 for(const [bookingId,netCollectedPaisa]of Object.entries(pays.balances))batch.create(base.collection('paymentBalances').doc(bookingId),{netCollectedPaisa,updatedAt:stamp});
 batch.create(base.collection('settings').doc('trustedOperations'),{status:'ready',timezone:'Asia/Karachi',version:1,migratedAt:stamp,bookingsMigrated:books.length,paymentsMigrated:payDocs.length});
 await batch.commit();console.log('Migration committed. Re-run audit with a separate verifier; do not delete historical documents.');
}
run().catch(e=>{console.error(e);process.exitCode=1;});
