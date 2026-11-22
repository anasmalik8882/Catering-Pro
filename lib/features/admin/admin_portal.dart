// Milestone 12: SaaS super-admin portal (Flutter Web, lib/main_admin_web.dart).
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'admin_api.dart';

String adminDate(DateTime? d) =>
    d == null ? '—' : DateFormat('dd MMM yyyy, HH:mm').format(d);

class AdminPortalApp extends StatelessWidget {
  final FirebaseAuth auth;
  final AdminGateway gateway;
  const AdminPortalApp({super.key, required this.auth, required this.gateway});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Caterer Pro Admin',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    home: StreamBuilder<User?>(
      stream: auth.idTokenChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snapshot.data;
        if (user == null) return AdminSignIn(auth: auth);
        return FutureBuilder<IdTokenResult>(
          key: ValueKey(user.uid),
          future: user.getIdTokenResult(true),
          builder: (context, token) {
            if (!token.hasData && !token.hasError) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (token.data?.claims?['platformAdmin'] != true) {
              return AdminNotAuthorized(
                email: user.email ?? '',
                onSignOut: auth.signOut,
              );
            }
            return AdminHome(
              gateway: gateway,
              email: user.email ?? '',
              onSignOut: auth.signOut,
            );
          },
        );
      },
    ),
  );
}

class AdminSignIn extends StatefulWidget {
  final FirebaseAuth auth;
  const AdminSignIn({super.key, required this.auth});
  @override
  State<AdminSignIn> createState() => _AdminSignInState();
}

class _AdminSignInState extends State<AdminSignIn> {
  final email = TextEditingController();
  final password = TextEditingController();
  String error = '';
  bool busy = false;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> attempt(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      setState(() => error = e.message ?? 'Sign-in failed.');
    } catch (_) {
      setState(() => error = 'Sign-in failed.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Caterer Pro Admin',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: email,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () => attempt(
                          () => widget.auth.signInWithEmailAndPassword(
                            email: email.text.trim(),
                            password: password.text,
                          ),
                        ),
                  child: const Text('Sign in'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => attempt(
                          () =>
                              widget.auth.signInWithPopup(GoogleAuthProvider()),
                        ),
                  icon: const Icon(Icons.login),
                  label: const Text('Sign in with Google'),
                ),
                if (error.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class AdminNotAuthorized extends StatelessWidget {
  final String email;
  final Future<void> Function() onSignOut;
  const AdminNotAuthorized({
    super.key,
    required this.email,
    required this.onSignOut,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline, size: 48),
          const SizedBox(height: 12),
          Text('$email is not a platform administrator.'),
          const SizedBox(height: 12),
          FilledButton(onPressed: onSignOut, child: const Text('Sign out')),
        ],
      ),
    ),
  );
}

class AdminHome extends StatelessWidget {
  final AdminGateway gateway;
  final String email;
  final Future<void> Function() onSignOut;
  const AdminHome({
    super.key,
    required this.gateway,
    required this.email,
    required this.onSignOut,
  });
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Caterer Pro Admin'),
        actions: [
          Center(child: Text(email)),
          IconButton(
            tooltip: 'Sign out',
            onPressed: onSignOut,
            icon: const Icon(Icons.logout),
          ),
        ],
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Businesses'),
            Tab(text: 'Audit log'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          BusinessesTab(gateway: gateway),
          AuditLogView(gateway: gateway),
        ],
      ),
    ),
  );
}

class BusinessesTab extends StatefulWidget {
  final AdminGateway gateway;
  const BusinessesTab({super.key, required this.gateway});
  @override
  State<BusinessesTab> createState() => _BusinessesTabState();
}

class _BusinessesTabState extends State<BusinessesTab> {
  String status = '';
  String query = '';
  final items = <BusinessSummary>[];
  String? next;
  bool loading = false;
  String error = '';

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    items.clear();
    next = null;
    await loadMore();
  }

  Future<void> loadMore() async {
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final page = await widget.gateway.listBusinesses(
        status: status,
        after: next,
      );
      items.addAll(page.businesses);
      next = page.next;
    } catch (e) {
      error = adminError(e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = items.where((b) => b.matches(query)).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: '', label: Text('All')),
                  ButtonSegment(value: 'active', label: Text('Active')),
                  ButtonSegment(value: 'suspended', label: Text('Suspended')),
                ],
                selected: {status},
                onSelectionChanged: (v) {
                  status = v.first;
                  reload();
                },
              ),
              SizedBox(
                width: 320,
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search name, city, phone, email or id',
                  ),
                  onChanged: (v) => setState(() => query = v),
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: loading ? null : reload,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        if (error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final b in visible)
                Card(
                  child: ListTile(
                    leading: Icon(
                      b.status == 'active'
                          ? Icons.storefront
                          : Icons.pause_circle_outline,
                      color: b.status == 'active'
                          ? null
                          : Theme.of(context).colorScheme.error,
                    ),
                    title: Text(b.name.isEmpty ? b.id : b.name),
                    subtitle: Text(
                      '${b.city} · ${b.ownerEmail.isEmpty ? 'owner unknown' : b.ownerEmail} · ${b.status}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => BusinessDetailPage(
                            gateway: widget.gateway,
                            businessId: b.id,
                          ),
                        ),
                      );
                      reload();
                    },
                  ),
                ),
              if (!loading && visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('No businesses found.')),
                ),
              if (loading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (!loading && next != null)
                Center(
                  child: TextButton(
                    onPressed: loadMore,
                    child: const Text('Load more'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class BusinessDetailPage extends StatefulWidget {
  final AdminGateway gateway;
  final String businessId;
  const BusinessDetailPage({
    super.key,
    required this.gateway,
    required this.businessId,
  });
  @override
  State<BusinessDetailPage> createState() => _BusinessDetailPageState();
}

class _BusinessDetailPageState extends State<BusinessDetailPage> {
  late Future<BusinessDetail> detail = widget.gateway.business(
    widget.businessId,
  );
  bool busy = false;

  Future<void> changeStatus(BusinessSummary b) async {
    final suspending = b.status == 'active';
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          suspending ? 'Suspend ${b.name}?' : 'Reactivate ${b.name}?',
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                suspending
                    ? 'Staff can still view their records but cannot create or change anything, and the public storefront goes offline.'
                    : 'The business regains full access and its storefront can be shown again.',
              ),
              TextField(
                controller: reason,
                maxLength: 500,
                decoration: InputDecoration(
                  labelText: suspending
                      ? 'Reason (required)'
                      : 'Note (optional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(suspending ? 'Suspend' : 'Reactivate'),
          ),
        ],
      ),
    );
    final text = reason.text.trim();
    reason.dispose();
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.gateway.setStatus(
        b.id,
        suspending ? 'suspended' : 'active',
        text,
      );
      setState(() => detail = widget.gateway.business(widget.businessId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(adminError(e))));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Business')),
    body: FutureBuilder<BusinessDetail>(
      future: detail,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text(adminError(snapshot.error!)));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return BusinessDetailView(
          detail: snapshot.data!,
          busy: busy,
          onChangeStatus: changeStatus,
          auditLog: AuditLogView(
            gateway: widget.gateway,
            businessId: widget.businessId,
            embedded: true,
          ),
        );
      },
    ),
  );
}

/// Pure view of a business; separated for widget tests.
class BusinessDetailView extends StatelessWidget {
  final BusinessDetail detail;
  final bool busy;
  final void Function(BusinessSummary) onChangeStatus;
  final Widget? auditLog;
  const BusinessDetailView({
    super.key,
    required this.detail,
    required this.busy,
    required this.onChangeStatus,
    this.auditLog,
  });
  @override
  Widget build(BuildContext context) {
    final b = detail.business;
    final active = b.status == 'active';
    final labels = {
      'customers': 'Customers',
      'inquiries': 'Sales inquiries',
      'publicInquiries': 'Website inquiries',
      'quotations': 'Quotations',
      'bookings': 'Bookings',
    };
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(b.name, style: Theme.of(context).textTheme.headlineSmall),
        Text('${b.city} · ${b.phone} · id ${b.id}'),
        Text('Owner: ${b.ownerEmail.isEmpty ? '—' : b.ownerEmail}'),
        Text('Created: ${adminDate(b.createdAt)}'),
        const SizedBox(height: 8),
        Row(
          children: [
            Chip(
              label: Text(active ? 'Active' : 'Suspended'),
              backgroundColor: active
                  ? null
                  : Theme.of(context).colorScheme.errorContainer,
            ),
            const SizedBox(width: 12),
            if (active)
              OutlinedButton.icon(
                onPressed: busy ? null : () => onChangeStatus(b),
                icon: const Icon(Icons.pause),
                label: const Text('Suspend business'),
              )
            else
              FilledButton.icon(
                onPressed: busy ? null : () => onChangeStatus(b),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Reactivate business'),
              ),
          ],
        ),
        if (!active && b.statusReason.isNotEmpty)
          Text('Suspension reason: ${b.statusReason}'),
        const SizedBox(height: 16),
        Text('Usage', style: Theme.of(context).textTheme.titleMedium),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in labels.entries)
              Chip(label: Text('${e.value}: ${detail.usage[e.key] ?? 0}')),
          ],
        ),
        const SizedBox(height: 16),
        Text('Storefront', style: Theme.of(context).textTheme.titleMedium),
        Text(
          detail.storefront == null
              ? 'Not set up'
              : '/b/${detail.storefront!['slug']} · ${detail.storefront!['published'] == true ? 'published' : 'unpublished'}',
        ),
        const SizedBox(height: 16),
        Text('Subscription', style: Theme.of(context).textTheme.titleMedium),
        Text(
          detail.subscription == null
              ? 'No subscription yet (billing arrives in Milestone 13)'
              : '${detail.subscription!['plan']} · ${detail.subscription!['status']}',
        ),
        const SizedBox(height: 16),
        Text(
          'Team (${detail.members.length})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        for (final m in detail.members)
          ListTile(
            dense: true,
            leading: Icon(
              m['active'] == true ? Icons.person : Icons.person_off_outlined,
            ),
            title: Text(
              '${m['email']}'.isEmpty ? '${m['uid']}' : '${m['email']}',
            ),
            subtitle: Text(
              '${m['role']}${m['active'] == true ? '' : ' · inactive'}',
            ),
          ),
        if (auditLog != null) ...[
          const SizedBox(height: 16),
          Text('Admin history', style: Theme.of(context).textTheme.titleMedium),
          auditLog!,
        ],
      ],
    );
  }
}

class AuditLogView extends StatelessWidget {
  final AdminGateway gateway;
  final String? businessId;
  final bool embedded;
  const AuditLogView({
    super.key,
    required this.gateway,
    this.businessId,
    this.embedded = false,
  });
  @override
  Widget build(BuildContext context) => FutureBuilder<List<AdminJson>>(
    future: gateway.auditLog(businessId: businessId),
    builder: (context, snapshot) {
      if (snapshot.hasError) return Text(adminError(snapshot.error!));
      if (!snapshot.hasData) {
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      final entries = snapshot.data!;
      if (entries.isEmpty) {
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Text('No admin actions recorded.'),
        );
      }
      final tiles = [
        for (final e in entries)
          ListTile(
            dense: true,
            leading: Icon(
              e['action'] == 'business.suspend' ? Icons.pause : Icons.history,
            ),
            title: Text('${e['action']} · ${e['businessId']}'),
            subtitle: Text(
              '${e['actorEmail']} · ${adminDate(e['createdAt'] is num ? DateTime.fromMillisecondsSinceEpoch((e['createdAt'] as num).toInt()) : null)}'
              '${'${e['reason'] ?? ''}'.isEmpty ? '' : '\n${e['reason']}'}',
            ),
          ),
      ];
      return embedded
          ? Column(children: tiles)
          : ListView(padding: const EdgeInsets.all(12), children: tiles);
    },
  );
}
