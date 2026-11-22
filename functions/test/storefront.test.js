'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {slug, config, inquiry, image} = require('../storefront').validation;
const draft = () => ({slug:'karachi-catering', displayName:'Karachi Catering', description:'', phone:'', email:'', location:'', services:'', logoUrl:'', heroUrl:'', published:true, menus:[], packages:[]});
const request = () => ({name:'Test Visitor', phone:'+92 300 1234567', email:'test@example.invalid', eventType:'Wedding', eventDate:'2027-03-01', guests:100, packageId:'', requirements:''});
test('slugs reject traversal, malformed URLs, uppercase and excessive length', () => {
  assert.equal(slug('karachi-catering'), 'karachi-catering');
  for (const value of ['../private','ab','a--b','Bad-name','a/b','a%2fb','-abc','abc-', 'a'.repeat(61), undefined]) assert.throws(() => slug(value));
});
test('publishing strips unknown fields and validates selections and images', () => {
  const value = config({...draft(), ownerId:'private', customers:['secret']});
  assert.equal(value.ownerId, undefined);
  assert.equal(value.customers, undefined);
  assert.throws(() => config({...draft(), menus:[{id:'../other', description:'', imageUrl:'', showPrice:false}]}));
  assert.throws(() => config({...draft(), menus:[null]}), {code:'invalid-argument'});
  const item = {id:'menu-one', description:'Public copy', imageUrl:'', showPrice:false};
  assert.throws(() => config({...draft(), menus:[item,item]}));
  assert.throws(() => config({...draft(), menus:Array(41).fill(item)}));
  assert.equal(image('https://images.unsplash.com/photo-test'), 'https://images.unsplash.com/photo-test');
  for (const value of ['javascript:alert(1)', 'http://images.unsplash.com/photo', 'https://evil.invalid/a', 'https://user:pass@images.unsplash.com/a']) assert.throws(() => image(value));
});
test('anonymous inquiry rejects invalid contacts, dates, counts and excessive text', () => {
  const now = new Date('2026-11-09T12:00:00Z');
  assert.equal(inquiry(request(), now).guests,100);
  for (const change of [{name:''},{phone:'abc'},{phone:'.......'},{phone:'1'.repeat(16)},{email:'invalid'},{guests:0},{guests:1.5},{guests:100001},{eventDate:'2027-02-30'},{eventDate:'2025-01-01'},{eventDate:'2031-01-01'},{requirements:'a'.repeat(2001)},{packageId:'../private'}]) assert.throws(() => inquiry({...request(),...change}, now));
  assert.equal(inquiry({...request(),businessId:'attacker',status:'confirmed'},now).businessId, undefined);
});
