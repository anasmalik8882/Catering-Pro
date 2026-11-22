'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {requireAdmin, validateList, validateStatus} = require('../admin').validation;
test('only the platformAdmin custom claim grants admin access', () => {
  assert.equal(requireAdmin({auth:{uid:'a', token:{platformAdmin:true}}}), 'a');
  assert.throws(() => requireAdmin({}), {code:'unauthenticated'});
  for (const token of [{}, {platformAdmin:'true'}, {platformAdmin:1}, {role:'owner'}, {admin:true}]) {
    assert.throws(() => requireAdmin({auth:{uid:'a', token}}), {code:'permission-denied'});
  }
});
test('list and status requests are validated', () => {
  assert.deepEqual(validateList({}), {limit:25, status:'', after:''});
  assert.equal(validateList({status:'suspended', limit:50}).limit, 50);
  for (const bad of [{limit:0}, {limit:51}, {limit:'5'}, {status:'deleted'}, {after:'../x'}]) assert.throws(() => validateList(bad));
  assert.equal(validateStatus({businessId:'b1', status:'suspended', reason:' Unpaid '}).reason, 'Unpaid');
  assert.equal(validateStatus({businessId:'b1', status:'active'}).reason, '');
  for (const bad of [{businessId:'b1', status:'suspended'}, {businessId:'b1', status:'deleted', reason:'xxx'},
    {businessId:'a/b', status:'active'}, {businessId:'b1', status:'suspended', reason:'x'.repeat(501)}]) assert.throws(() => validateStatus(bad));
});
