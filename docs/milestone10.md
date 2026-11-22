# Milestone 10: customer storefront

Implementation is local; no production or staging deployment was performed. Rollback base: `524bf56a46a05b78d40c1a2859a51c017f940bfd`. No historical migrations, reconciliation scripts or live records were changed.

## Architecture and data contract

- `lib/main_customer_web.dart` boots a separate Flutter application with path URLs. It imports neither the business app nor its authentication/session gate. `/b/<slug>` and refreshes are supported by the Hosting rewrite. Missing, unpublished and disabled businesses return a generic unavailable page; malformed paths do not reach Firestore.
- The customer app uses callable Cloud Functions in `asia-south1`. It does not require a signed-in session or make Firestore client reads. Shared Firebase Web SDK modules may be loaded by plugin registration; visitors never create an account. The existing business entry point keeps its environment checks and authentication flow.
- `saveStorefront` atomically checks current active owner membership, matching business owner identity, business status, slug reservation and selected catalog records. A concurrent tenant cannot take the same slug. Slugs remain reserved while unpublished; renaming releases the previous slug. The old URL stops working immediately.
- `businesses/{bid}/settings/storefront` stores owner configuration, public selections and audit fields. New publishing is owner-only. Existing authenticated-member settings read access is preserved; writes are exclusively server-side. Owner settings retrieval uses `getStorefrontSettings`.
- `publicStorefronts/{slug}` is an internal server-owned snapshot containing `businessId`, `publicData` and `updatedAt`. Despite its name, direct client reads/writes are denied. `getPublicStorefront` checks both snapshot visibility and the current tenant status in a transaction, then returns ONLY `publicData`. It does not return tenant IDs, member data, private descriptions, costs, customer records, or historical business data.
- Each published item contains only its ID, name, owner-written public description, optional image URL, unit or package guest/pricing mode, and an optional `pricePaisa`. Private catalog descriptions and package composition are not copied. Prices remain integer paisa. Republish after catalog changes; snapshots intentionally do not publish subsequent private edits automatically. Deactivate an item and republish/unselect it to remove it from the website.
- `submitStorefrontInquiry` is anonymous. It resolves tenant identity from the current slug snapshot, validates contacts/date/guests/package selection, assigns `new` status and a server timestamp, and writes `businesses/{bid}/publicInquiries/{id}`. Client-provided business IDs, status and timestamps are ignored. Event dates are calendar strings (`YYYY-MM-DD`), using UTC today for the lower date boundary, not booking timestamps. No customer, quotation, booking, payment or capacity record is created.
- Public inquiries are a separate intake contract for Milestone 11. Owners can read them under Firestore rules; all client writes are denied. There is deliberately no inquiry-to-sales conversion or pipeline UI in this milestone.
- UUID request IDs and a normalized payload hash provide transaction-safe retry deduplication within a slug. The form retains its ID across network retries; editing after a failed attempt rotates it. Browser reload is a new request. A duplicate ID with different content fails.

## Abuse controls and images

Successful new submissions consume transactional hourly quotas: 20 per server-observed IP across tenants, 3 per normalized contact number per tenant, and 200 per tenant. Concurrent requests cannot bypass the counters. `storefrontRateLimits/{sha256}` stores counts and `expiresAt`, never raw IPs. The current deployment does not require App Check or user sign-in. Limits bound accepted intake, not all invocation costs; distributed invalid-request flooding still needs infrastructure monitoring and, if needed later, App Check/WAF. `maxInstances: 20` and a 30-second callable timeout bound scaling per new endpoint.

No composite indexes are required. For automatic cleanup, enable Firestore TTL on collection group `storefrontRateLimits`, field `expiresAt` after deployment (optional for correct enforcement; expired counters are never reused). Avoid short retention or automatic TTL on inquiries until the business retention policy is agreed.

Only explicitly entered HTTPS images from `firebasestorage.googleapis.com`, `storage.googleapis.com`, or `images.unsplash.com` are accepted. Credentials in URLs, nonstandard ports, other hosts and non-HTTPS schemes are rejected. No uploads or Storage rule changes are needed. A referenced image must already be publicly loadable with appropriate CORS; an inaccessible image falls back to the branded illustration treatment. Publishing a token-bearing Storage URL makes that URL public. Use dedicated public marketing assets you own; do not paste links to private customer/event images. An unpublish cannot revoke a previously shared third-party URL or screenshots.

## Owner and visitor workflows

1. In the business app, sign in as the active business owner and open **Home → Customer storefront**. Staff do not see this action; backend checks remain authoritative.
2. Enter a unique slug, display name, public description/services, optional contact details, and optional logo/hero URLs. Contact fields are blank by default, so existing private contact details are not published accidentally.
3. Select up to 40 active menu items and 40 active packages. Write public descriptions, add optional photos and choose each item's price visibility (hidden by default).
4. **Preview changes** renders the current draft with submission disabled. **Publish website** / **Update published website** saves a public snapshot. **Save unpublished** / **Save and unpublish** hides the storefront while retaining its slug.
5. Copy the saved storefront URL. The default origin is the current Firebase project's `https://<projectId>.web.app`; compile the business app with `--dart-define=CUSTOMER_SITE_ORIGIN=https://<your-host>` if using a different Hosting site or development host. No purchased domain is required.
6. Visitors open that URL, browse the published catalog, select a package if desired, and submit their name, phone, optional email, event type/date, guests and requirements. They see success only after the server returns a stored inquiry reference. A quotation request is not a confirmed booking.

## Local development

Prerequisites: the repository's Flutter SDK/dependencies, Node dependencies in `functions` and `tests/security`, Firebase CLI, and Java 21 for the emulator. Production Functions runtime is Node 22; the available host used Node 24 for local emulation. On Windows use `firebase.cmd` when PowerShell execution policy blocks `firebase.ps1`.

Start local emulators, with no live Firebase project:

```powershell
firebase.cmd emulators:start --project demo-caterer-stage --config firebase.customer.json --only auth,firestore,functions
```

In a second terminal, seed synthetic data through the actual publishing callable:

```powershell
$env:GCLOUD_PROJECT='demo-caterer-stage'
$env:FIRESTORE_EMULATOR_HOST='127.0.0.1:8080'
$env:FIREBASE_AUTH_EMULATOR_HOST='127.0.0.1:9099'
node tools/seed_storefront_emulator.js
flutter run -d chrome --target lib/main_customer_web.dart --dart-define=APP_ENV=emulator --web-port=4200
```

Open `http://localhost:4200/b/karachi-table`. The seed script refuses non-demo projects and non-loopback Auth/Firestore hosts. It contains only synthetic development data, never used by the production application. Image URLs can be set with the owner callable if image treatment needs review. For an emulator accessed from another device, set `EMULATOR_HOST` to the development host and explicitly configure suitable emulator network binding; defaults remain loopback-only.

For a compiled build with Hosting deep-link/refresh behavior:

```powershell
flutter build web --target lib/main_customer_web.dart --dart-define=APP_ENV=emulator
firebase.cmd emulators:start --project demo-caterer-stage --config firebase.customer.json --only auth,firestore,functions,hosting
```

Seed in the other terminal again, then open `http://127.0.0.1:5000/b/karachi-table`. The business management app currently supports its original production/staging Android environments; use staging for owner-screen device acceptance. Do not point the business app at production for testing.

## Staging and later manual deployment

Staging currently has Android configuration only. Obtain/register a Web app in the EXISTING `caterer-pro-staging` project and supply its public Firebase client configuration (these values are not server secrets):

```powershell
flutter run -d chrome --target lib/main_customer_web.dart --dart-define=APP_ENV=staging --dart-define=STAGING_WEB_API_KEY=<web-api-key> --dart-define=STAGING_WEB_APP_ID=<web-app-id> --dart-define=STAGING_WEB_SENDER_ID=<sender-id>
```

Missing staging config logs a setup error and displays a safe unavailable message, never a fallback to production. For the owner app use its existing staging flavor:

```powershell
flutter run --flavor staging --dart-define=APP_ENV=staging --dart-define=CUSTOMER_SITE_ORIGIN=https://caterer-pro-staging.web.app
```

Manual staging deployment commands, not executed by this task:

```powershell
firebase.cmd deploy --project caterer-pro-staging --config firebase.customer.json --only functions:getStorefrontSettings,functions:saveStorefront,functions:getPublicStorefront,functions:submitStorefrontInquiry,firestore:rules
flutter build web --target lib/main_customer_web.dart --dart-define=APP_ENV=staging --dart-define=STAGING_WEB_API_KEY=<web-api-key> --dart-define=STAGING_WEB_APP_ID=<web-app-id> --dart-define=STAGING_WEB_SENDER_ID=<sender-id>
firebase.cmd deploy --project caterer-pro-staging --config firebase.customer.json --only hosting
```

After separate release approval and staging/device acceptance, the analogous production commands are:

```powershell
firebase.cmd deploy --project catering-pro-b001d --config firebase.customer.json --only functions:getStorefrontSettings,functions:saveStorefront,functions:getPublicStorefront,functions:submitStorefrontInquiry,firestore:rules
flutter build web --target lib/main_customer_web.dart --dart-define=APP_ENV=production
firebase.cmd deploy --project catering-pro-b001d --config firebase.customer.json --only hosting
```

Review current deployed rules against repository rules before any live rules release. Deploy only the four named new functions, preserving all existing trusted operation endpoints. Confirm the intended Firebase Hosting site before deploying; use a separate Hosting target if the default site already serves another application. Never deploy an emulator-configured build to staging/production. Do not run any historical migration or reconciliation as part of this release.

## Verification commands

```powershell
flutter analyze
flutter test
flutter build web --target lib/main_customer_web.dart --dart-define=APP_ENV=emulator
node --test functions/test/migration_core.test.js functions/test/storefront.test.js
firebase.cmd emulators:exec --project demo-caterer-stage --config firebase.customer.json --only auth,firestore,functions "node --test functions/test/storefront.integration.test.js"
firebase.cmd emulators:exec --project demo-caterer-stage --config firebase.customer.json --only firestore "node --test tests/security/firestore.rules.test.cjs"
```

The existing `trusted_operations.integration.test.js` calls historical migration/reconciliation code on synthetic emulator fixtures, so it was intentionally not run under this task's explicit no-migration instruction. Existing migration math unit tests and trusted-state Firestore rule tests can run safely. Do not use bare `npm test` in `functions`: its current broad test discovery also includes that historical migration integration suite, which requires a dedicated emulator environment.

Actual run results and remaining acceptance limitations are recorded below.

## File inventory

Added:
- `lib/main_customer_web.dart`
- `lib/features/storefront/storefront_api.dart`
- `lib/features/storefront/customer_site.dart`
- `lib/features/storefront/storefront_management.dart`
- `functions/storefront.js`
- `functions/test/storefront.test.js`
- `functions/test/storefront.integration.test.js`
- `test/storefront_test.dart`
- `firebase.customer.json`
- `tools/seed_storefront_emulator.js`
- `tools/test_storefront_emulators.js`
- `tools/storefront_browser_preview.js`
- `web/customer_icon.svg`
- `docs/milestone10.md`

Modified:
- `lib/features/dashboard/presentation/dashboard_screen.dart` (owner publishing entry)
- `functions/index.js` (register four functions; existing implementations preserved)
- `firebase/firestore.rules` (owner-only read access to new public inquiry intake; client writes denied)
- `tests/security/firestore.rules.test.cjs` (anonymous and cross-tenant tests)
- `firebase.json` (Hosting SPA rewrite)
- `pubspec.yaml` and `pubspec.lock` (Flutter SDK `flutter_web_plugins` dependency for path URL strategy)
- `web/index.html` (customer metadata, accessible startup/loading state, safe slow-start guidance)
- `web/manifest.json` (customer browser branding)
- `android/.gitignore` (ignore generated Kotlin compiler sessions)

## Verification results (9 November 2026)

| Check | Actual result |
| --- | --- |
| `flutter analyze` | Passed: **No issues found** |
| `flutter test` | **17 passed**, including existing business role, quote/event finance and payment recovery tests; plus storefront URLs, unavailable response handling, 390×844 and 1440×1000 layouts, and validated inquiry submission |
| Storefront and migration-math Node unit tests | **7 passed**; expanded malformed-selection/contact validation also passed its subsequent 3-test unit run |
| Firestore security suite | **8 passed** against the local Firestore emulator, including existing tenant/trusted-state protections and new anonymous access denials |
| Storefront backend integration and trusted-operation smoke tests | **2 passed** against local Auth, Firestore and Functions emulators. All four existing trusted callables exercised using new synthetic fixtures, without migrations |
| Customer Flutter Web build | Passed, including Wasm dry run; final source rebuild recorded below |
| Existing staging Android debug build | Passed: `build/app/outputs/flutter-apk/app-staging-debug.apk`, 598.7 seconds; no device installation or live calls |
| Hosting rewrite and demo fixture | Passed: real publishing callable plus HTTP refresh checks for valid, missing and malformed storefront paths |

The historical migration integration suite was intentionally excluded under the no-migration instruction, as explained above. No claim is made that it ran. The new smoke test replaces the need to invoke migrations when checking the preserved trusted callables.

Browser verification waits for the real `getPublicStorefront` HTTP 200 response before capturing a frame. Fixed virtual-time captures were too early on this host while Flutter/Firebase assets initialized; they were rejected as visual evidence. The production HTML now displays an accessible loading message from the first response, followed by the Flutter loading/error/success states. The final browser results below include visual inspection.

Run the complete local suite, including Hosting refresh checks, after building Web:

```powershell
$env:FUNCTIONS_DISCOVERY_TIMEOUT='120'
firebase.cmd emulators:exec --project demo-caterer-stage --config firebase.customer.json --only auth,firestore,functions,hosting "node tools/test_storefront_emulators.js"
```

The timeout accommodates slow local function discovery and does not change deployed runtime limits. Set `$env:STOREFRONT_SCREENSHOTS='1'` for optional installed Windows Edge checks using Node's built-in WebSocket support; screenshots are written under ignored `build/`. Omit it on hosts without Edge. `--hosting-only` skips the independent backend suite when validating only the seed, Hosting and browser rendering.

## Remaining release acceptance

No live deployment was performed. Staging Web Firebase configuration must be supplied before staging browser acceptance. iOS compilation requires macOS/Xcode, which is unavailable on this Windows host. Physical Android/iOS owner publishing, image/CORS behavior with the business's actual marketing assets, and staging end-to-end device acceptance remain to be checked. The Android build and shared widget/backend regressions passed; they do not certify those physical-device workflows.

The implementation is delivered for review, but Milestone 10 is **not marked fully complete** until those outstanding release acceptance checks are performed. Milestone 11 inquiry-to-sales conversion remains intentionally deferred.

Final browser and build verification:

- Final Web build including the accessible HTML startup shell passed, with the Wasm dry run also successful (202.5 seconds).
- The corrected Hosting/browser runner exited **0**. The synthetic storefront was published through `saveStorefront`, all three Hosting refresh URLs returned the application, and the actual browser `getPublicStorefront` request returned **HTTP 200** without JavaScript exceptions.
- Desktop **1440×1000** and mobile **390×844** screenshots were captured after real data loaded and visually inspected. Branding, hero text, quotation CTAs and responsive stacking rendered correctly. The synthetic fixture deliberately has no photo; production uses only owner-published image URLs.
- Local screenshots: `build/storefront-desktop.png` and `build/storefront-mobile.png` (ignored artifacts, not committed).
- `git diff --check` passed. Source changes comprise **14 added files and 10 modified files**, enumerated above. No credentials, keystores, migrations or build artifacts were committed.
