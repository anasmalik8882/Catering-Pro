# Milestone 11 — Website inquiries → sales pipeline

Status: **implemented and tested locally on emulators. Not deployed anywhere.**
Production is untouched. Deploy to **staging** only after Milestone 10 staging
acceptance passes (see `docs/milestone10.md` and the handoff §9).

## What it does

1. A customer submits the public storefront form (Milestone 10). The request is stored in
   `businesses/{bid}/publicInquiries/{id}` with status `new`.
2. Owner, manager and sales staff see a **Website inquiries** card on Home, with a live
   badge for new requests. The same inbox is under **More → Website inquiries**.
3. The inbox has four tabs: New, Contacted, Converted, Dismissed. Opening an inquiry shows
   the visitor's contact details, event, guests, package and requirements.
4. Actions, all done on the server by the new callable `reviewPublicInquiry`:
   | From | Action | To |
   |---|---|---|
   | new | Mark as contacted | contacted |
   | new / contacted | **Convert** | converted |
   | new / contacted | Dismiss (spam, duplicate, date unavailable, not interested, other) | dismissed |
   | dismissed | Reopen | new |
5. **Convert** does this in one transaction:
   - uses the customer you pick, or reuses an existing customer with the same phone number,
     or creates a new customer;
   - creates a sales inquiry in `inquiries/{same id}` with `source: Website`, status `new`,
     the event date set to midday Asia/Karachi on the chosen day, and notes holding the
     package name, email and requirements;
   - marks the website inquiry `converted` and records who handled it and when.
   Running it twice, or on two phones at the same moment, returns the same result and
   creates no duplicates.
6. After converting, **Create quotation** opens the quotation editor with the customer,
   event type, guests and date already filled in. Saving the quotation links it to the
   inquiry and moves the sales inquiry to `quoted`. Manual inquiries also get a
   **Create quotation** button.

Converting does **not** create a quotation automatically. It never creates bookings or
payments and never reserves capacity. Those still go through the existing quotation →
accepted → booking → `transitionBooking` flow.

## Security changes

- `firebase/firestore.rules`: `publicInquiries` can now be read by active **owner, manager
  and sales** members (before this change, only the owner could read them). Kitchen and
  event staff, inactive members, other tenants and anonymous users are still denied. All
  client writes are still denied.
- `reviewPublicInquiry` checks for an active owner, manager or sales membership in the
  same tenant. It validates every identifier and only allows the transitions in the
  table above.

## Files

Added: `functions/inquiries.js`, `functions/test/inquiries.test.js`,
`lib/features/inquiries/website_inquiries.dart`, `test/website_inquiries_test.dart`,
`docs/milestone11.md`.
Modified: `functions/index.js` (registers the callable), `firebase/firestore.rules`,
`functions/test/storefront.integration.test.js`, `tests/security/firestore.rules.test.cjs`,
`lib/features/dashboard/presentation/dashboard_screen.dart`,
`lib/features/sales/presentation/sales_screens.dart`,
`lib/features/sales/data/sales_repository.dart`.

## Test results (run 22 Nov 2026, Linux, emulator project `demo-caterer-stage`)

- `flutter analyze`: no errors or warnings. Flutter 3.50 reports only its own
  `material.dart` deprecation notices, which an older local SDK will not show.
- `flutter test`: **24 passed** (17 existing + 7 new).
- `node --test functions/test/inquiries.test.js functions/test/storefront.test.js functions/test/migration_core.test.js`: **10 passed**.
- Callable integration suite on the emulators: **3 passed**. The new test covers
  role checks, cross-tenant denial, invalid transitions, concurrent convert idempotency,
  phone-match reuse, dismiss/reopen, and confirms that no booking, quotation, payment or
  capacity records are written.
- Firestore security rules suite: **9 passed**, including the new website-inquiry read and
  write test.

## Deploy to STAGING (Windows PowerShell). Do this only after Milestone 10 acceptance.

```powershell
cd C:\flutter_projects\catering_pro
firebase.cmd deploy --project caterer-pro-staging --config firebase.customer.json --only "functions:reviewPublicInquiry,firestore:rules"
gcloud functions list --gen2 --project caterer-pro-staging --format="table(name,state)"
flutter run --flavor staging --dart-define=APP_ENV=staging --dart-define=CUSTOMER_SITE_ORIGIN=https://caterer-pro-staging.web.app
```

Name the function exactly as shown. A plain `--only functions` would redeploy every
function.

## Staging acceptance checklist

1. Submit a test inquiry on `https://caterer-pro-staging.web.app/b/<slug>` in an incognito window.
2. In the staging app, the Home card shows a badge of 1. Open the inquiry and check the details.
3. Mark as contacted. It moves to the Contacted tab.
4. Convert. A customer and a sales inquiry (source Website) appear under Customers and Inquiries.
5. Create quotation. The fields are prefilled. Save it, and the sales inquiry shows `quoted`.
6. Submit a second inquiry with the same phone and convert it. No duplicate customer is created.
7. Submit a third inquiry, dismiss it as spam, then reopen it.
8. Sign in as a kitchen or event staff member, if you have one. The inbox must not load.
9. Check that the existing bookings, payments and capacity screens still work.

## Deferred (later milestones / launch hardening)

- Push or email notifications for new inquiries. FCM needs `firebase_messaging`, platform
  setup and APNs, and APNs requires an Apple Developer membership.
- Tap-to-call and WhatsApp links. These need the `url_launcher` package.
- App Check on `reviewPublicInquiry` and the public callables.
