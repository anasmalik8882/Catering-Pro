import 'package:cloud_firestore/cloud_firestore.dart';

typedef Json = Map<String, dynamic>;

int money(num value) => (value * 100).round();
String pkr(int paisa) => 'Rs ${(paisa / 100).toStringAsFixed(2)}';

class QuoteLine {
  final String itemId;
  final String title;
  final int quantity;
  final int unitPaisa;
  const QuoteLine(this.itemId, this.title, this.quantity, this.unitPaisa);
  int get total => quantity * unitPaisa;
  Json toJson() => {
    'itemId': itemId,
    'title': title,
    'quantity': quantity,
    'unitPaisa': unitPaisa,
    'totalPaisa': total,
  };
  factory QuoteLine.fromJson(Json j) => QuoteLine(
    '${j['itemId'] ?? ''}',
    '${j['title'] ?? ''}',
    (j['quantity'] as num).toInt(),
    (j['unitPaisa'] as num).toInt(),
  );
}

class QuoteMath {
  final List<QuoteLine> lines;
  final int extraPaisa;
  final int discountPaisa;
  const QuoteMath(this.lines, {this.extraPaisa = 0, this.discountPaisa = 0});
  int get subtotal => lines.fold(0, (subtotal, line) => subtotal + line.total);
  int get total => subtotal + extraPaisa - discountPaisa;
  void validate() {
    if (lines.isEmpty ||
        lines.any(
          (l) => l.quantity <= 0 || l.unitPaisa < 0 || l.title.trim().isEmpty,
        )) {
      throw StateError('Add valid quotation items.');
    }
    if (extraPaisa < 0 || discountPaisa < 0 || total < 0) {
      throw StateError('Invalid extra charges or discount.');
    }
  }
}

class SalesRecord {
  final String id;
  final Json data;
  const SalesRecord(this.id, this.data);
  String str(String key) => '${data[key] ?? ''}';
  int number(String key) => (data[key] is num) ? (data[key] as num).toInt() : 0;
  DateTime? date(String key) =>
      (data[key] is Timestamp) ? (data[key] as Timestamp).toDate() : null;
}
