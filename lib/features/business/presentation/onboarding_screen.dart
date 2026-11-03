import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/app/session_controller.dart';
import '../data/business_repository.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final keyForm = GlobalKey<FormState>();
  final name = TextEditingController();
  final city = TextEditingController(text: 'Karachi');
  final phone = TextEditingController();
  bool saving = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    city.dispose();
    phone.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!keyForm.currentState!.validate() || saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final session = Get.find<SessionController>();
      await Get.find<BusinessRepository>().createBusiness(
        uid: session.auth.currentUser!.uid,
        name: name.text,
        city: city.text,
        phone: phone.text,
      );
      await session.reloadSession();
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Business setup failed. Check internet connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Set up your business'),
      actions: [
        TextButton(
          onPressed: () => Get.find<SessionController>().auth.signOut(),
          child: const Text('Sign out'),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Form(
              key: keyForm,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Your catering business',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Create your private business workspace. Only authorized staff will be able to access it.',
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Business name',
                    ),
                    validator: (v) => (v ?? '').trim().length < 3
                        ? 'Enter business name'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: city,
                    decoration: const InputDecoration(labelText: 'City'),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'Enter city' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Business phone',
                    ),
                    validator: (v) => (v ?? '').trim().length < 7
                        ? 'Enter phone number'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: saving ? null : submit,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(saving ? 'Creating...' : 'Create business'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
