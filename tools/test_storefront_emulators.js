'use strict';
const {spawnSync} = require('node:child_process');
function run(args) {
  const result = spawnSync(process.execPath,args,{stdio:'inherit',env:process.env});
  if (result.status !== 0) process.exit(result.status || 1);
}
async function main() {
  if (process.env.GCLOUD_PROJECT !== 'demo-caterer-stage' || process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:8080') throw Error('Use the isolated demo emulator suite.');
  if (!process.argv.includes('--hosting-only')) run(['--test','functions/test/storefront.integration.test.js']);
  run(['tools/seed_storefront_emulator.js']);
  for (const path of ['/b/karachi-table', '/b/missing-caterer', '/b/invalid/extra']) {
    const response = await fetch(`http://127.0.0.1:5000${path}`);
    if (response.status !== 200 || !(await response.text()).includes('flutter_bootstrap.js')) throw Error(`Hosting refresh rewrite failed: ${path}`);
  }
  console.log('PASS: Hosting deep links and refresh fallbacks serve the customer application.');
  if (process.env.STOREFRONT_SCREENSHOTS === '1') await require('./storefront_browser_preview')();
}
main().catch(error => {console.error(error.message);process.exitCode=1;});
