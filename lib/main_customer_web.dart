import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'firebase_options.dart' as production;
import 'features/storefront/customer_site.dart';
import 'features/storefront/storefront_api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
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
      throw StateError(
        'Staging Web configuration is required. See docs/milestone10.md.',
      );
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
    final functions = FirebaseFunctions.instanceFor(region: 'asia-south1');
    if (environment == 'emulator') {
      const host = String.fromEnvironment(
        'EMULATOR_HOST',
        defaultValue: '127.0.0.1',
      );
      functions.useFunctionsEmulator(host, 5001);
    }
    runApp(CustomerSite(api: StorefrontApi(functions: functions)));
  } catch (error) {
    debugPrint('Customer website initialization failed: $error');
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'This website is temporarily unavailable. Refresh the page to try again.',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
