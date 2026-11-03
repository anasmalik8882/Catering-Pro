'use strict';
const fs = require('node:fs');
const [a,b] = process.argv.slice(2);
if(!a||!b)throw Error('Usage: node compare-verifications.js production.json staging.json');
const prod=JSON.parse(fs.readFileSync(a,'utf8'));
const stage=JSON.parse(fs.readFileSync(b,'utf8'));
if(prod.project===stage.project)throw Error('Refusing to compare same project ID');
if(prod.businessId!==stage.businessId)throw Error('Different business IDs');
let bad=false;
for(const k of ['bookings','payments','capacityDays','paymentBalances']){
 const countMatch=prod.counts[k]===stage.counts[k];
 const hashMatch=prod.fingerprints[k]===stage.fingerprints[k];
 console.log(`${k}: count=${prod.counts[k]}/${stage.counts[k]} ${countMatch?'OK':'MISMATCH'} sha256=${hashMatch?'MATCH':'MISMATCH'}`);
 if(!countMatch||!hashMatch)bad=true;
}
if(bad){console.error('RESTORE VERIFICATION FAILED. DO NOT PROCEED WITH MIGRATION.');process.exitCode=1;}
else console.log('Selected business collections match exactly. This is not a full database validation.');
