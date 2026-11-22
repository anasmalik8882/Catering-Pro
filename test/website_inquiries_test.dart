import 'package:catering_pro/features/inquiries/website_inquiries.dart';
import 'package:catering_pro/features/sales/domain/sales_models.dart';
import 'package:catering_pro/features/sales/presentation/sales_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SalesRecord record(String status, {Map<String, dynamic> extra = const {}}) =>
    SalesRecord('web-1', {
      'name': 'Ayesha Khan',
      'phone': '03001112222',
      'email': 'visitor@example.invalid',
      'eventType': 'Walima',
      'eventDate': '2027-04-10',
      'guests': 250,
      'packageId': 'feast',
      'requirements': 'Live BBQ station',
      'status': status,
      ...extra,
    });

Future<List<String>> pump(WidgetTester tester, SalesRecord r) async {
  final tapped = <String>[];
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: WebsiteInquiryDetails(
          record: r,
          busy: false,
          onAction: (a) async => tapped.add(a),
        ),
      ),
    ),
  );
  return tapped;
}

void main() {
  test('client action menu mirrors backend transitions', () {
    expect(websiteInquiryActions('new'), ['convert', 'contacted', 'dismiss']);
    expect(websiteInquiryActions('contacted'), ['convert', 'dismiss']);
    expect(websiteInquiryActions('dismissed'), ['reopen']);
    expect(websiteInquiryActions('converted'), isEmpty);
    expect(websiteInquiryActions('anything-else'), isEmpty);
  });

  test('visitor event days parse without timezone drift', () {
    expect(websiteEventDay('2027-04-10'), DateTime(2027, 4, 10));
    expect(websiteEventDay('10/04/2027'), isNull);
    expect(websiteEventDay(''), isNull);
  });

  test('free-text website event types stay selectable in quotations', () {
    expect(eventTypeOptions('Wedding'), quoteEventTypes);
    expect(eventTypeOptions('Engagement').first, 'Engagement');
    expect(eventTypeOptions(''), quoteEventTypes);
  });

  test('quotation prefill carries sales inquiry details', () {
    final p = QuotePrefill.fromInquiry(
      const SalesRecord('inq-1', {
        'customerId': 'cust-1',
        'eventType': 'Walima',
        'guests': 250,
      }),
    );
    expect(p.inquiryId, 'inq-1');
    expect(p.customerId, 'cust-1');
    expect(p.guests, 250);
    expect(p.eventDate, isNull);
  });

  testWidgets('new inquiry shows contact details and review actions', (
    tester,
  ) async {
    final tapped = await pump(tester, record('new'));
    expect(find.text('Ayesha Khan'), findsOneWidget);
    expect(find.text('03001112222'), findsOneWidget);
    expect(find.text('Live BBQ station'), findsOneWidget);
    expect(find.text('Create quotation'), findsNothing);
    await tester.tap(find.text('Convert to customer & sales inquiry'));
    await tester.tap(find.text('Mark as contacted'));
    await tester.tap(find.text('Dismiss'));
    expect(tapped, ['convert', 'contacted', 'dismiss']);
  });

  testWidgets('converted inquiry offers quotation creation only', (
    tester,
  ) async {
    final tapped = await pump(
      tester,
      record('converted', extra: {'customerCreated': true}),
    );
    expect(find.text('Dismiss'), findsNothing);
    expect(find.textContaining('new customer was created'), findsOneWidget);
    await tester.tap(find.text('Create quotation'));
    expect(tapped, ['quote']);
  });

  testWidgets('dismissed inquiry shows reason and can be reopened', (
    tester,
  ) async {
    final tapped = await pump(
      tester,
      record('dismissed', extra: {'dismissReason': 'spam'}),
    );
    expect(find.text('Reason: Spam'), findsOneWidget);
    await tester.tap(find.text('Reopen'));
    expect(tapped, ['reopen']);
  });
}
