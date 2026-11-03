Caterer Pro staging UX fixes (2026-10-27)

Changed: lib/features/operations/presentation/operations_screens.dart, lib/features/operations/payment_recovery.dart, test/payment_recovery_test.dart.

1) Calendar day event-count labels are limited to one line with ellipsis, preventing the narrow November 2 card overflow.
2) Known terminal trusted-payment business rejections clear the exact matching pending local intent and display only an OK dialog; ambiguous/network errors preserve the original request ID and retry/recovery dialog.
3) A new unit test covers the classification of definitive versus ambiguous errors.

Backup the three current files outside the Flutter project before copying. Run flutter analyze and flutter test after applying. Does not change Firebase config, Cloud Functions, or Firestore rules.
