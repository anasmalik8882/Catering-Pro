 'use strict';
const ACTIVE = new Set(['confirmed','preparation','ready','in_progress','completed','closed']);
function dateKey(value, timezone='Asia/Karachi') {
  if (!(value instanceof Date) || Number.isNaN(value.getTime())) throw Error('Invalid event date');
  const parts = new Intl.DateTimeFormat('en-US', {timeZone:timezone,year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(value);
  const get = key => parts.find(p=>p.type===key).value;
  return `${get('year')}-${get('month')}-${get('day')}`;
}
function capacitySummary(bookings, timezone='Asia/Karachi') {
  const days={}; const issues=[]; const seen=new Set();
  for(const b of bookings) {
    if(!b.id || seen.has(b.id)){issues.push(`duplicate/invalid booking id ${b.id}`);continue;}seen.add(b.id);
    if(!ACTIVE.has(b.status)) continue;
    if(!Number.isSafeInteger(b.guests) || b.guests<=0 || !(b.eventDate instanceof Date)) {issues.push(`invalid active booking ${b.id}`);continue;}
    const day=dateKey(b.eventDate,timezone);days[day]=(days[day]||0)+b.guests;
    if(!Number.isSafeInteger(days[day])) issues.push(`capacity overflow on ${day}`);
  }
  return {days,issues};
}
function paymentSummary(bookings,payments) {
  const balances={};const issues=[];const known=new Map();
  for(const b of bookings){if(!b.id||known.has(b.id)){issues.push(`duplicate booking ${b.id}`);continue;}known.set(b.id,b);balances[b.id]=0;}
  for(const p of payments){
    if(!p.id || !known.has(p.bookingId)){issues.push(`unknown payment booking ${p.id}`);continue;}
    if(!['payment','refund'].includes(p.kind) || !Number.isSafeInteger(p.amountPaisa) || p.amountPaisa<=0){issues.push(`invalid payment ${p.id}`);continue;}
    balances[p.bookingId]+= p.kind==='payment'?p.amountPaisa:-p.amountPaisa;
    if(!Number.isSafeInteger(balances[p.bookingId])) issues.push(`payment overflow ${p.bookingId}`);
  }
  for(const [id,b] of known){if(!Number.isSafeInteger(b.totalPaisa)||b.totalPaisa<0||balances[id]<0||balances[id]>b.totalPaisa) issues.push(`invalid balance for ${id}`);}
  return {balances,issues};
}
module.exports={dateKey,capacitySummary,paymentSummary,ACTIVE};
