import 'package:cloud_firestore/cloud_firestore.dart';

class BookingFinancialSummary {
  final int contracted;
  final int collected;
  final int expenses;
  const BookingFinancialSummary(this.contracted, this.collected, this.expenses);
  int get outstanding => contracted - collected;
  int get estimatedMargin => contracted - expenses;
}

/// Calculated from documents already loaded for the selected business.
/// Excludes cancelled bookings; event totals are gross contracted values, not cash revenue.
Map<String, BookingFinancialSummary> summarizeBookings(
  Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> bookings,
  Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> payments,
  Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> expenses,
) {
  final result = <String, BookingFinancialSummary>{};
  final cash = <String, int>{};
  final spent = <String, int>{};
  for (final p in payments) {
    final d = p.data();
    final id = d['bookingId'] as String?;
    if (id == null) continue;
    final value = (d['amountPaisa'] as num?)?.toInt() ?? 0;
    cash.update(
      id,
      (n) => n + (d['kind'] == 'refund' ? -value : value),
      ifAbsent: () => d['kind'] == 'refund' ? -value : value,
    );
  }
  for (final e in expenses) {
    final d = e.data();
    final id = d['bookingId'] as String?;
    if (id == null) continue;
    final value = (d['amountPaisa'] as num?)?.toInt() ?? 0;
    spent.update(id, (n) => n + value, ifAbsent: () => value);
  }
  for (final b in bookings) {
    final d = b.data();
    if (d['status'] == 'cancelled') continue;
    result[b.id] = BookingFinancialSummary(
      (d['totalPaisa'] as num?)?.toInt() ?? 0,
      cash[b.id] ?? 0,
      spent[b.id] ?? 0,
    );
  }
  return result;
}
