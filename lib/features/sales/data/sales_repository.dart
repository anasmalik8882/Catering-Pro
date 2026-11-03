import 'package:cloud_firestore/cloud_firestore.dart';
import '../domain/sales_models.dart';

class SalesRepository {
  final FirebaseFirestore db;
  final String businessId;
  final String userId;
  SalesRepository(this.db, this.businessId, this.userId);

  CollectionReference<Json> collection(String name) =>
      db.collection('businesses').doc(businessId).collection(name);
  Stream<List<SalesRecord>> watch(String name) =>
      collection(name).snapshots().map((s) {
        final records = s.docs.map((d) => SalesRecord(d.id, d.data())).toList();
        records.sort(
          (a, b) => b.str('createdAt').compareTo(a.str('createdAt')),
        );
        return records;
      });

  Future<String> createCustomer({
    required String name,
    required String phone,
    String email = '',
    String notes = '',
  }) async {
    final ref = collection('customers').doc();
    await ref.set({
      'name': name.trim(),
      'phone': phone.trim(),
      'email': email.trim(),
      'notes': notes.trim(),
      'createdBy': userId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> updateCustomer(
    String id, {
    required String name,
    required String phone,
    String email = '',
    String notes = '',
  }) => collection('customers').doc(id).update({
    'name': name.trim(),
    'phone': phone.trim(),
    'email': email.trim(),
    'notes': notes.trim(),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Future<void> createInquiry({
    required String customerId,
    required String eventType,
    required int guests,
    required DateTime eventDate,
    required String source,
    String notes = '',
  }) async {
    final ref = collection('inquiries').doc();
    await ref.set({
      'customerId': customerId,
      'eventType': eventType,
      'guests': guests,
      'eventDate': Timestamp.fromDate(eventDate),
      'source': source,
      'notes': notes.trim(),
      'status': 'new',
      'followUpAt': null,
      'createdBy': userId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateInquiry(String id, String status, DateTime? followUp) =>
      collection('inquiries').doc(id).update({
        'status': status,
        'followUpAt': followUp == null ? null : Timestamp.fromDate(followUp),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> createMenu({
    required String name,
    required String type,
    required int pricePaisa,
    required String unit,
    String description = '',
  }) async {
    await collection('menuItems').add({
      'name': name.trim(),
      'type': type,
      'pricePaisa': pricePaisa,
      'unit': unit,
      'description': description.trim(),
      'active': true,
      'createdBy': userId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateMenu(
    String id, {
    required String name,
    required String type,
    required int pricePaisa,
    required String unit,
    String description = '',
    required bool active,
  }) => collection('menuItems').doc(id).update({
    'name': name.trim(),
    'type': type,
    'pricePaisa': pricePaisa,
    'unit': unit,
    'description': description.trim(),
    'active': active,
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Future<void> createPackage({
    required String name,
    required String pricingMode,
    required int pricePaisa,
    required int minimumGuests,
    required String description,
  }) async {
    await collection('packages').add({
      'name': name.trim(),
      'pricingMode': pricingMode,
      'pricePaisa': pricePaisa,
      'minimumGuests': minimumGuests,
      'description': description.trim(),
      'active': true,
      'createdBy': userId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String> createQuote({
    required String customerId,
    String inquiryId = '',
    required String eventType,
    required int guests,
    required DateTime eventDate,
    required List<QuoteLine> lines,
    int extraPaisa = 0,
    int discountPaisa = 0,
    String notes = '',
    DateTime? validUntil,
  }) async {
    final calculated = QuoteMath(
      lines,
      extraPaisa: extraPaisa,
      discountPaisa: discountPaisa,
    )..validate();
    if (guests < 1) throw StateError('Guest count must be positive.');
    final ref = collection('quotations').doc();
    final now = FieldValue.serverTimestamp();
    final version = <String, dynamic>{
      'revision': 1,
      'lines': lines.map((l) => l.toJson()).toList(),
      'subtotalPaisa': calculated.subtotal,
      'extraPaisa': extraPaisa,
      'discountPaisa': discountPaisa,
      'totalPaisa': calculated.total,
      'notes': notes.trim(),
      'createdAt': now,
    };
    final batch = db.batch();
    batch.set(ref, {
      'customerId': customerId,
      'inquiryId': inquiryId,
      'eventType': eventType,
      'guests': guests,
      'eventDate': Timestamp.fromDate(eventDate),
      'validUntil': validUntil == null ? null : Timestamp.fromDate(validUntil),
      'status': 'draft',
      'revision': 1,
      'totalPaisa': calculated.total,
      'createdBy': userId,
      'createdAt': now,
      'updatedAt': now,
    });
    batch.set(ref.collection('revisions').doc('1'), version);
    await batch.commit();
    return ref.id;
  }

  Future<void> reviseQuote(
    SalesRecord quote,
    List<QuoteLine> lines, {
    int extraPaisa = 0,
    int discountPaisa = 0,
    String notes = '',
  }) async {
    final value = QuoteMath(
      lines,
      extraPaisa: extraPaisa,
      discountPaisa: discountPaisa,
    )..validate();
    final ref = collection('quotations').doc(quote.id);
    await db.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) throw StateError('Quotation no longer exists.');
      final data = snapshot.data()!;
      if (!['draft', 'sent'].contains(data['status'])) {
        throw StateError('This quotation can no longer be revised.');
      }
      final next = (data['revision'] as int) + 1;
      final revisionRef = ref.collection('revisions').doc('$next');
      transaction.set(revisionRef, {
        'revision': next,
        'lines': lines.map((l) => l.toJson()).toList(),
        'subtotalPaisa': value.subtotal,
        'extraPaisa': extraPaisa,
        'discountPaisa': discountPaisa,
        'totalPaisa': value.total,
        'notes': notes.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.update(ref, {
        'revision': next,
        'totalPaisa': value.total,
        'status': 'draft',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> markQuote(String id, String status) async =>
      collection('quotations').doc(id).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
  Future<SalesRecord> revision(String quoteId, int revision) async {
    final snapshot = await collection(
      'quotations',
    ).doc(quoteId).collection('revisions').doc('$revision').get();
    if (!snapshot.exists) throw StateError('Quotation revision missing.');
    return SalesRecord(snapshot.id, snapshot.data()!);
  }
}
