# Caterer Pro — Flutter trusted operations reliability patch

## Applies to
Latest project archive `catering_pro(20261026-074309).zip`.

## Replace these files in your Flutter project
- `lib/features/operations/operations_repository.dart`
- `lib/features/operations/presentation/operations_screens.dart`

Make a backup or git commit before replacement.

## Changes
1. Payment repository accepts optional caller-provided `requestId`, validated for Cloud Function compatibility. Generates a UUID otherwise.
2. Payment entry dialog generates one UUID and reuses it whenever user selects **Retry safely** after a failed or uncertain network result. Existing backend `recordBookingPayment` idempotency ensures retries don't create a second entry.
3. Booking detail screen allows only transitions supported by `transitionBooking`, disables the dropdown while an update runs, and displays Cloud Function errors.
4. Generic operation error reports prefer FirebaseFunctionsException.message.

## Validate locally (Windows PowerShell)
```
cd C:\flutter_projects\catering_pro
flutter pub get
dart format lib/features/operations/operations_repository.dart lib/features/operations/presentation/operations_screens.dart
flutter analyze
flutter test
```
Run the Android app and verify the booking status and payment flows against a properly configured staging backend. Do NOT test against live financial entries simply to validate UI.

## IMPORTANT: Outstanding production blockers
- Your real Firestore database currently has historical records. Do not use the in-app Initialize Daily Capacity action on that business; migration is required.
- A payment's idempotency key is only retained within the current payment dialog's retry loop. After closing/restarting the app, re-entering the same payment generates a new key; first check the ledger. Persist pending payment request intents durably for full crash/offline replay protection before production.
- Firebase App Check is not enforced on the callable functions. Plan configuration before production, including Windows-friendly development debug tokens and platform support.
- Existing booking creation is a direct client Firestore transaction that creates tentative bookings. The current security rules permit this and prohibit client status writes; trusted server confirmation is used for reservations. Assess whether booking creation should also be server authoritative.
- Production rollback requires verified Firestore export/restore, migrating legacy balances, dual-write freeze, staging deployment rehearsal and proper IAM permissions. This patch does not deploy or migrate anything.
- Re-run emulator tests with Node 22 before production deployment; current success was observed under Node 24.

No backend files, rules, or firebase configs are changed by this patch.
