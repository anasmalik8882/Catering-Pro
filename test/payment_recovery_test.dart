import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:catering_pro/features/operations/payment_recovery.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('persists identical payment payload and request ID on reload', () async {
    const store = PendingPaymentStore();
    final payment = PendingPayment.create(
      businessId: 'b1',
      userId: 'u1',
      bookingId: 'booking1',
      amountPaisa: 12345,
      reference: 'receipt-123',
      kind: 'payment',
    );
    await store.saveNew(payment);
    final restored = await const PendingPaymentStore().load(
      'b1',
      'u1',
      'booking1',
    );
    expect(restored!.toJson(), payment.toJson());
    expect(restored.requestId, payment.requestId);
  });

  test('does not overwrite an unresolved payment intent', () async {
    const store = PendingPaymentStore();
    final p1 = PendingPayment.create(
      businessId: 'b',
      userId: 'u',
      bookingId: 'q',
      amountPaisa: 100,
      reference: '',
      kind: 'payment',
    );
    final p2 = PendingPayment.create(
      businessId: 'b',
      userId: 'u',
      bookingId: 'q',
      amountPaisa: 200,
      reference: '',
      kind: 'payment',
    );
    await store.saveNew(p1);
    await expectLater(store.saveNew(p2), throwsStateError);
    expect((await store.load('b', 'u', 'q'))!.requestId, p1.requestId);
  });

  test('isolates pending requests by business, user and booking', () async {
    const store = PendingPaymentStore();
    final p = PendingPayment.create(
      businessId: 'b1',
      userId: 'u1',
      bookingId: 'q1',
      amountPaisa: 100,
      reference: '',
      kind: 'refund',
    );
    await store.saveNew(p);
    expect(await store.load('b2', 'u1', 'q1'), isNull);
    expect(await store.load('b1', 'u2', 'q1'), isNull);
    expect(await store.load('b1', 'u1', 'q2'), isNull);
  });

  test('clears only matching completed request', () async {
    const store = PendingPaymentStore();
    final p = PendingPayment.create(
      businessId: 'b',
      userId: 'u',
      bookingId: 'q',
      amountPaisa: 100,
      reference: '',
      kind: 'payment',
    );
    final other = PendingPayment.create(
      businessId: 'b',
      userId: 'u',
      bookingId: 'q',
      amountPaisa: 100,
      reference: '',
      kind: 'payment',
    );
    await store.saveNew(p);
    await expectLater(store.clear(other), throwsStateError);
    expect(await store.load('b', 'u', 'q'), isNotNull);
    await store.clear(p);
    expect(await store.load('b', 'u', 'q'), isNull);
  });

  test('clears only definite trusted payment rejections', () {
    expect(isDefinitivePaymentRejection('failed-precondition',
        'Payment exceeds balance or refund exceeds net collections.'), isTrue);
    expect(isDefinitivePaymentRejection('already-exists',
        'Idempotency key reused with different data.'), isTrue);
    expect(isDefinitivePaymentRejection('invalid-argument',
        'Invalid payment data.'), isTrue);
    expect(isDefinitivePaymentRejection('unavailable', 'Network unavailable'), isFalse);
    expect(isDefinitivePaymentRejection('deadline-exceeded', 'Timeout'), isFalse);
    expect(isDefinitivePaymentRejection('internal', 'Unknown failure'), isFalse);
    expect(isDefinitivePaymentRejection('failed-precondition', 'Unknown failure'), isFalse);
  });
}
