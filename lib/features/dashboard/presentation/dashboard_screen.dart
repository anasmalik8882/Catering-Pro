import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/app/session_controller.dart';
import '../../business/domain/business.dart';
import '../../sales/presentation/sales_screens.dart';
import '../../operations/presentation/operations_screens.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final session = Get.find<SessionController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Caterer Pro'),
        actions: [
          IconButton(
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: 'Caterer Pro',
              applicationVersion: 'Phase 1',
            ),
            icon: const Icon(Icons.info_outline),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => session.auth.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Welcome to ${session.business.value?.name ?? 'your business'}',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              '${session.business.value?.city ?? ''}  •  ${session.membership.value?.role.displayName ?? ''}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 22),
            const Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _Metric(label: 'Upcoming events', icon: Icons.event_available),
                _Metric(
                  label: 'New inquiries',
                  icon: Icons.mark_email_unread_outlined,
                ),
                _Metric(
                  label: 'Pending payments',
                  icon: Icons.payments_outlined,
                ),
                _Metric(label: 'Monthly sales', icon: Icons.trending_up),
              ],
            ),
            const SizedBox(height: 22),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bookings, payments and operations',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Manage quotations from More, convert accepted quotations into bookings, and track events, payments, kitchen tasks and expenses.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            label: 'Customers',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            label: 'Bookings',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            label: 'Finance',
          ),
          NavigationDestination(icon: Icon(Icons.menu), label: 'More'),
        ],
        onDestinationSelected: (index) {
          if (index == 1) {
            Get.to(() => const CustomersPage());
          } else if (index == 2) {
            Get.to(() => const BookingsPage());
          } else if (index == 3) {
            Get.to(() => const FinanceOverviewPage());
          } else if (index == 4) {
            Get.to(() => const SalesHome());
          } else if (index != 0) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('This module is scheduled for a later phase.'),
              ),
            );
          }
        },
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final IconData icon;
  const _Metric({required this.label, required this.icon});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 160,
    height: 112,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const Spacer(),
            Text('—', style: Theme.of(context).textTheme.headlineSmall),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ),
  );
}
