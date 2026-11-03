import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import '../../features/auth/data/firebase_auth_repository.dart';
import '../../features/auth/domain/auth_repository.dart';
import '../../features/business/data/business_repository.dart';
import 'session_controller.dart';

class AppBinding extends Bindings {
  @override
  void dependencies() {
    Get.put<AuthRepository>(
      FirebaseAuthRepository(FirebaseAuth.instance),
      permanent: true,
    );
    Get.put<BusinessRepository>(
      FirestoreBusinessRepository(FirebaseFirestore.instance),
      permanent: true,
    );
    Get.put<SessionController>(
      SessionController(
        Get.find<AuthRepository>(),
        Get.find<BusinessRepository>(),
      ),
      permanent: true,
    );
  }
}
