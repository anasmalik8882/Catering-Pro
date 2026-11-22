'use strict';
// Synthetic development fixture. Refuses every non-demo project or remote host.
const {createRequire} = require('node:module');
const path = require('node:path');
const functionsRequire = createRequire(path.resolve(__dirname, '../functions/package.json'));
const {initializeApp} = functionsRequire('firebase-admin/app');
const {getFirestore} = functionsRequire('firebase-admin/firestore');
const {getAuth} = functionsRequire('firebase-admin/auth');
async function main() {
  if (process.env.GCLOUD_PROJECT !== 'demo-caterer-stage' || process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:8080' || process.env.FIREBASE_AUTH_EMULATOR_HOST !== '127.0.0.1:9099') throw Error('Only the local demo-caterer-stage Auth and Firestore emulators are supported.');
  initializeApp({projectId:'demo-caterer-stage'});
  const auth = getAuth();
  const email = 'storefront-demo@example.invalid';
  let owner;
  try { owner = await auth.getUserByEmail(email); }
  catch (error) { if (error.code !== 'auth/user-not-found') throw error; owner = await auth.createUser({email,password:'emulator-demo-only-123'}); }
  const base = getFirestore().collection('businesses').doc('website-demo');
  await base.set({name:'Karachi Table',city:'Karachi',phone:'03000000000',ownerId:owner.uid,status:'active'});
  await base.collection('members').doc(owner.uid).set({uid:owner.uid,active:true,role:'owner'});
  await base.collection('menuItems').doc('biryani').set({name:'Celebration biryani',description:'Private catalog notes',unit:'plate',pricePaisa:65000,active:true});
  await base.collection('packages').doc('wedding').set({name:'The celebration table',description:'Private package notes',pricingMode:'per_head',minimumGuests:50,pricePaisa:185000,active:true});
  const signIn = await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-key',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email,password:'emulator-demo-only-123',returnSecureToken:true})});
  const {idToken} = await signIn.json();
  if (!idToken) throw Error('Demo sign-in failed.');
  const config = {slug:'karachi-table',displayName:'Karachi Table',description:'Thoughtfully prepared food, generous hospitality and a table your guests will remember. Let us take care of the menu while you enjoy the occasion.',services:'Wedding celebrations · Family gatherings · Corporate hospitality',phone:'',email:'',location:'Karachi',logoUrl:'',heroUrl:'',published:true,menus:[{id:'biryani',description:'Fragrant basmati rice, warming spices and a generous serving of tradition.',imageUrl:'',showPrice:true}],packages:[{id:'wedding',description:'A generous menu for your celebration. Tell us about your occasion and we will tailor the details.',imageUrl:'',showPrice:false}]};
  const response = await fetch('http://127.0.0.1:5001/demo-caterer-stage/asia-south1/saveStorefront',{method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${idToken}`},body:JSON.stringify({data:{businessId:base.id,config}})});
  const result = await response.json();
  if (result.error) throw Error(result.error.message);
  console.log('Local synthetic storefront published: /b/karachi-table');
}
main().catch(error => {console.error(error.message);process.exitCode=1;});
