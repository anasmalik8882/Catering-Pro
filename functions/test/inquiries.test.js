'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {validate, karachiEventDate, salesNotes} = require('../inquiries').validation;
const base = {businessId:'owner_abc', inquiryId:'abc123'};
test('review requests accept only known actions and safe identifiers', () => {
  assert.deepEqual(validate({...base, action:'contacted'}), {...base, action:'contacted'});
  assert.equal(validate({...base, action:'dismiss'}).reason, 'other');
  assert.equal(validate({...base, action:'dismiss', reason:'spam'}).reason, 'spam');
  assert.equal(validate({...base, action:'convert', customerId:'cust-1'}).customerId, 'cust-1');
  assert.equal(validate({...base, action:'convert', customerId:''}).customerId, undefined);
  for (const bad of [null, {...base, action:'delete'}, {...base, action:'toString'}, {...base, businessId:'../x', action:'contacted'},
    {...base, inquiryId:'a/b', action:'contacted'}, {...base, action:'dismiss', reason:'rude'}, {...base, action:'convert', customerId:'x/y'}]) {
    assert.throws(() => validate(bad), {code:'invalid-argument'});
  }
});
test('website event days map to the same Asia/Karachi calendar day', () => {
  const ts = karachiEventDate('2027-03-01');
  const day = new Intl.DateTimeFormat('en-CA', {timeZone:'Asia/Karachi', year:'numeric', month:'2-digit', day:'2-digit'}).format(ts.toDate());
  assert.equal(day, '2027-03-01');
  for (const bad of ['2027-3-1', '', undefined, '2027-13-45']) assert.throws(() => karachiEventDate(bad));
});
test('sales notes carry package, email and requirements within limits', () => {
  const doc = {get: k => ({email:'a@example.invalid', requirements:'x'.repeat(5000)})[k]};
  const notes = salesNotes(doc, 'Wedding feast');
  assert.ok(notes.includes('Wedding feast') && notes.includes('a@example.invalid'));
  assert.ok(notes.length <= 2000);
});
