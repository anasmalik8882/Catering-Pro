import 'package:cloud_functions/cloud_functions.dart';

typedef AdminJson = Map<String, dynamic>;

AdminJson _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<AdminJson> _list(Object? value) =>
    value is List ? value.map(_map).toList() : <AdminJson>[];

class BusinessSummary {
  final String id;
  final String name;
  final String city;
  final String phone;
  final String status;
  final String ownerEmail;
  final String statusReason;
  final DateTime? createdAt;
  const BusinessSummary({
    required this.id,
    required this.name,
    required this.city,
    required this.phone,
    required this.status,
    required this.ownerEmail,
    required this.statusReason,
    this.createdAt,
  });
  factory BusinessSummary.fromJson(AdminJson j) => BusinessSummary(
    id: '${j['id'] ?? ''}',
    name: '${j['name'] ?? ''}',
    city: '${j['city'] ?? ''}',
    phone: '${j['phone'] ?? ''}',
    status: '${j['status'] ?? ''}',
    ownerEmail: '${j['ownerEmail'] ?? ''}',
    statusReason: '${j['statusReason'] ?? ''}',
    createdAt: j['createdAt'] is num
        ? DateTime.fromMillisecondsSinceEpoch((j['createdAt'] as num).toInt())
        : null,
  );
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [
      id,
      name,
      city,
      phone,
      ownerEmail,
    ].any((v) => v.toLowerCase().contains(q));
  }
}

class BusinessPage {
  final List<BusinessSummary> businesses;
  final String? next;
  const BusinessPage(this.businesses, this.next);
}

class BusinessDetail {
  final BusinessSummary business;
  final List<AdminJson> members;
  final Map<String, int> usage;
  final AdminJson? storefront;
  final AdminJson? subscription;
  const BusinessDetail({
    required this.business,
    required this.members,
    required this.usage,
    this.storefront,
    this.subscription,
  });
  factory BusinessDetail.fromJson(AdminJson j) => BusinessDetail(
    business: BusinessSummary.fromJson(_map(j['business'])),
    members: _list(j['members']),
    usage: _map(
      j['usage'],
    ).map((k, v) => MapEntry(k, v is num ? v.toInt() : 0)),
    storefront: j['storefront'] == null ? null : _map(j['storefront']),
    subscription: j['subscription'] == null ? null : _map(j['subscription']),
  );
}

abstract class AdminGateway {
  Future<BusinessPage> listBusinesses({String status = '', String? after});
  Future<BusinessDetail> business(String id);
  Future<void> setStatus(String id, String status, String reason);
  Future<List<AdminJson>> auditLog({String? businessId});
}

class AdminApi implements AdminGateway {
  final FirebaseFunctions functions;
  AdminApi(this.functions);
  Future<AdminJson> _call(String name, AdminJson data) async =>
      _map((await functions.httpsCallable(name).call<dynamic>(data)).data);

  @override
  Future<BusinessPage> listBusinesses({
    String status = '',
    String? after,
  }) async {
    final r = await _call('adminListBusinesses', {
      'limit': 50,
      'status': status,
      'after': ?after,
    });
    return BusinessPage(
      _list(r['businesses']).map(BusinessSummary.fromJson).toList(),
      r['next'] as String?,
    );
  }

  @override
  Future<BusinessDetail> business(String id) async => BusinessDetail.fromJson(
    await _call('adminGetBusiness', {'businessId': id}),
  );

  @override
  Future<void> setStatus(String id, String status, String reason) => _call(
    'adminSetBusinessStatus',
    {'businessId': id, 'status': status, 'reason': reason},
  );

  @override
  Future<List<AdminJson>> auditLog({String? businessId}) async => _list(
    (await _call('adminListAuditLog', {
      'limit': 100,
      'businessId': ?businessId,
    }))['entries'],
  );
}

String adminError(Object error) {
  if (error is FirebaseFunctionsException) {
    return switch (error.code) {
      'permission-denied' => 'Platform administrator access is required.',
      'unauthenticated' => 'Please sign in again.',
      'not-found' => error.message ?? 'Not found.',
      'invalid-argument' ||
      'failed-precondition' => error.message ?? 'Request rejected.',
      _ => 'Could not connect. Please try again.',
    };
  }
  return 'Something went wrong: $error';
}
