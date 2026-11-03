'use strict';
const fs = require('node:fs');
const assert = require('node:assert/strict');
const json = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));
assert.equal(json('android/app/google-services.json').project_info.project_id, 'catering-pro-b001d');
assert.equal(json('android/app/src/production/google-services.json').project_info.project_id, 'catering-pro-b001d');
assert.equal(json('firebase_staging/google-services.json').project_info.project_id, 'caterer-pro-staging');
assert.equal(json('firebase.json').flutter.platforms.android.default.projectId, 'catering-pro-b001d');
const stagingPath = 'android/app/src/staging/google-services.json';
if (fs.existsSync(stagingPath)) {
  const data = json(stagingPath);
  assert.equal(data.project_info.project_id, 'caterer-pro-staging');
  assert.ok(data.client.some(c => c.client_info?.android_client_info?.package_name === 'com.example.catering_pro.staging'));
  console.log('Production and staging configs verified, including staging build app.');
} else {
  console.log('Production configuration verified. Staging Android app registration is still required.');
}
