import 'package:flutter_test/flutter_test.dart';
import 'package:catering_pro/features/operations/operations_repository.dart';

void main() {
  test('outstanding and event profit are calculated in paisa', () {
    const n = EventNumbers(12500000, 4000000, 3600000);
    expect(n.outstandingPaisa, 8500000);
    expect(n.estimatedProfitPaisa, 8900000);
    expect(n.cashAfterExpensesPaisa, 400000);
  });
  test('refunds lower net cash receipts', () {
    const n = EventNumbers(1000000, 300000, 120000);
    expect(n.outstandingPaisa, 700000);
  });
}
