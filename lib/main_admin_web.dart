// Milestone 12: SaaS super-admin portal entry point (Flutter Web only).
// Build: flutter build web --target lib/main_admin_web.dart --output build/admin_web ...
// See docs/milestone12.md.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart' as production;
import 'features/admin/admin_api.dart';
import 'features/admin/admin_portal.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const environment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'emulator',
  );
  try {
    if (!['emulator', 'staging', 'production'].contains(environment)) {
      throw StateError('APP_ENV must be emulator, staging or production.');
    }
    const stagingKey = String.fromEnvironment('STAGING_WEB_API_KEY');
    const stagingApp = String.fromEnvironment('STAGING_WEB_APP_ID');
    const stagingSender = String.fromEnvironment('STAGING_WEB_SENDER_ID');
    if (environment == 'staging' &&
        (stagingKey.isEmpty || stagingApp.isEmpty || stagingSender.isEmpty)) {
      throw StateError('Staging Web configuration is required.');
    }
    final options = environment == 'production'
        ? production.DefaultFirebaseOptions.web
        : FirebaseOptions(
            apiKey: environment == 'emulator' ? 'fake-api-key' : stagingKey,
            appId: environment == 'emulator'
                ? '1:123456789:web:emulator'
                : stagingApp,
            messagingSenderId: environment == 'emulator'
                ? '123456789'
                : stagingSender,
            projectId: environment == 'emulator'
                ? 'demo-caterer-stage'
                : 'caterer-pro-staging',
            authDomain: environment == 'emulator'
                ? 'localhost'
                : 'caterer-pro-staging.firebaseapp.com',
          );
    await Firebase.initializeApp(options: options);
    final auth = FirebaseAuth.instance;
    final functions = FirebaseFunctions.instanceFor(region: 'asia-south1');
    if (environment == 'emulator') {
      const host = String.fromEnvironment(
        'EMULATOR_HOST',
        defaultValue: '127.0.0.1',
      );
      await auth.useAuthEmulator(host, 9099);
      functions.useFunctionsEmulator(host, 5001);
    }
    runApp(AdminPortalApp(auth: auth, gateway: AdminApi(functions)));
  } catch (error) {
    debugPrint('Admin portal initialization failed: $error');
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Admin portal is unavailable.')),
        ),
      ),
    );
  }
}
