import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';

import 'core/app/app.dart';
import 'core/app/app_binding.dart';
import 'firebase_options.dart' as production;
import 'firebase_options_staging.dart' as staging;

const _environment = String.fromEnvironment('APP_ENV', defaultValue: 'production');
const _nativeApplicationChannel = MethodChannel('caterer_pro/environment');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Do not initialize Firebase until the selected flavor and project agree.
  if (_environment != 'production' && _environment != 'staging') {
    throw StateError('Invalid APP_ENV: $_environment');
  }

  final expectedProject = _environment == 'staging'
      ? 'caterer-pro-staging'
      : 'catering-pro-b001d';
  final options = _environment == 'staging'
      ? staging.DefaultFirebaseOptions.currentPlatform
      : production.DefaultFirebaseOptions.currentPlatform;
  if (options.projectId != expectedProject) {
    throw StateError('Firebase options do not match APP_ENV=$_environment');
  }

  if (defaultTargetPlatform == TargetPlatform.android) {
    final applicationId =
        await _nativeApplicationChannel.invokeMethod<String>('applicationId');
    final expectedApplicationId = _environment == 'staging'
        ? 'com.example.catering_pro.staging'
        : 'com.example.catering_pro';
    if (applicationId != expectedApplicationId) {
      throw StateError('Android flavor mismatch: expected $expectedApplicationId, '
          'got $applicationId. Refusing Firebase initialization.');
    }
  } else if (_environment == 'staging') {
    throw UnsupportedError('Staging environment is currently Android-only.');
  }

  final app = await Firebase.initializeApp(options: options);
  if (app.options.projectId != expectedProject ||
      app.options.appId != options.appId) {
    throw StateError('Firebase default app mismatch. Expected $expectedProject; '
        'got ${app.options.projectId}. Refusing app startup.');
  }

  AppBinding().dependencies();
  runApp(const CatererProApp());
}
