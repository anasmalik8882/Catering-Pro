# Milestone 12 — SaaS super-admin portal

Status: **implemented and tested on emulators. Not deployed.** Builds on Milestone 11
(this branch includes it). Production is untouched.

## What it does

A separate Flutter Web app (`lib/main_admin_web.dart`) for you, the platform owner:

- Sign in with email/password or Google. Only accounts that have the `platformAdmin`
  custom claim get in. Everyone else sees "not a platform administrator".
- **Businesses tab:** every tenant, filterable by All / Active / Suspended, searchable by
  name, city, phone, owner email or id, with paging.
- **Business page:** owner, created date, usage counts (customers, sales inquiries,
  website inquiries, quotations, bookings), storefront slug and published state, team
  members and roles, subscription status (set up in Milestone 13), and this business's
  admin history.
- **Suspend or reactivate**, with a required reason when suspending. Every change is
  written to `platformAuditLogs`.
- **Audit log tab:** the latest 100 admin actions across all tenants.

The portal never returns payment or ledger records, only counts.

### What suspension does

- The business app shows an **Account suspended** screen with the reason, plus
  **Check again** and **Sign out**.
- Firestore rules: members keep **read** access but every client **write** is denied
  (customers, inquiries, menu, packages, quotations, bookings, expenses, tasks), and the
  business profile can't be edited.
- Trusted functions (`transitionBooking`, `recordBookingPayment`, capacity, and
  `reviewPublicInquiry`) refuse to run with "business account is suspended".
- The storefront is already hidden for non-active businesses (Milestone 10).
- **Reactivate** restores everything. No data is deleted.

## New server functions (asia-south1)

`adminListBusinesses`, `adminGetBusiness`, `adminSetBusinessStatus`, `adminListAuditLog`.
All of them require `request.auth.token.platformAdmin === true`.

## Files

Added: `functions/admin.js`, `functions/test/admin.test.js`, `lib/main_admin_web.dart`,
`lib/features/admin/admin_api.dart`, `lib/features/admin/admin_portal.dart`,
`test/admin_portal_test.dart`, `tools/grant_platform_admin.js`, `firebase.admin.json`,
`docs/milestone12.md`.
Modified: `functions/index.js` (registers the admin callables, and `authorize()` now
blocks suspended tenants), `functions/inquiries.js`, `firebase/firestore.rules`,
`lib/core/app/app.dart`, `lib/core/app/session_controller.dart`,
`lib/features/business/data/business_repository.dart`, and tests.

## Test results (22 Nov 2026, emulator project `demo-caterer-stage`)

- `flutter test`: **28 passed**. `flutter analyze`: no errors or warnings.
- `flutter build web --target lib/main_admin_web.dart --output build/admin_web`: built.
- Node unit tests: **12 passed**.
- Callable integration tests: **4 passed**. The new one checks that tenant owners and
  anonymous users are denied, owner emails are listed, no private fields leak, a reason is
  required, suspension blocks trusted operations, reactivation restores them, and the
  audit trail is in order.
- Firestore rules tests: **10 passed**. The new one checks that a suspended tenant can read
  but not write, and that the audit log is closed to every client, including admins.

## Deploy to STAGING (Windows PowerShell)

### 1. Make yourself a platform admin (one time)
You need the Google Cloud CLI signed in with the account that owns the Firebase project:
```powershell
gcloud auth application-default login
cd C:\flutter_projects\catering_pro
node tools/grant_platform_admin.js --project caterer-pro-staging --email YOUR_LOGIN_EMAIL
```
The email must already have signed in to staging at least once. To remove the access
later, add `--revoke`.

### 2. Deploy functions and rules
This deploys the Milestone 11 and 12 functions by name, and the rules. The existing
trusted functions are included because `authorize()` now checks for suspension.
```powershell
firebase.cmd deploy --project caterer-pro-staging --config firebase.customer.json --only "functions:reviewPublicInquiry,functions:adminListBusinesses,functions:adminGetBusiness,functions:adminSetBusinessStatus,functions:adminListAuditLog,functions:transitionBooking,functions:recordBookingPayment,functions:initializeDailyCapacity,functions:updateDailyCapacity,firestore:rules"
```

### 3. Create the admin website (one time)
```powershell
firebase.cmd hosting:sites:create caterer-pro-staging-admin --project caterer-pro-staging
firebase.cmd target:apply hosting admin caterer-pro-staging-admin --project caterer-pro-staging
```
In Firebase Console → Authentication → Settings → **Authorized domains**, add
`caterer-pro-staging-admin.web.app` so Google sign-in works there.

### 4. Build and deploy the portal
Use the same staging Web variables as Milestone 10:
```powershell
flutter build web --target lib/main_admin_web.dart --output build/admin_web --dart-define=APP_ENV=staging --dart-define=STAGING_WEB_API_KEY=$env:STAGING_WEB_API_KEY --dart-define=STAGING_WEB_APP_ID=$env:STAGING_WEB_APP_ID --dart-define=STAGING_WEB_SENDER_ID=$env:STAGING_WEB_SENDER_ID
firebase.cmd deploy --project caterer-pro-staging --config firebase.admin.json --only hosting:admin
```
Open `https://caterer-pro-staging-admin.web.app`.

The customer storefront deploy (`firebase.customer.json`, `build/web`) is unchanged.
Always pass `--output build/admin_web` for the portal so it never overwrites the
storefront build.

## Staging acceptance checklist

1. Sign in to the portal as a non-admin account. You see "not a platform administrator".
2. Sign in as the admin. Your staging business is listed with the owner's email.
3. Open it. The usage counts match the app, and the team and storefront are shown.
4. Suspend it with a reason. The staging app shows **Account suspended** after **Check
   again** or a restart. The storefront `/b/<slug>` stops loading, and creating a customer
   fails.
5. Reactivate it. The app and storefront work again.
6. The Audit log tab shows both actions with your email.

## Deferred

- Plan management, billing and Safepay are Milestone 13.
- Requiring 2-step verification for admin accounts, and App Check on the admin callables.
  Recommended before launch.
- Impersonation and data export for support. Not built on purpose; add later only with
  audit logging.
