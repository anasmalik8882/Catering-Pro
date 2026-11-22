import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:catering_pro/features/storefront/customer_site.dart';
import 'package:catering_pro/features/storefront/storefront_api.dart';

class FakeStorefront implements StorefrontGateway {
  bool fail = false;
  StoreJson? submitted;
  final StoreJson data = {
    'displayName': 'Karachi Catering',
    'description': 'Fresh food for memorable occasions.',
    'services': 'Weddings and corporate events',
    'menus': <StoreJson>[
      {
        'id': 'dish',
        'name': 'Biryani',
        'description': 'Aromatic rice',
        'unit': 'plate',
      },
    ],
    'packages': <StoreJson>[
      {
        'id': 'package',
        'name': 'Wedding feast',
        'description': 'A complete meal',
        'minimumGuests': 50,
        'pricingMode': 'per_head',
        'pricePaisa': 150000,
      },
    ],
  };
  @override
  Future<StoreJson> load(String slug) async {
    if (fail) {
      throw FirebaseFunctionsException(
        code: 'not-found',
        message: 'Unavailable',
      );
    }
    return data;
  }

  @override
  Future<String> submit(StoreJson data) async {
    submitted = data;
    return 'received-123';
  }
}

void main() {
  test('only well formed storefront paths are accepted', () {
    expect(storefrontSlug('/b/karachi-catering'), 'karachi-catering');
    expect(storefrontSlug('/b/abc/'), 'abc');
    for (final path in [
      '/',
      '/admin',
      '/b/ab',
      '/b/Upper',
      '/b/a--b',
      '/b/a%2fb',
      '/b/abc/private',
    ]) {
      expect(storefrontSlug(path), isNull);
    }
  });
  for (final size in [const Size(390, 844), const Size(1440, 1000)]) {
    testWidgets('storefront renders without overflow at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        CustomerSite(api: FakeStorefront(), path: '/b/karachi-catering'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Karachi Catering'), findsWidgets);
      expect(find.text('Wedding feast'), findsWidgets);
      expect(find.text('Pricing on request'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Get a quote'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'missing and malformed storefront links have a safe public page',
    (tester) async {
      final api = FakeStorefront()..fail = true;
      await tester.pumpWidget(CustomerSite(api: api, path: '/b/missing'));
      await tester.pumpAndSettle();
      expect(find.text('This storefront is unavailable.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      await tester.pumpWidget(
        CustomerSite(key: UniqueKey(), api: api, path: '/private'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Storefront not found'), findsOneWidget);
    },
  );
  testWidgets(
    'inquiry validates and displays success only after gateway returns a receipt',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = FakeStorefront();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: InquiryForm(
                api: api,
                slug: 'karachi-catering',
                packages: const [],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Request a quotation'));
      await tester.pumpAndSettle();
      expect(api.submitted, isNull);
      expect(find.text('Choose an event date.'), findsOneWidget);
      for (final entry in {
        'Your name': 'Test Visitor',
        'Phone number': '03001234567',
        'Event type': 'Wedding',
        'Expected guests': '100',
      }.entries) {
        await tester.enterText(
          find.widgetWithText(TextFormField, entry.key),
          entry.value,
        );
      }
      await tester.tap(find.text('Choose event date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Request a quotation'));
      await tester.pumpAndSettle();
      expect(api.submitted?['slug'], 'karachi-catering');
      expect(api.submitted?['guests'], 100);
      expect(api.submitted?['requestId'], isNotEmpty);
      expect(
        find.text('Thank you! Your inquiry has been received.'),
        findsOneWidget,
      );
      expect(find.text('Reference: received-123'), findsOneWidget);
    },
  );
}
