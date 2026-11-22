// Milestone 11: website inquiry inbox → customer → sales inquiry → quotation.
//
// Website submissions (businesses/{bid}/publicInquiries) are read-only for
// clients. Every status change goes through the trusted reviewPublicInquiry
// callable, which also performs the idempotent conversion.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../sales/domain/sales_models.dart';
import '../sales/presentation/sales_screens.dart';

typedef InquiryJson = Map<String, dynamic>;

/// Public inquiry statuses in inbox order.
const websiteInquiryStatuses = ['new', 'contacted', 'converted', 'dismissed'];

String websiteStatusLabel(String status) => switch (status) {
  'new' => 'New',
  'contacted' => 'Contacted',
  'converted' => 'Converted',
  'dismissed' => 'Dismissed',
  _ => status,
};

/// Actions the backend accepts from each status (mirrors functions/inquiries.js).
List<String> websiteInquiryActions(String status) => switch (status) {
  'new' => ['convert', 'contacted', 'dismiss'],
  'contacted' => ['convert', 'dismiss'],
  'dismissed' => ['reopen'],
  _ => const [],
};

const dismissReasons = {
  'spam': 'Spam',
  'duplicate': 'Duplicate',
  'unavailable': 'Date unavailable',
  'not_interested': 'Customer not interested',
  'other': 'Other',
};

abstract class InquiryReviewGateway {
  Future<InquiryJson> review(
    String businessId,
    String inquiryId,
    String action, {
    String? customerId,
    String? reason,
  });
}

class InquiryReviewApi implements InquiryReviewGateway {
  final FirebaseFunctions functions;
  InquiryReviewApi({FirebaseFunctions? functions})
    : functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1');
  @override
  Future<InquiryJson> review(
    String businessId,
    String inquiryId,
    String action, {
    String? customerId,
    String? reason,
  }) async {
    final result = await functions
        .httpsCallable('reviewPublicInquiry')
        .call<dynamic>({
          'businessId': businessId,
          'inquiryId': inquiryId,
          'action': action,
          'customerId': ?customerId,
          'reason': ?reason,
        });
    return Map<String, dynamic>.from(result.data as Map);
  }
}

String inquiryReviewError(Object error) {
  if (error is FirebaseFunctionsException) {
    return switch (error.code) {
      'permission-denied' ||
      'unauthenticated' => 'Owner, manager or sales access is required.',
      'not-found' => error.message ?? 'Record not found.',
      'failed-precondition' ||
      'invalid-argument' => error.message ?? 'This action is not allowed.',
      _ => 'Could not connect. Please try again.',
    };
  }
  return 'Could not connect. Please try again.';
}

/// Parses the visitor's YYYY-MM-DD event day for display.
DateTime? websiteEventDay(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return null;
  return DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
}

int _createdMillis(InquiryJson data) {
  final value = data['createdAt'];
  return value is Timestamp ? value.millisecondsSinceEpoch : 0;
}

Stream<List<SalesRecord>> watchWebsiteInquiries(String status) => sales()
    .collection('publicInquiries')
    .where('status', isEqualTo: status)
    .snapshots()
    .map((s) {
      final list = s.docs.map((d) => SalesRecord(d.id, d.data())).toList();
      list.sort((a, b) => _createdMillis(b.data) - _createdMillis(a.data));
      return list;
    });

/// Live count of unhandled website inquiries for the dashboard badge.
Stream<int> watchNewWebsiteInquiryCount() => sales()
    .collection('publicInquiries')
    .where('status', isEqualTo: 'new')
    .snapshots()
    .map((s) => s.size);

class WebsiteInquiriesPage extends StatelessWidget {
  const WebsiteInquiriesPage({super.key});
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: websiteInquiryStatuses.length,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Website inquiries'),
        bottom: TabBar(
          isScrollable: true,
          tabs: [
            for (final s in websiteInquiryStatuses)
              Tab(text: websiteStatusLabel(s)),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          for (final s in websiteInquiryStatuses) _InquiryList(status: s),
        ],
      ),
    ),
  );
}

class _InquiryList extends StatelessWidget {
  final String status;
  const _InquiryList({required this.status});
  @override
  Widget build(BuildContext context) => StreamBuilder<List<SalesRecord>>(
    stream: watchWebsiteInquiries(status),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: Text('Could not load inquiries: ${snapshot.error}'),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final items = snapshot.data!;
      if (items.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              status == 'new'
                  ? 'No new website inquiries. Share your storefront link to receive requests.'
                  : 'Nothing here yet.',
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: items.length,
        itemBuilder: (ctx, i) {
          final r = items[i];
          return Card(
            child: ListTile(
              leading: const Icon(Icons.language),
              title: Text('${r.str('name')} · ${r.str('eventType')}'),
              subtitle: Text(
                '${r.number('guests')} guests · ${humanDate(websiteEventDay(r.str('eventDate')))}\n'
                '${r.str('phone')} · received ${humanDate(r.date('createdAt'))}',
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  Get.to(() => WebsiteInquiryDetailPage(inquiryId: r.id)),
            ),
          );
        },
      );
    },
  );
}

class WebsiteInquiryDetailPage extends StatefulWidget {
  final String inquiryId;
  final InquiryReviewGateway? gateway;
  const WebsiteInquiryDetailPage({
    super.key,
    required this.inquiryId,
    this.gateway,
  });
  @override
  State<WebsiteInquiryDetailPage> createState() =>
      _WebsiteInquiryDetailPageState();
}

class _WebsiteInquiryDetailPageState extends State<WebsiteInquiryDetailPage> {
  late final InquiryReviewGateway gateway =
      widget.gateway ?? InquiryReviewApi();
  bool busy = false;

  String get businessId => sales().businessId;

  Future<void> run(
    String action, {
    String? customerId,
    String? reason,
    String? success,
  }) async {
    setState(() => busy = true);
    try {
      final result = await gateway.review(
        businessId,
        widget.inquiryId,
        action,
        customerId: customerId,
        reason: reason,
      );
      if (!mounted) return;
      if (action == 'convert') {
        final created = result['customerCreated'] == true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              created
                  ? 'Customer and sales inquiry created.'
                  : 'Sales inquiry created for the existing customer.',
            ),
          ),
        );
      } else if (success != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(inquiryReviewError(e))));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> convert() async {
    // Let the user pick an existing customer, or let the server match by
    // phone / create a new one.
    final customers = await sales().collection('customers').get();
    if (!mounted) return;
    String choice = '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Convert to sales inquiry'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'A customer record and a sales inquiry will be created. '
                  'No quotation, booking or capacity is reserved yet.',
                ),
                gap(),
                DropdownButtonFormField<String>(
                  initialValue: choice,
                  isExpanded: true,
                  decoration: field('Customer'),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Match by phone or create new'),
                    ),
                    for (final d in customers.docs)
                      DropdownMenuItem(
                        value: d.id,
                        child: Text(
                          '${d.data()['name']} · ${d.data()['phone']}',
                        ),
                      ),
                  ],
                  onChanged: (v) => set(() => choice = v ?? ''),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Convert'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await run('convert', customerId: choice.isEmpty ? null : choice);
    }
  }

  Future<void> dismiss() async {
    String reason = 'other';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Dismiss inquiry'),
          content: DropdownButtonFormField<String>(
            initialValue: reason,
            decoration: field('Reason'),
            items: [
              for (final e in dismissReasons.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => set(() => reason = v ?? 'other'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Dismiss'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await run('dismiss', reason: reason, success: 'Inquiry dismissed.');
    }
  }

  Future<void> createQuotation(SalesRecord r) async {
    final salesInquiryId = r.str('salesInquiryId');
    final snapshot = await sales()
        .collection('inquiries')
        .doc(salesInquiryId)
        .get();
    if (!snapshot.exists) {
      errorNotice('The linked sales inquiry was not found.');
      return;
    }
    final inquiry = SalesRecord(snapshot.id, snapshot.data()!);
    Get.to(() => QuoteEditor(prefill: QuotePrefill.fromInquiry(inquiry)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Website inquiry')),
    body: StreamBuilder<DocumentSnapshot<Json>>(
      stream: sales()
          .collection('publicInquiries')
          .doc(widget.inquiryId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Could not load: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.data!.exists) {
          return const Center(child: Text('Inquiry not found.'));
        }
        final r = SalesRecord(snapshot.data!.id, snapshot.data!.data()!);
        return WebsiteInquiryDetails(
          record: r,
          busy: busy || !salesEditor(),
          onAction: (action) => switch (action) {
            'convert' => convert(),
            'contacted' => run('contacted', success: 'Marked as contacted.'),
            'dismiss' => dismiss(),
            'reopen' => run('reopen', success: 'Inquiry reopened.'),
            'quote' => createQuotation(r),
            _ => Future.value(),
          },
        );
      },
    ),
  );
}

/// Stateless details view; separated for widget testing without Firebase.
class WebsiteInquiryDetails extends StatelessWidget {
  final SalesRecord record;
  final bool busy;
  final Future<void> Function(String action) onAction;
  const WebsiteInquiryDetails({
    super.key,
    required this.record,
    required this.busy,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final r = record;
    final status = r.str('status');
    Widget row(IconData icon, String label, String value) => ListTile(
      dense: true,
      leading: Icon(icon),
      title: Text(label),
      subtitle: SelectableText(value.isEmpty ? '—' : value),
    );
    final labels = {
      'convert': ('Convert to customer & sales inquiry', Icons.person_add_alt),
      'contacted': ('Mark as contacted', Icons.call_made),
      'dismiss': ('Dismiss', Icons.block),
      'reopen': ('Reopen', Icons.undo),
    };
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          r.str('name'),
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        gap(6),
        Chip(label: Text(websiteStatusLabel(status))),
        if (status == 'dismissed' && r.str('dismissReason').isNotEmpty)
          Text(
            'Reason: ${dismissReasons[r.str('dismissReason')] ?? r.str('dismissReason')}',
          ),
        Card(
          child: Column(
            children: [
              row(Icons.phone, 'Phone', r.str('phone')),
              row(Icons.email_outlined, 'Email', r.str('email')),
              row(Icons.celebration_outlined, 'Event', r.str('eventType')),
              row(
                Icons.event,
                'Event date',
                humanDate(websiteEventDay(r.str('eventDate'))),
              ),
              row(Icons.groups_outlined, 'Guests', '${r.number('guests')}'),
              if (r.str('packageId').isNotEmpty)
                row(
                  Icons.inventory_2_outlined,
                  'Package id',
                  r.str('packageId'),
                ),
              row(Icons.notes, 'Requirements', r.str('requirements')),
              row(Icons.schedule, 'Received', humanDate(r.date('createdAt'))),
            ],
          ),
        ),
        gap(),
        const Text(
          'Website inquiries are requests only. They do not reserve capacity '
          'or create bookings until you send and confirm a quotation.',
          style: TextStyle(fontStyle: FontStyle.italic),
        ),
        gap(),
        for (final action in websiteInquiryActions(status))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: action == 'convert'
                ? FilledButton.icon(
                    onPressed: busy ? null : () => onAction(action),
                    icon: Icon(labels[action]!.$2),
                    label: Text(labels[action]!.$1),
                  )
                : OutlinedButton.icon(
                    onPressed: busy ? null : () => onAction(action),
                    icon: Icon(labels[action]!.$2),
                    label: Text(labels[action]!.$1),
                  ),
          ),
        if (status == 'converted') ...[
          FilledButton.icon(
            onPressed: busy ? null : () => onAction('quote'),
            icon: const Icon(Icons.request_quote_outlined),
            label: const Text('Create quotation'),
          ),
          gap(6),
          Text(
            r.data['customerCreated'] == true
                ? 'A new customer was created from this inquiry.'
                : 'Linked to an existing customer.',
          ),
        ],
      ],
    );
  }
}
