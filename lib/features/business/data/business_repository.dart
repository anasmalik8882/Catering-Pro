import 'package:cloud_firestore/cloud_firestore.dart';
import '../domain/business.dart';

abstract class BusinessRepository {
  Future<void> createBusiness({
    required String uid,
    required String name,
    required String city,
    required String phone,
  });
  Future<({Business business, BusinessMembership member})?> findCurrentBusiness(
    String uid,
  );
}

class FirestoreBusinessRepository implements BusinessRepository {
  final FirebaseFirestore db;
  FirestoreBusinessRepository(this.db);

  @override
  Future<void> createBusiness({
    required String uid,
    required String name,
    required String city,
    required String phone,
  }) async {
    // A stable ID makes retries idempotent for first-owner onboarding.
    final business = db.collection('businesses').doc('owner_$uid');
    final batch = db.batch();
    batch.set(business, {
      'name': name.trim(),
      'city': city.trim(),
      'phone': phone.trim(),
      'ownerId': uid,
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(business.collection('members').doc(uid), {
      'uid': uid,
      'role': 'owner',
      'active': true,
      'joinedAt': FieldValue.serverTimestamp(),
    });
    batch.set(db.collection('users').doc(uid), {
      'activeBusinessId': business.id,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
  }

  @override
  Future<({Business business, BusinessMembership member})?> findCurrentBusiness(
    String uid,
  ) async {
    final user = await db.collection('users').doc(uid).get();
    final businessId = user.data()?['activeBusinessId'] as String?;
    if (businessId == null || businessId.isEmpty) return null;
    final memberDoc = await db
        .collection('businesses')
        .doc(businessId)
        .collection('members')
        .doc(uid)
        .get(const GetOptions(source: Source.server));
    if (!memberDoc.exists) return null;
    final member = memberDoc.data()!;
    if (member['active'] != true) return null;
    final businessDoc = await db
        .collection('businesses')
        .doc(businessId)
        .get(const GetOptions(source: Source.server));
    if (!businessDoc.exists) return null;
    final data = businessDoc.data()!;
    if (data['status'] != 'active') return null;
    return (
      business: Business(
        id: businessId,
        name: (data['name'] ?? '') as String,
        ownerId: (data['ownerId'] ?? '') as String,
        city: (data['city'] ?? '') as String,
        phone: (data['phone'] ?? '') as String,
        status: (data['status'] ?? '') as String,
      ),
      member: BusinessMembership(
        uid: uid,
        businessId: businessId,
        role: BusinessRoleLabel.fromWire((member['role'] ?? '') as String),
        active: true,
      ),
    );
  }
}
