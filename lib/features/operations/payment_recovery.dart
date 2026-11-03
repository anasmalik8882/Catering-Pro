import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';

/// A locally durable *intent*, not proof that money was collected.
/// All amounts are integer paisa. Never store credentials in this record.
class PendingPayment {
  final String requestId;
  final String businessId;
  final String userId;
  final String bookingId;
  final int amountPaisa;
  final String method;
  final String reference;
  final String kind;

  const PendingPayment({
    required this.requestId,
    required this.businessId,
    required this.userId,
    required this.bookingId,
    required this.amountPaisa,
    required this.method,
    required this.reference,
    required this.kind,
  });

  factory PendingPayment.create({
    required String businessId,
    required String userId,
    required String bookingId,
    required int amountPaisa,
    required String reference,
    required String kind,
  }) => PendingPayment(
    requestId: const Uuid().v4(),
    businessId: businessId,
    userId: userId,
    bookingId: bookingId,
    amountPaisa: amountPaisa,
    method: 'manual',
    reference: reference.trim(),
    kind: kind,
  );

  Map<String, dynamic> toJson() => {
    'requestId': requestId,
    'businessId': businessId,
    'userId': userId,
    'bookingId': bookingId,
    'amountPaisa': amountPaisa,
    'method': method,
    'reference': reference,
    'kind': kind,
  };

  factory PendingPayment.fromJson(Map<String, dynamic> json) => PendingPayment(
    requestId: json['requestId'] as String,
    businessId: json['businessId'] as String,
    userId: json['userId'] as String,
    bookingId: json['bookingId'] as String,
    amountPaisa: json['amountPaisa'] as int,
    method: json['method'] as String,
    reference: json['reference'] as String,
    kind: json['kind'] as String,
  );
}

class PendingPaymentStore {
  const PendingPaymentStore();

  String _key(String businessId, String userId, String bookingId) =>
      'caterer.pending_payment.v1.${Uri.encodeComponent(businessId)}.${Uri.encodeComponent(userId)}.${Uri.encodeComponent(bookingId)}';

  Future<PendingPayment?> load(
    String businessId,
    String userId,
    String bookingId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(businessId, userId, bookingId));
    if (raw == null) return null;
    final payment = PendingPayment.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    if (payment.businessId != businessId ||
        payment.userId != userId ||
        payment.bookingId != bookingId) {
      throw StateError(
        'Pending payment belongs to a different account or booking.',
      );
    }
    return payment;
  }

  /// Never replace an unresolved intent; otherwise its idempotency key is lost.
  Future<void> saveNew(PendingPayment payment) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _key(payment.businessId, payment.userId, payment.bookingId);
    if (prefs.containsKey(key)) {
      throw StateError(
        'Resolve the existing pending payment before starting another.',
      );
    }
    final saved = await prefs.setString(key, jsonEncode(payment.toJson()));
    if (!saved) {
      throw StateError(
        'Could not securely retain the pending request. Payment not submitted.',
      );
    }
  }

  Future<void> clear(PendingPayment payment) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _key(payment.businessId, payment.userId, payment.bookingId);
    final raw = prefs.getString(key);
    if (raw == null) return;
    final stored = PendingPayment.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    if (stored.requestId != payment.requestId) {
      throw StateError(
        'Pending payment changed; refusing to clear another request.',
      );
    }
    if (!await prefs.remove(key)) {
      throw StateError(
        'Payment succeeded, but its local recovery record could not be removed.',
      );
    }
  }
}

/// Returns true only for explicit, terminal rejections emitted by the trusted
/// payment callable. Unknown failures may have committed remotely: preserve
/// their request IDs so recovery can safely ask the server again.
bool isDefinitivePaymentRejection(String code, String? message) {
  final normalizedCode = code.toLowerCase().replaceAll('_', '-');
  final detail = message ?? '';
  if (normalizedCode == 'failed-precondition') {
    return detail == 'Payment exceeds balance or refund exceeds net collections.' ||
        detail == 'Cancelled booking: manual reconciliation required.' ||
        detail == 'Invalid contract total.' ||
        detail == 'Payment balance inconsistent; reconcile before continuing.';
  }
  if (normalizedCode == 'invalid-argument') {
    return detail == 'Invalid payment data.';
  }
  if (normalizedCode == 'already-exists') {
    return detail == 'Idempotency key reused with different data.';
  }
  return false;
}
