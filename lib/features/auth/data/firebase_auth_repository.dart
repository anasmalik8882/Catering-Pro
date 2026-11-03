import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../domain/auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  final FirebaseAuth auth;
  FirebaseAuthRepository(this.auth);
  @override
  Stream<User?> authChanges() => auth.authStateChanges();
  @override
  User? get currentUser => auth.currentUser;
  @override
  Future<void> signIn(String email, String password) async {
    await auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  @override
  Future<void> signUp(String name, String email, String password) async {
    final credentials = await auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await credentials.user!.updateDisplayName(name.trim());
  }

  @override
  Future<void> resetPassword(String email) async {
    await auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void>? _googleInitialization;

  @override
  Future<void> signInWithGoogle() async {
    if (kIsWeb) {
      await auth.signInWithPopup(GoogleAuthProvider());
      return;
    }
    _googleInitialization ??= GoogleSignIn.instance.initialize();
    await _googleInitialization;
    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw UnsupportedError('Google sign-in is unavailable on this platform.');
    }
    final account = await GoogleSignIn.instance.authenticate();
    final tokens = account.authentication;
    final credential = GoogleAuthProvider.credential(idToken: tokens.idToken);
    await auth.signInWithCredential(credential);
  }

  @override
  Future<void> signOut() async {
    await auth.signOut();
    if (!kIsWeb && _googleInitialization != null) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {
        // Firebase session is already signed out; don't restore it on plugin errors.
      }
    }
  }
}
