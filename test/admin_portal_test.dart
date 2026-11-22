import 'package:catering_pro/core/app/app.dart';
import 'package:catering_pro/features/admin/admin_api.dart';
import 'package:catering_pro/features/admin/admin_portal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BusinessSummary biz(String id, String name, String status) =>
    BusinessSummary.fromJson({
      'id': id,
      'name': name,
      'city': 'Karachi',
      'phone': '0300',
      'status': status,
      'ownerEmail': '$id@example.invalid',
      'statusReason': status == 'suspended' ? 'Unpaid' : '',
    });

class FakeAdmin implements AdminGateway {
  final calls = <String>[];
  @override
  Future<BusinessPage> listBusinesses({
    String status = '',
    String? after,
  }) async {
    calls.add('list:$status');
    final all = [
      biz('a1', 'Alpha Caterers', 'active'),
      biz('b2', 'Beta Foods', 'suspended'),
    ];
    return BusinessPage(
      all.where((b) => status.isEmpty || b.status == status).toList(),
      null,
    );
  }

  @override
  Future<BusinessDetail> business(String id) async => BusinessDetail.fromJson({
    'business': {'id': id, 'name': 'Alpha Caterers', 'status': 'active'},
    'members': [],
    'usage': {'customers': 3},
  });
  @override
  Future<void> setStatus(String id, String status, String reason) async =>
      calls.add('status:$id:$status:$reason');
  @override
  Future<List<AdminJson>> auditLog({String? businessId}) async => [];
}

void main() {
  test('business search matches name, email and id case-insensitively', () {
    final b = biz('a1', 'Alpha Caterers', 'active');
    expect(b.matches('alpha'), isTrue);
    expect(b.matches('A1@EXAMPLE'), isTrue);
    expect(b.matches('zzz'), isFalse);
    expect(b.matches(''), isTrue);
  });

  testWidgets('business list filters by status and search text', (
    tester,
  ) async {
    final fake = FakeAdmin();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BusinessesTab(gateway: fake)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Alpha Caterers'), findsOneWidget);
    expect(find.text('Beta Foods'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'beta');
    await tester.pump();
    expect(find.text('Alpha Caterers'), findsNothing);
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Suspended'));
    await tester.pumpAndSettle();
    expect(fake.calls.last, 'list:suspended');
    expect(find.text('Alpha Caterers'), findsNothing);
  });

  testWidgets('detail view shows usage and the correct status action', (
    tester,
  ) async {
    BusinessSummary? tapped;
    final detail = BusinessDetail.fromJson({
      'business': {
        'id': 'b2',
        'name': 'Beta Foods',
        'status': 'suspended',
        'statusReason': 'Unpaid',
      },
      'members': [
        {
          'uid': 'u1',
          'email': 'owner@example.invalid',
          'role': 'owner',
          'active': true,
        },
      ],
      'usage': {'customers': 7, 'bookings': 2},
      'storefront': {'slug': 'beta-foods', 'published': false},
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BusinessDetailView(
            detail: detail,
            busy: false,
            onChangeStatus: (b) => tapped = b,
          ),
        ),
      ),
    );
    expect(find.text('Customers: 7'), findsOneWidget);
    expect(find.text('Suspension reason: Unpaid'), findsOneWidget);
    expect(find.text('/b/beta-foods · unpublished'), findsOneWidget);
    expect(find.text('owner@example.invalid'), findsOneWidget);
    expect(find.text('Suspend business'), findsNothing);
    await tester.tap(find.text('Reactivate business'));
    expect(tapped?.id, 'b2');
  });

  testWidgets('suspended business app screen offers retry and sign out', (
    tester,
  ) async {
    var retried = 0, signedOut = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SuspendedScreen(
          message: 'Your business account has been suspended: Unpaid',
          onRetry: () => retried++,
          onSignOut: () => signedOut++,
        ),
      ),
    );
    expect(find.text('Account suspended'), findsOneWidget);
    await tester.tap(find.text('Check again'));
    await tester.tap(find.text('Sign out'));
    expect([retried, signedOut], [1, 1]);
  });
}
