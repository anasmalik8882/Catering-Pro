'use strict';
const fs = require('node:fs');
const crypto = require('node:crypto');
const path = require('node:path');
const base = path.resolve(__dirname, '..');
const original = fs.readFileSync(path.join(base, 'firebase/firestore.rules'), 'utf8');
const maintenance = fs.readFileSync(path.join(base, 'firebase/firestore.maintenance.rules'), 'utf8');
const hash = crypto.createHash('sha256').update(original).digest('hex');
const expectedHash = 'cf78d9b13ad88cc930630d52bdd970ab7be22329475a6169fbb4e241e7adbbc8';
if (hash !== expectedHash) throw Error(`Base rules changed: ${hash}. STOP: review and regenerate maintenance rules before deployment.`);
const allowed = /^[ \t]*allow\s+([^:;]+):\s*if\s+([\s\S]*?);/gm;
const parse = (source) => [...source.matchAll(allowed)].map(m => ({methods: m[1].split(',').map(s => s.trim()), condition: m[2].trim()}));
const before = parse(original), after = parse(maintenance);
if (before.length !== after.length || before.length < 30) throw Error('Rule statement count changed unexpectedly.');
let denied = 0;
for (let i = 0; i < before.length; i++) {
  if (before[i].methods.join(',') !== after[i].methods.join(',')) throw Error(`Rule methods changed at #${i+1}`);
  const writable = before[i].methods.some(s => ['write','create','update','delete'].includes(s));
  if (writable) {if (after[i].condition !== 'false') throw Error(`Write not denied at rule #${i+1}`);denied++;}
  else if (before[i].condition !== after[i].condition) throw Error(`Read condition changed at rule #${i+1}`);
}
if (denied < 20) throw Error('Unexpectedly few write rules denied.');
console.log(`PASS: source rules SHA256 verified; ${denied} write grants disabled; ${before.length-denied} read-only grants unchanged.`);
console.log('NOTE: Static check ONLY. Before production deployment, compile rules in Firestore emulator and test denied writes.');
