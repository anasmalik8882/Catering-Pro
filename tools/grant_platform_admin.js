'use strict';
// Grant or revoke the Caterer Pro platform-admin custom claim (Milestone 12).
//
// Usage (Windows PowerShell, after `gcloud auth application-default login`):
//   node tools/grant_platform_admin.js --project caterer-pro-staging --email you@example.com
//   node tools/grant_platform_admin.js --project caterer-pro-staging --email you@example.com --revoke
// Production additionally requires --confirm-production.
// The user must sign out and back in (or wait up to 1 hour) for the claim to apply.
const path = require('node:path');
const {initializeApp, applicationDefault} = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin', 'lib', 'app'));
const {getAuth} = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin', 'lib', 'auth'));

const args = process.argv.slice(2);
const flag = name => args.includes(name);
const option = name => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : undefined; };
const projectId = option('--project');
const email = option('--email');
const allowed = ['caterer-pro-staging', 'catering-pro-b001d', 'demo-caterer-stage'];
if (!allowed.includes(projectId) || !email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
  console.error(`Usage: --project <${allowed.join('|')}> --email <address> [--revoke] [--confirm-production]`);
  process.exit(2);
}
if (projectId === 'catering-pro-b001d' && !flag('--confirm-production')) {
  console.error('Refusing to change PRODUCTION without --confirm-production.');
  process.exit(2);
}
if (projectId.startsWith('demo-') && !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  console.error('demo- projects require FIREBASE_AUTH_EMULATOR_HOST.');
  process.exit(2);
}
(async () => {
  initializeApp(projectId.startsWith('demo-') ? {projectId} : {projectId, credential: applicationDefault()});
  const auth = getAuth();
  const user = await auth.getUserByEmail(email);
  const claims = {...(user.customClaims || {})};
  if (flag('--revoke')) delete claims.platformAdmin; else claims.platformAdmin = true;
  await auth.setCustomUserClaims(user.uid, claims);
  console.log(`${flag('--revoke') ? 'Revoked' : 'Granted'} platformAdmin for ${email} (uid ${user.uid}) on ${projectId}.`);
  console.log('Sign out and sign in again for the change to take effect.');
})().catch(error => { console.error(error.message); process.exit(1); });
