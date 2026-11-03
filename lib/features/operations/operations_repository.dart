import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';

/// Money is stored as integer paisa. Entries are append-only.
class OperationsRepository {
  final FirebaseFirestore db;
  final String businessId;
  final String userId;
  OperationsRepository(this.db, this.businessId, this.userId);

  CollectionReference<Map<String, dynamic>> records(String name) =>
      db.collection('businesses').doc(businessId).collection(name);
  Stream<QuerySnapshot<Map<String, dynamic>>> watch(String name) =>
      records(name).snapshots();

  /// One booking per quotation. Transaction checks quotation and capacity in
  /// one atomic operation. Configurable shift capacity is a separate rollout.
  Future<void> bookAcceptedQuote(String quoteId) async {
    final quoteRef = records('quotations').doc(quoteId);
    final bookingRef = records('bookings').doc(quoteId);
    await db.runTransaction((tx) async {
      final quote = await tx.get(quoteRef);
      final previous = await tx.get(bookingRef);
      if (!quote.exists || quote.data()?['status'] != 'accepted') {
        throw StateError('Only an accepted quotation can be booked.');
      }
      if (previous.exists) {
        throw StateError('A booking already exists for this quotation.');
      }
      final q = quote.data()!;
      tx.set(bookingRef, {
        'quotationId': quoteId,
        'quotationRevision': q['revision'],
        'customerId': q['customerId'],
        'eventType': q['eventType'],
        'eventDate': q['eventDate'],
        'guests': q['guests'],
        'totalPaisa': q['totalPaisa'],
        'status': 'tentative',
        'createdBy': userId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> initializeDailyCapacity(int maxGuestsPerDay) async {
    await FirebaseFunctions.instanceFor(region: 'asia-south1')
        .httpsCallable('initializeDailyCapacity')
        .call({'businessId': businessId, 'maxGuestsPerDay': maxGuestsPerDay});
  }

  Future<void> updateDailyCapacity(int maxGuestsPerDay) async {
    await FirebaseFunctions.instanceFor(region: 'asia-south1')
        .httpsCallable('updateDailyCapacity')
        .call({'businessId': businessId, 'maxGuestsPerDay': maxGuestsPerDay});
  }

  /// Server-authoritative status transition. Confirmation reserves capacity;
  /// cancellation releases it. The server validates the current status.
  Future<void> setBookingStatus(String id, String status) async {
    await FirebaseFunctions.instanceFor(region: 'asia-south1')
        .httpsCallable('transitionBooking')
        .call({'businessId': businessId, 'bookingId': id, 'status': status});
  }

  /// Append-only and idempotent. Financial limits are checked by a trusted
  /// transaction; never write payment documents directly from a client.
  Future<void> recordPayment({
    required String bookingId,
    required int amountPaisa,
    required String method,
    required String reference,
    required String kind,
    String? requestId,
  }) async {
    if (amountPaisa <= 0 || !['payment', 'refund'].contains(kind)) {
      throw ArgumentError('Invalid payment.');
    }
    final id = requestId ?? const Uuid().v4();
    if (!RegExp(r'^[a-zA-Z0-9-]{1,100}$').hasMatch(id)) {
      throw ArgumentError('Invalid payment request ID.');
    }
    await FirebaseFunctions.instanceFor(
      region: 'asia-south1',
    ).httpsCallable('recordBookingPayment').call({
      'businessId': businessId,
      'bookingId': bookingId,
      'amountPaisa': amountPaisa,
      'method': method,
      'reference': reference.trim(),
      'kind': kind,
      'requestId': id,
    });
  }

  Future<void> recordExpense({
    required String bookingId,
    required String category,
    required int amountPaisa,
    required String description,
  }) async {
    if (amountPaisa <= 0) throw ArgumentError('Expense must be positive.');
    final booking = await records('bookings').doc(bookingId).get();
    if (!booking.exists) throw StateError('Booking not found.');
    await records('expenses').add({
      'bookingId': bookingId,
      'category': category,
      'amountPaisa': amountPaisa,
      'description': description.trim(),
      'createdBy': userId,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addTask({
    required String bookingId,
    required String title,
    required String category,
    required DateTime dueAt,
    String assignee = '',
  }) async {
    if (title.trim().isEmpty) throw ArgumentError('Task title required.');
    await records('eventTasks').add({
      'bookingId': bookingId,
      'title': title.trim(),
      'category': category,
      'dueAt': Timestamp.fromDate(dueAt),
      'assignee': assignee.trim(),
      'completed': false,
      'createdBy': userId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> completeTask(String taskId, bool complete) =>
      records('eventTasks').doc(taskId).update({
        'completed': complete,
        'updatedAt': FieldValue.serverTimestamp(),
      });
}

class EventNumbers {
  final int contractedPaisa;
  final int paymentsPaisa;
  final int expensesPaisa;
  const EventNumbers(
    this.contractedPaisa,
    this.paymentsPaisa,
    this.expensesPaisa,
  );
  int get outstandingPaisa => contractedPaisa - paymentsPaisa;
  int get estimatedProfitPaisa => contractedPaisa - expensesPaisa;
  int get cashAfterExpensesPaisa => paymentsPaisa - expensesPaisa;
}
