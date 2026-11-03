import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../../core/app/session_controller.dart';
import '../../business/domain/business.dart';
import '../../sales/domain/sales_models.dart';
import '../operations_repository.dart';
import '../payment_recovery.dart';
import '../operations_exports.dart';
import '../operations_reporting.dart';

OperationsRepository operations() {
  final s = Get.find<SessionController>();
  return OperationsRepository(
    FirebaseFirestore.instance,
    s.business.value!.id,
    s.auth.currentUser!.uid,
  );
}

String eventDate(dynamic value) =>
    value is Timestamp ? DateFormat('dd MMM yyyy').format(value.toDate()) : '—';
String amount(int p) => pkr(p);
Future<void> safely(Future<void> Function() fn) async {
  try {
    await fn();
  } catch (e) {
    final message = e is FirebaseFunctionsException
        ? e.message ?? 'Request failed (${e.code}).'
        : e.toString();
    Get.snackbar(
      'Operation failed',
      message,
      snackPosition: SnackPosition.BOTTOM,
    );
  }
}

Future<String?> askText(
  BuildContext context,
  String label, {
  String initial = '',
}) async {
  final fieldController = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(label),
      content: TextField(
        controller: fieldController,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, fieldController.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  // Do not dispose controller synchronously: the dialog still animates out.
  return result;
}

class BookingsPage extends StatefulWidget {
  const BookingsPage({super.key});
  @override
  State<BookingsPage> createState() => _BookingsPageState();
}

class _BookingsPageState extends State<BookingsPage> {
  bool calendarMode = true;
  DateTime displayedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Event bookings'),
      actions: [
        IconButton(
          tooltip: calendarMode ? 'Show list' : 'Show calendar',
          icon: Icon(calendarMode ? Icons.list : Icons.calendar_month),
          onPressed: () => setState(() => calendarMode = !calendarMode),
        ),
        if (Get.find<SessionController>().membership.value?.role ==
            BusinessRole.owner)
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('businesses')
                .doc(Get.find<SessionController>().business.value!.id)
                .collection('settings')
                .doc('capacity')
                .snapshots(),
            builder: (context, snapshot) {
              final current = snapshot.data?.data()?['maxGuestsPerDay'];
              return IconButton(
                tooltip: current is int
                    ? 'Daily capacity: $current guests (edit)'
                    : 'Set daily guest capacity',
                icon: const Icon(Icons.tune),
                onPressed: !snapshot.hasData || snapshot.hasError
                    ? null
                    : () async {
                        final value = await askText(
                          context,
                          'Maximum guests per day',
                          initial: current is int ? '$current' : '',
                        );
                        if (value == null) return;
                        final maximum = int.tryParse(value);
                        if (maximum == null || maximum < 1 || maximum > 100000) {
                          Get.snackbar('Invalid capacity',
                              'Enter a number between 1 and 100000');
                          return;
                        }
                        if (current == maximum) return;
                        final repository = operations();
                        await safely(() => current is int
                            ? repository.updateDailyCapacity(maximum)
                            : repository.initializeDailyCapacity(maximum));
                      },
              );
            },
          ),
        IconButton(
          tooltip: 'Convert accepted quotation',
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => Get.to(() => const ConvertQuotePage()),
        ),
      ],
    ),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: operations().watch('bookings'),
      builder: (context, s) {
        if (s.hasError) {
          return Center(child: Text('Bookings unavailable: ${s.error}'));
        }
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final items = s.data!.docs.toList()
          ..sort(
            (a, b) =>
                ((a.data()['eventDate'] as Timestamp?)
                            ?.millisecondsSinceEpoch ??
                        0)
                    .compareTo(
                      (b.data()['eventDate'] as Timestamp?)
                              ?.millisecondsSinceEpoch ??
                          0,
                    ),
          );
        if (items.isEmpty) {
          return const Center(
            child: Text(
              'No bookings yet. Accept a quotation, then convert it to a booking.',
            ),
          );
        }
        if (calendarMode) {
          final monthStart = DateTime(
            displayedMonth.year,
            displayedMonth.month,
          );
          final offset = monthStart.weekday - 1;
          final count = DateTime(
            displayedMonth.year,
            displayedMonth.month + 1,
            0,
          ).day;
          final byDay =
              <int, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
          for (final booking in items) {
            final raw = booking.data()['eventDate'];
            if (raw is! Timestamp) continue;
            final date = raw.toDate();
            if (date.year == displayedMonth.year &&
                date.month == displayedMonth.month) {
              byDay.putIfAbsent(date.day, () => []).add(booking);
            }
          }
          return Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: () => setState(
                      () => displayedMonth = DateTime(
                        displayedMonth.year,
                        displayedMonth.month - 1,
                      ),
                    ),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text(
                    DateFormat('MMMM yyyy').format(displayedMonth),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  IconButton(
                    onPressed: () => setState(
                      () => displayedMonth = DateTime(
                        displayedMonth.year,
                        displayedMonth.month + 1,
                      ),
                    ),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              Row(
                children: [
                  for (final name in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                    Expanded(child: Center(child: Text(name))),
                ],
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: ((offset + count + 6) ~/ 7) * 7,
                  itemBuilder: (context, index) {
                    final day = index - offset + 1;
                    if (day < 1 || day > count) return const SizedBox.shrink();
                    final bookings = byDay[day] ?? [];
                    return InkWell(
                      onTap: bookings.isEmpty
                          ? null
                          : () => showModalBottomSheet<void>(
                              context: context,
                              showDragHandle: true,
                              builder: (c) => SafeArea(
                                child: ListView(
                                  shrinkWrap: true,
                                  children: [
                                    ListTile(
                                      title: Text(
                                        '$day ${DateFormat('MMMM').format(displayedMonth)} — ${bookings.length} event(s)',
                                      ),
                                    ),
                                    ...bookings.map(
                                      (b) => ListTile(
                                        title: Text('${b.data()['eventType']}'),
                                        subtitle: Text(
                                          '${b.data()['guests']} guests · ${b.data()['status']}',
                                        ),
                                        onTap: () {
                                          Navigator.pop(c);
                                          Get.to(
                                            () => EventDetailsPage(
                                              bookingId: b.id,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                      child: Card(
                        margin: const EdgeInsets.all(2),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Column(
                            children: [
                              Text('$day'),
                              if (bookings.isNotEmpty)
                                Text(
                                  '${bookings.length} event${bookings.length == 1 ? '' : 's'}',
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              if (bookings.any(
                                (b) => b.data()['status'] == 'confirmed',
                              ))
                                const Icon(
                                  Icons.circle,
                                  size: 8,
                                  color: Colors.green,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        }
        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, i) {
            final b = items[i], d = b.data();
            return Card(
              child: ListTile(
                title: Text('${d['eventType']} · ${eventDate(d['eventDate'])}'),
                subtitle: Text(
                  '${d['guests']} guests · ${d['status']} · ${amount((d['totalPaisa'] as num).toInt())}',
                ),
                onTap: () => Get.to(() => EventDetailsPage(bookingId: b.id)),
                trailing: const Icon(Icons.chevron_right),
              ),
            );
          },
        );
      },
    ),
  );
}

class ConvertQuotePage extends StatelessWidget {
  const ConvertQuotePage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Accepted quotations')),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: operations().watch('quotations'),
      builder: (context, s) {
        if (s.hasError) return Center(child: Text('${s.error}'));
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final quotes = s.data!.docs
            .where((d) => d.data()['status'] == 'accepted')
            .toList();
        if (quotes.isEmpty) {
          return const Center(
            child: Text(
              'No accepted quotations. Mark a sent quotation accepted first.',
            ),
          );
        }
        return ListView(
          children: quotes
              .map(
                (q) => ListTile(
                  title: Text(
                    '${q.data()['eventType']} · ${amount((q.data()['totalPaisa'] as num).toInt())}',
                  ),
                  subtitle: Text(
                    '${eventDate(q.data()['eventDate'])} · ${q.data()['guests']} guests',
                  ),
                  trailing: const Icon(Icons.add),
                  onTap: () => safely(() async {
                    await operations().bookAcceptedQuote(q.id);
                    if (context.mounted) Navigator.pop(context);
                  }),
                ),
              )
              .toList(),
        );
      },
    ),
  );
}

class EventDetailsPage extends StatefulWidget {
  final String bookingId;
  const EventDetailsPage({super.key, required this.bookingId});
  @override
  State<EventDetailsPage> createState() => _EventDetailsPageState();
}

class _EventDetailsPageState extends State<EventDetailsPage> {
  bool _changingStatus = false;
  @override
  Widget build(BuildContext context) {
    final repo = operations();
    return Scaffold(
      appBar: AppBar(title: const Text('Event operations')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: repo.records('bookings').doc(widget.bookingId).snapshots(),
        builder: (context, s) {
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!s.data!.exists) {
            return const Center(child: Text('Booking no longer exists'));
          }
          final b = s.data!.data()!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${b['eventType']} · ${eventDate(b['eventDate'])}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                '${b['guests']} guests · ${amount((b['totalPaisa'] as num).toInt())}',
              ),
              const SizedBox(height: 12),
              if (_changingStatus) const LinearProgressIndicator(),
              const SizedBox(height: 6),
              Builder(
                builder: (context) {
                  const transitions = <String, List<String>>{
                    'tentative': ['confirmed', 'cancelled'],
                    'confirmed': ['preparation', 'cancelled'],
                    'preparation': ['ready', 'cancelled'],
                    'ready': ['in_progress', 'cancelled'],
                    'in_progress': ['completed'],
                    'completed': ['closed'],
                  };
                  final current = b['status'] as String? ?? 'tentative';
                  final allowed = transitions[current] ?? const <String>[];
                  return DropdownButtonFormField<String>(
                    key: ValueKey('$current:$_changingStatus'),
                    initialValue: current,
                    decoration: const InputDecoration(
                      labelText: 'Event status',
                      border: OutlineInputBorder(),
                    ),
                    items: [current, ...allowed]
                        .map((x) => DropdownMenuItem(value: x, child: Text(x)))
                        .toList(),
                    onChanged: _changingStatus || allowed.isEmpty
                        ? null
                        : (v) async {
                            if (v == null || !allowed.contains(v)) return;
                            setState(() => _changingStatus = true);
                            try {
                              await repo.setBookingStatus(widget.bookingId, v);
                            } catch (e) {
                              final message = e is FirebaseFunctionsException
                                  ? e.message ?? e.code
                                  : e.toString();
                              Get.snackbar(
                                'Status update failed',
                                message,
                                snackPosition: SnackPosition.BOTTOM,
                              );
                            } finally {
                              if (mounted) {
                                setState(() => _changingStatus = false);
                              }
                            }
                          },
                  );
                },
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Get.to(
                  () => EventFinancePage(
                    bookingId: widget.bookingId,
                    totalPaisa: (b['totalPaisa'] as num).toInt(),
                  ),
                ),
                icon: const Icon(Icons.account_balance_wallet),
                label: const Text('Payments, expenses & profit'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () =>
                    Get.to(() => EventTasksPage(bookingId: widget.bookingId)),
                icon: const Icon(Icons.checklist),
                label: const Text('Kitchen, staff & dispatch tasks'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class EventFinancePage extends StatelessWidget {
  final String bookingId;
  final int totalPaisa;
  const EventFinancePage({
    super.key,
    required this.bookingId,
    required this.totalPaisa,
  });
  @override
  Widget build(BuildContext context) {
    final repo = operations();
    return Scaffold(
      appBar: AppBar(title: const Text('Event finances')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: repo.watch('payments'),
        builder: (context, ps) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: repo.watch('expenses'),
          builder: (context, es) {
            if (ps.hasError || es.hasError) {
              return Center(
                child: Text('Could not load finances: ${ps.error ?? es.error}'),
              );
            }
            if (!ps.hasData || !es.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final payments = ps.data!.docs
                .where((e) => e.data()['bookingId'] == bookingId)
                .toList();
            final expenses = es.data!.docs
                .where((e) => e.data()['bookingId'] == bookingId)
                .toList();
            final received = payments.fold<int>(
              0,
              (n, d) =>
                  n +
                  (d.data()['amountPaisa'] as num).toInt() *
                      (d.data()['kind'] == 'refund' ? -1 : 1),
            );
            final spent = expenses.fold<int>(
              0,
              (n, d) => n + (d.data()['amountPaisa'] as num).toInt(),
            );
            final numbers = EventNumbers(totalPaisa, received, spent);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Contract value: ${amount(totalPaisa)}'),
                        Text('Net collected: ${amount(received)}'),
                        Text(
                          'Outstanding: ${amount(numbers.outstandingPaisa)}',
                        ),
                        Text('Recorded expenses: ${amount(spent)}'),
                        Text(
                          'Estimated event profit: ${amount(numbers.estimatedProfitPaisa)}',
                        ),
                        const Text(
                          'Profit is based on recorded expenses; unentered costs are excluded.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                      onPressed: () => _paymentDialog(context, repo, bookingId),
                      child: const Text('Record payment / refund'),
                    ),
                    OutlinedButton(
                      onPressed: () => _expenseDialog(context, repo, bookingId),
                      child: const Text('Record expense'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Ledger (append-only)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                ...payments.map(
                  (d) => ListTile(
                    title: Text(
                      '${d.data()['kind']} · ${amount((d.data()['amountPaisa'] as num).toInt())}',
                    ),
                    subtitle: Text(
                      '${d.data()['method']} · ${d.data()['reference']}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Payment acknowledgement PDF',
                      icon: const Icon(Icons.picture_as_pdf),
                      onPressed: () async {
                        final data = d.data();
                        final session = Get.find<SessionController>();
                        await exportPaymentAcknowledgement(
                          businessName:
                              session.business.value?.name ?? 'Caterer Pro',
                          bookingId: bookingId,
                          entryId: d.id,
                          amountPaisa: (data['amountPaisa'] as num).toInt(),
                          kind: data['kind'] as String? ?? 'payment',
                          method: data['method'] as String? ?? 'manual',
                          reference: data['reference'] as String? ?? '',
                          timestamp:
                              (data['createdAt'] as Timestamp?)?.toDate() ??
                              DateTime.now(),
                        );
                      },
                    ),
                  ),
                ),
                const Divider(),
                Text(
                  'Expenses',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                ...expenses.map(
                  (d) => ListTile(
                    title: Text(
                      '${d.data()['category']} · ${amount((d.data()['amountPaisa'] as num).toInt())}',
                    ),
                    subtitle: Text('${d.data()['description']}'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

Future<void> _paymentDialog(
  BuildContext context,
  OperationsRepository repo,
  String bookingId,
) async {
  const store = PendingPaymentStore();
  PendingPayment? pending;
  try {
    pending = await store.load(repo.businessId, repo.userId, bookingId);
  } catch (error) {
    Get.snackbar(
      'Recovery unavailable',
      '$error',
      snackPosition: SnackPosition.BOTTOM,
    );
    return;
  }
  if (!context.mounted) return;

  if (pending != null) {
    final recover = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Unresolved payment request'),
        content: Text(
          'A previous ${pending!.kind} of PKR ${(pending.amountPaisa / 100).toStringAsFixed(2)} '
          'has not been confirmed on this device.\n\n'
          'Retrying sends the original request ID and amount; the server will not record it twice. '
          'Do not create a replacement request until this one is reconciled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Recover safely'),
          ),
        ],
      ),
    );
    if (recover != true) return;
  } else {
    final amountText = await askText(context, 'Amount in PKR');
    if (amountText == null) return;
    // Reject extra precision rather than silently rounding a payment.
    final amountPattern = RegExp(r'^\d+(?:\.\d{1,2})?$');
    if (!amountPattern.hasMatch(amountText.trim())) {
      Get.snackbar(
        'Invalid amount',
        'Enter a positive amount with at most two decimal places.',
      );
      return;
    }
    final parts = amountText.trim().split('.');
    final whole = int.tryParse(parts[0]);
    final fraction = parts.length == 2
        ? int.parse(parts[1].padRight(2, '0'))
        : 0;
    if (whole == null || whole > 10000000000) {
      Get.snackbar('Invalid amount', 'Amount is outside supported range.');
      return;
    }
    final amountPaisa = whole * 100 + fraction;
    if (amountPaisa <= 0 || amountPaisa > 1000000000000) {
      Get.snackbar('Invalid amount', 'Amount is outside supported range.');
      return;
    }
    if (!context.mounted) return;
    final kind = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Entry type'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, 'payment'),
            child: const Text('Payment received'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, 'refund'),
            child: const Text('Refund issued'),
          ),
        ],
      ),
    );
    if (kind == null || !context.mounted) return;
    final reference = await askText(context, 'Reference / receipt notes');
    if (reference == null) return;
    pending = PendingPayment.create(
      businessId: repo.businessId,
      userId: repo.userId,
      bookingId: bookingId,
      amountPaisa: amountPaisa,
      reference: reference,
      kind: kind,
    );
    try {
      // Persist BEFORE network submission so a crash does not lose the key.
      await store.saveNew(pending);
    } catch (error) {
      Get.snackbar(
        'Payment not submitted',
        '$error',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
  }

  final intent = pending;
  while (true) {
    try {
      await repo.recordPayment(
        bookingId: intent.bookingId,
        amountPaisa: intent.amountPaisa,
        method: intent.method,
        reference: intent.reference,
        kind: intent.kind,
        requestId: intent.requestId,
      );
      try {
        await store.clear(intent);
      } catch (error) {
        Get.snackbar(
          'Recorded, recovery cleanup pending',
          '$error',
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }
      Get.snackbar(
        'Saved',
        'Payment entry recorded successfully.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    } catch (error) {
      if (!context.mounted) return;
      final message = error is FirebaseFunctionsException
          ? error.message ?? error.code
          : error.toString();
      // Clear only explicitly recognized server-side business-rule rejections.
      // Network, transport, and unknown errors may have committed remotely, so
      // their original request IDs MUST remain available for safe recovery.
      if (error is FirebaseFunctionsException &&
          isDefinitivePaymentRejection(error.code, error.message)) {
        try {
          await store.clear(intent);
        } catch (cleanupError) {
          if (!context.mounted) return;
          await showDialog<void>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Payment rejected; cleanup incomplete'),
              content: Text(
                '$message\n\nThe server rejected the request, but its local '
                'recovery record could not be cleared: $cleanupError',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
          return;
        }
        if (!context.mounted) return;
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Payment rejected'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }
      final retry = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Payment not confirmed'),
          content: Text(
            '$message\n\nThe original request is saved on this device. '
            'Retry safely now, or reopen this booking later to recover it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Retry safely'),
            ),
          ],
        ),
      );
      if (retry != true) return;
    }
  }
}

Future<void> _expenseDialog(
  BuildContext context,
  OperationsRepository repo,
  String bookingId,
) async {
  final amountText = await askText(context, 'Expense amount in PKR');
  if (amountText == null) return;
  final amt = num.tryParse(amountText);
  if (amt == null || amt <= 0) {
    Get.snackbar('Invalid amount', 'Enter positive amount');
    return;
  }
  if (!context.mounted) return;
  final category = await askText(
    context,
    'Category (ingredients / labour / transport / rental)',
  );
  if (category == null || category.isEmpty) return;
  if (!context.mounted) return;
  final desc = await askText(context, 'Description');
  if (desc == null) return;
  await safely(
    () => repo.recordExpense(
      bookingId: bookingId,
      category: category,
      amountPaisa: (amt * 100).round(),
      description: desc,
    ),
  );
}

class EventTasksPage extends StatelessWidget {
  final String bookingId;
  const EventTasksPage({super.key, required this.bookingId});
  @override
  Widget build(BuildContext context) {
    final repo = operations();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Event preparation'),
        actions: [
          IconButton(
            tooltip: 'Export preparation sheet',
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: () async {
              final booking = await repo
                  .records('bookings')
                  .doc(bookingId)
                  .get();
              if (!booking.exists) return;
              final tasks = await repo
                  .records('eventTasks')
                  .where('bookingId', isEqualTo: bookingId)
                  .get();
              final b = booking.data()!;
              final session = Get.find<SessionController>();
              await exportPreparationSheet(
                businessName: session.business.value?.name ?? 'Caterer Pro',
                bookingId: bookingId,
                eventName: b['eventType'] as String? ?? 'Event',
                eventDate: (b['eventDate'] as Timestamp).toDate(),
                guests: (b['guests'] as num).toInt(),
                tasks: tasks.docs.map((d) {
                  final t = d.data();
                  return {
                    'category': '${t['category'] ?? ''}',
                    'title': '${t['title'] ?? ''}',
                    'assignee': '${t['assignee'] ?? ''}',
                    'completed': t['completed'] == true ? 'Yes' : 'No',
                  };
                }).toList(),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              final title = await askText(context, 'Task title');
              if (title == null || title.isEmpty || !context.mounted) return;
              final category = await showDialog<String>(
                context: context,
                builder: (c) => SimpleDialog(
                  title: const Text('Task category'),
                  children:
                      ['kitchen', 'staff', 'transport', 'equipment', 'delivery']
                          .map(
                            (x) => SimpleDialogOption(
                              onPressed: () => Navigator.pop(c, x),
                              child: Text(x),
                            ),
                          )
                          .toList(),
                ),
              );
              if (category == null) return;
              await safely(
                () => repo.addTask(
                  bookingId: bookingId,
                  title: title,
                  category: category,
                  dueAt: DateTime.now(),
                ),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: repo.watch('eventTasks'),
        builder: (context, s) {
          if (s.hasError) {
            return Center(child: Text('Cannot load tasks: ${s.error}'));
          }
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final tasks = s.data!.docs
              .where((e) => e.data()['bookingId'] == bookingId)
              .toList();
          if (tasks.isEmpty) {
            return const Center(
              child: Text(
                'No preparation tasks. Add kitchen, staff or delivery tasks.',
              ),
            );
          }
          return ListView(
            children: tasks
                .map(
                  (d) => CheckboxListTile(
                    value: d.data()['completed'] == true,
                    title: Text('${d.data()['title']}'),
                    subtitle: Text(
                      '${d.data()['category']} · ${d.data()['assignee']}',
                    ),
                    onChanged: (v) =>
                        safely(() => repo.completeTask(d.id, v == true)),
                  ),
                )
                .toList(),
          );
        },
      ),
    );
  }
}

class FinanceOverviewPage extends StatelessWidget {
  const FinanceOverviewPage({super.key});
  @override
  Widget build(BuildContext context) {
    final repo = operations();
    return Scaffold(
      appBar: AppBar(title: const Text('Finance & profit reports')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: repo.watch('bookings'),
        builder: (context, bs) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: repo.watch('payments'),
          builder: (context, ps) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: repo.watch('expenses'),
            builder: (context, es) {
              if (bs.hasError || ps.hasError || es.hasError) {
                return Center(
                  child: Text(
                    'Could not load report: ${bs.error ?? ps.error ?? es.error}',
                  ),
                );
              }
              if (!bs.hasData || !ps.hasData || !es.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final summaries = summarizeBookings(
                bs.data!.docs,
                ps.data!.docs,
                es.data!.docs,
              );
              final contracted = summaries.values.fold<int>(
                0,
                (n, e) => n + e.contracted,
              );
              final collected = summaries.values.fold<int>(
                0,
                (n, e) => n + e.collected,
              );
              final spent = summaries.values.fold<int>(
                0,
                (n, e) => n + e.expenses,
              );
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Business overview',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _MetricCard('Active events', '${summaries.length}'),
                      _MetricCard('Contracted', amount(contracted)),
                      _MetricCard('Net collected', amount(collected)),
                      _MetricCard(
                        'Outstanding',
                        amount(contracted - collected),
                      ),
                      _MetricCard('Recorded costs', amount(spent)),
                      _MetricCard(
                        'Estimated margin',
                        amount(contracted - spent),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Values cover all non-cancelled bookings loaded for this business. Margin excludes unrecorded expenses; contracted value is not cash received.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const Divider(),
                  Text(
                    'Event breakdown',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  ...bs.data!.docs.where((b) => summaries.containsKey(b.id)).map((
                    b,
                  ) {
                    final n = summaries[b.id]!;
                    return Card(
                      child: ListTile(
                        title: Text(
                          '${b.data()['eventType']} · ${eventDate(b.data()['eventDate'])}',
                        ),
                        subtitle: Text(
                          'Collected: ${amount(n.collected)} · Due: ${amount(n.outstanding)}\nEstimated margin: ${amount(n.estimatedMargin)}',
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Get.to(
                          () => EventFinancePage(
                            bookingId: b.id,
                            totalPaisa: n.contracted,
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  const _MetricCard(this.label, this.value);
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 155,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 5),
            Text(value, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    ),
  );
}
