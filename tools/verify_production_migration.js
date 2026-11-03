'use strict';
// Read-only verification of a single business. Never writes to Firestore.
const {initializeApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {capacitySummary,paymentSummary} = require('../functions/migration_core');
const args=process.argv.slice(2);
function option(k){const i=args.indexOf(k);return i<0?null:args[i+1];}
const project=process.env.GCLOUD_PROJECT;
const businessId=option('--business');
if(project!=='catering-pro-b001d' && project!=='caterer-pro-staging') throw Error('Set GCLOUD_PROJECT to explicit allowlisted project');
if(process.env.FIRESTORE_EMULATOR_HOST) throw Error('Unsetting FIRESTORE_EMULATOR_HOST is required for this live read-only check');
if(!businessId || !/^[a-zA-Z0-9_-]{1,180}$/.test(businessId)) throw Error('Specify --business ID');
if(args.includes('--apply') || args.includes('--write')) throw Error('Read-only verifier; write flags are not accepted');
initializeApp({projectId:project});const db=getFirestore();
const equal=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
async function docs(q){const s=await q.get();return s.docs.map(d=>({id:d.id,...d.data()}));}
async function main(){
 const base=db.collection('businesses').doc(businessId);
 const [business,books,pays,capacityDocs,balanceDocs,config,state]=await Promise.all([
 base.get(),docs(base.collection('bookings')),docs(base.collection('payments')),
 docs(base.collection('capacityDays')),docs(base.collection('paymentBalances')),
 base.collection('settings').doc('capacity').get(),base.collection('settings').doc('trustedOperations').get()]);
 const issues=[];
 if(!business.exists) issues.push('Business document does not exist');
 const transformed=books.map(b=>({...b,eventDate: b.eventDate&&typeof b.eventDate.toDate==='function'?b.eventDate.toDate():null}));
 const expectedCap=capacitySummary(transformed),expectedPay=paymentSummary(transformed,pays);
 issues.push(...expectedCap.issues,...expectedPay.issues);
 const migrated=state.exists && state.get('status')==='ready';
 if(state.exists && !migrated) issues.push('Trusted operations state exists but is not ready');
 if(!migrated && (capacityDocs.length || balanceDocs.length)) issues.push('Counters exist without ready migration state');
 const capActual=Object.fromEntries(capacityDocs.map(d=>[d.id,d.reservedGuests]));
 const payActual=Object.fromEntries(balanceDocs.map(d=>[d.id,d.netCollectedPaisa]));
 if(migrated){
  const exCap=Object.fromEntries(Object.entries(expectedCap.days).sort());
  const exPay=Object.fromEntries(Object.entries(expectedPay.balances).sort());
  const actualCap=Object.fromEntries(Object.entries(capActual).sort());
  const actualPay=Object.fromEntries(Object.entries(payActual).sort());
  if(!equal(exCap,actualCap)) issues.push('Capacity-day counters differ from historical booking totals');
  if(!equal(exPay,actualPay)) issues.push('Payment balances differ from payment ledger');
  if(!config.exists) issues.push('Capacity settings absent despite ready state');
  if(state.get('timezone')!=='Asia/Karachi') issues.push('Unexpected trusted operations timezone');
 }
 const max=config.exists?config.get('maxGuestsPerDay'):null;
 if(config.exists && (!Number.isSafeInteger(max)||max<1)) issues.push('Invalid configured maximum capacity');
 if(Number.isSafeInteger(max)) for(const [day,n] of Object.entries(expectedCap.days)) if(n>max) issues.push(`Reservations exceed capacity for ${day}`);
 const result={project,businessId,readOnly:true,bookingCount:books.length,paymentCount:pays.length,capacityConfig:max,trustedState:migrated?'ready':state.exists?'not-ready':'absent',expectedCapacity:expectedCap.days,expectedBalances:expectedPay.balances,actualCapacity:capActual,actualBalances:payActual,issues};
 console.log(JSON.stringify(result,null,2));
 if(issues.length){process.exitCode=2;return;}
 if(migrated)console.log('PASS: trusted counters match the current historical source data.');
 else console.log('PASS: no inconsistencies detected in historical inputs; migration NOT yet confirmed complete.');
}
main().catch(e=>{console.error(e.message||e);process.exitCode=1;});
