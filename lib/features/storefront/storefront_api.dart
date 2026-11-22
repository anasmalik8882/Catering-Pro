import 'package:cloud_functions/cloud_functions.dart';

typedef StoreJson = Map<String, dynamic>;

String? storefrontSlug(String path) {
  final match = RegExp(r'^/b/([a-z0-9]+(?:-[a-z0-9]+)*)/?$').firstMatch(path);
  final slug = match?.group(1);
  return slug != null && slug.length >= 3 && slug.length <= 60 ? slug : null;
}

abstract class StorefrontGateway {
  Future<StoreJson> load(String slug);
  Future<String> submit(StoreJson data);
}

class StorefrontApi implements StorefrontGateway {
  final FirebaseFunctions functions;
  StorefrontApi({FirebaseFunctions? functions})
    : functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1');
  Future<StoreJson> call(String name, StoreJson data) async =>
      Map<String, dynamic>.from(
        (await functions.httpsCallable(name).call<dynamic>(data)).data as Map,
      );
  @override
  Future<StoreJson> load(String slug) =>
      call('getPublicStorefront', {'slug': slug});
  @override
  Future<String> submit(StoreJson data) async =>
      '${(await call('submitStorefrontInquiry', data))['inquiryId']}';
  Future<StoreJson?> settings(String bid) async {
    final result = await call('getStorefrontSettings', {'businessId': bid});
    return result['config'] == null
        ? null
        : Map<String, dynamic>.from(result['config'] as Map);
  }

  Future<void> save(String bid, StoreJson config) async {
    await call('saveStorefront', {'businessId': bid, 'config': config});
  }
}

String storefrontError(Object error) {
  if (error is FirebaseFunctionsException) {
    return switch (error.code) {
      'not-found' => 'This storefront is unavailable.',
      'resource-exhausted' => 'Too many requests. Please try again later.',
      'already-exists' =>
        'That slug or submission identifier is already in use.',
      'permission-denied' ||
      'unauthenticated' => 'Business owner access is required.',
      'invalid-argument' ||
      'failed-precondition' => error.message ?? 'Please check your details.',
      _ => 'Could not connect. Please try again.',
    };
  }
  return 'Could not connect. Please try again.';
}
