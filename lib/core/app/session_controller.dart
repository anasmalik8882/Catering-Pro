import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import '../../features/auth/domain/auth_repository.dart';
import '../../features/business/data/business_repository.dart';
import '../../features/business/domain/business.dart';

enum SessionStage { loading, signedOut, onboarding, ready, error }

class SessionController extends GetxController {
  final AuthRepository auth;
  final BusinessRepository businesses;
  SessionController(this.auth, this.businesses);

  final stage = SessionStage.loading.obs;
  final business = Rxn<Business>();
  final membership = Rxn<BusinessMembership>();
  final errorMessage = ''.obs;
  StreamSubscription<User?>? _subscription;
  int _generation = 0;

  @override
  void onInit() {
    super.onInit();
    _subscription = auth.authChanges().listen((user) => _resolve(user));
  }

  Future<void> reloadSession() => _resolve(auth.currentUser);

  Future<void> _resolve(User? user) async {
    final version = ++_generation;
    business.value = null;
    membership.value = null;
    errorMessage.value = '';
    if (user == null) {
      stage.value = SessionStage.signedOut;
      return;
    }
    stage.value = SessionStage.loading;
    try {
      final result = await businesses.findCurrentBusiness(user.uid);
      if (version != _generation) return;
      if (result == null) {
        stage.value = SessionStage.onboarding;
        return;
      }
      business.value = result.business;
      membership.value = result.member;
      stage.value = SessionStage.ready;
    } catch (_) {
      if (version != _generation) return;
      errorMessage.value =
          'Could not verify your business access. Check your connection and retry.';
      stage.value = SessionStage.error;
    }
  }

  @override
  void onClose() {
    ++_generation;
    _subscription?.cancel();
    super.onClose();
  }
}
