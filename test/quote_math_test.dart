import 'package:flutter_test/flutter_test.dart';
import 'package:catering_pro/features/sales/domain/sales_models.dart';

void main() {
  test('per-head and fixed line amounts calculate in paisa', () {
    final q = QuoteMath(
      [
        const QuoteLine('a', 'Chicken Biryani', 150, 65000),
        const QuoteLine('b', 'Delivery', 1, 300000),
      ],
      extraPaisa: 50000,
      discountPaisa: 150000,
    );
    expect(q.subtotal, 10050000);
    expect(q.total, 9950000);
    q.validate();
  });
  test('negative totals are rejected', () {
    expect(
      () => QuoteMath([
        const QuoteLine('x', 'Menu', 1, 100),
      ], discountPaisa: 200).validate(),
      throwsStateError,
    );
  });
  test('zero quantity is rejected', () {
    expect(
      () => QuoteMath([const QuoteLine('x', 'Menu', 0, 100)]).validate(),
      throwsStateError,
    );
  });
}
