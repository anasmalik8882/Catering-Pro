 'use strict';
const {test}=require('node:test');const assert=require('node:assert/strict');
const {dateKey,capacitySummary,paymentSummary}=require('../migration_core');
test('Asia/Karachi local date differs from UTC across midnight',()=>{assert.equal(dateKey(new Date('2026-10-22T20:30:00Z')),'2026-10-23');});
test('capacity counts active bookings only',()=>{const d=new Date('2026-10-22T20:30:00Z');assert.deepEqual(capacitySummary([{id:'a',status:'confirmed',guests:100,eventDate:d},{id:'b',status:'tentative',guests:400,eventDate:d},{id:'c',status:'preparation',guests:75,eventDate:d}]).days,{'2026-10-23':175});});
test('net balance reconciles payments and refunds',()=>{const r=paymentSummary([{id:'b',totalPaisa:10000}],[{id:'p1',bookingId:'b',kind:'payment',amountPaisa:6000},{id:'p2',bookingId:'b',kind:'refund',amountPaisa:1500}]);assert.equal(r.balances.b,4500);assert.deepEqual(r.issues,[]);});
test('rejects excess refund and unknown references',()=>{const r=paymentSummary([{id:'b',totalPaisa:10000}],[{id:'p',bookingId:'b',kind:'refund',amountPaisa:1},{id:'x',bookingId:'missing',kind:'payment',amountPaisa:5}]);assert.equal(r.issues.length,2);});
