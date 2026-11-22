import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../../core/app/session_controller.dart';
import '../business/domain/business.dart';
import 'customer_site.dart';
import 'storefront_api.dart';

class StorefrontManagementPage extends StatefulWidget {
  const StorefrontManagementPage({super.key});
  @override
  State<StorefrontManagementPage> createState() =>
      _StorefrontManagementPageState();
}

class _StorefrontManagementPageState extends State<StorefrontManagementPage> {
  final _api = StorefrontApi();
  final _form = GlobalKey<FormState>();
  final _fields = {
    for (final key in [
      'slug',
      'displayName',
      'description',
      'services',
      'phone',
      'email',
      'location',
      'logoUrl',
      'heroUrl',
    ])
      key: TextEditingController(),
  };
  final Map<String, Map<String, StoreJson>> _selected = {
    'menus': {},
    'packages': {},
  };
  final Map<String, List<StoreJson>> _catalog = {'menus': [], 'packages': []};
  bool _loading = true;
  bool _loaded = false;
  bool _busy = false;
  bool _published = false;
  String? _error;
  String? _notice;
  String? _savedSlug;
  SessionController get _session => Get.find<SessionController>();
  bool get _owner =>
      _session.membership.value?.active == true &&
      _session.membership.value?.role == BusinessRole.owner;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    if (!_owner) {
      setState(() {
        _loading = false;
        _error = 'Business owner access required.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bid = _session.business.value!.id;
      final settings = await _api.settings(bid);
      final collections = await Future.wait([
        FirebaseFirestore.instance
            .collection('businesses')
            .doc(bid)
            .collection('menuItems')
            .get(),
        FirebaseFirestore.instance
            .collection('businesses')
            .doc(bid)
            .collection('packages')
            .get(),
      ]);
      if (!mounted) return;
      final config =
          settings ??
          <String, dynamic>{'displayName': _session.business.value!.name};
      for (final entry in _fields.entries) {
        entry.value.text = '${config[entry.key] ?? ''}';
      }
      _published = config['published'] == true;
      _savedSlug = settings?['slug'] as String?;
      for (var index = 0; index < 2; index++) {
        final key = index == 0 ? 'menus' : 'packages';
        _selected[key]!.clear();
        for (final value in (config[key] as List? ?? [])) {
          final item = Map<String, dynamic>.from(value as Map);
          _selected[key]!['${item['id']}'] = item;
        }
        _catalog[key] = collections[index].docs
            .map((d) => <String, dynamic>{...d.data(), 'id': d.id})
            .toList();
      }
      _loaded = true;
    } catch (error) {
      if (mounted) _error = storefrontError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  StoreJson _config(bool published) => {
    for (final entry in _fields.entries) entry.key: entry.value.text.trim(),
    'published': published,
    'menus': _selected['menus']!.values.toList(),
    'packages': _selected['packages']!.values.toList(),
  };
  Future<void> _save(bool published) async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await _api.save(_session.business.value!.id, _config(published));
      if (mounted) {
        setState(() {
          _published = published;
          _savedSlug = _fields['slug']!.text.trim();
          _notice = published
              ? 'Storefront published. Your selected content is now public.'
              : 'Saved as unpublished. Your storefront is hidden.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = storefrontError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _preview() {
    if (!_form.currentState!.validate()) return;
    final data = _config(false);
    for (final key in ['menus', 'packages']) {
      data[key] = _selected[key]!.values.map((selection) {
        final source =
            _catalog[key]!
                .where((c) => c['id'] == selection['id'])
                .firstOrNull ??
            <String, dynamic>{};
        return <String, dynamic>{
          'id': selection['id'],
          'name': source['name'] ?? 'Unavailable item',
          'description': selection['description'],
          'imageUrl': selection['imageUrl'],
          'minimumGuests': source['minimumGuests'] ?? 0,
          'pricingMode': source['pricingMode'] ?? '',
          'unit': source['unit'] ?? '',
          if (selection['showPrice'] == true)
            'pricePaisa': source['pricePaisa'],
        };
      }).toList();
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StorefrontPage(api: _api, preview: data),
      ),
    );
  }

  String get _url {
    const origin = String.fromEnvironment('CUSTOMER_SITE_ORIGIN');
    final fallback =
        'https://${FirebaseFirestore.instance.app.options.projectId}.web.app';
    return '${(origin.isEmpty ? fallback : origin).replaceAll(RegExp(r'/$'), '')}/b/$_savedSlug';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Customer storefront')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : !_owner
        ? const Center(child: Text('Business owner access required.'))
        : !_loaded
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error ?? 'Could not load storefront settings.'),
                TextButton(onPressed: _load, child: const Text('Try again')),
              ],
            ),
          )
        : Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    _published
                        ? 'Published storefront'
                        : 'Storefront is unpublished',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Only the details and catalog items selected here become public. Contact details are optional. Changes take effect when you save. Publishing takes a snapshot; republish to apply later catalog changes.',
                  ),
                  const SizedBox(height: 16),
                  if (_savedSlug != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SelectableText(_url),
                            TextButton.icon(
                              icon: const Icon(Icons.copy),
                              label: const Text('Copy storefront URL'),
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: _url),
                                );
                                if (mounted) {
                                  setState(
                                    () => _notice = 'Storefront URL copied.',
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          if (_savedSlug == null)
                            TextButton(
                              onPressed: _load,
                              child: const Text('Retry loading'),
                            ),
                        ],
                      ),
                    ),
                  if (_notice != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Semantics(liveRegion: true, child: Text(_notice!)),
                    ),
                  Form(
                    key: _form,
                    child: Column(
                      children: [
                        for (final entry in _fields.entries)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: TextFormField(
                              controller: entry.value,
                              enabled: !_busy,
                              maxLength: _max(entry.key),
                              minLines: entry.key == 'description' ? 3 : 1,
                              maxLines:
                                  [
                                    'description',
                                    'services',
                                  ].contains(entry.key)
                                  ? 5
                                  : 1,
                              decoration: InputDecoration(
                                labelText: _label(entry.key),
                                border: const OutlineInputBorder(),
                                helperText: entry.key.endsWith('Url')
                                    ? 'Optional HTTPS image from Firebase Storage, Google Storage or Unsplash. Use only images you have permission to publish.'
                                    : entry.key == 'slug'
                                    ? '3–60 lowercase letters, numbers and single hyphens'
                                    : null,
                              ),
                              validator: (value) {
                                final v = (value ?? '').trim();
                                if (entry.key == 'slug' &&
                                    (v.length < 3 ||
                                        v.length > 60 ||
                                        !RegExp(
                                          r'^[a-z0-9]+(?:-[a-z0-9]+)*$',
                                        ).hasMatch(v))) {
                                  return 'Enter a valid public slug.';
                                }
                                if (entry.key == 'displayName' &&
                                    v.length < 3) {
                                  return 'Enter at least three characters.';
                                }
                                if (entry.key == 'email' &&
                                    v.isNotEmpty &&
                                    !RegExp(
                                      r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                    ).hasMatch(v)) {
                                  return 'Enter a valid email address.';
                                }
                                return null;
                              },
                            ),
                          ),
                        for (final key in ['menus', 'packages'])
                          _selection(key),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _preview,
                        icon: const Icon(Icons.visibility_outlined),
                        label: const Text('Preview changes'),
                      ),
                      OutlinedButton(
                        onPressed: _busy ? null : () => _save(false),
                        child: Text(
                          _published
                              ? 'Save and unpublish'
                              : 'Save unpublished',
                        ),
                      ),
                      FilledButton(
                        onPressed: _busy ? null : () => _save(true),
                        child: Text(
                          _busy
                              ? 'Saving…'
                              : _published
                              ? 'Update published website'
                              : 'Publish website',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
  );
  Widget _selection(String key) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 20),
      Text(
        key == 'menus' ? 'Published menu items' : 'Published packages',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const Text(
        'Select up to 40. Prices are hidden by default. Public descriptions are separate from your private catalog.',
      ),
      if (_catalog[key]!.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Add items to your catalog from More first.'),
        ),
      for (final source in _catalog[key]!)
        Builder(
          builder: (context) {
            final itemId = '${source['id']}';
            final selection = _selected[key]![itemId];
            final active = source['active'] == true;
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${source['name']}'),
                      subtitle: active
                          ? null
                          : const Text(
                              'Inactive: remove from your published selection before saving.',
                            ),
                      value: selection != null,
                      onChanged: _busy || (!active && selection == null)
                          ? null
                          : (checked) => setState(() {
                              if (checked == true) {
                                if (_selected[key]!.length < 40) {
                                  _selected[key]![itemId] = {
                                    'id': itemId,
                                    'description': '',
                                    'showPrice': false,
                                    'imageUrl': '',
                                  };
                                }
                              } else {
                                _selected[key]!.remove(itemId);
                              }
                            }),
                    ),
                    if (selection != null) ...[
                      TextFormField(
                        key: ValueKey('$key-$itemId-description'),
                        initialValue: '${selection['description']}',
                        enabled: !_busy,
                        maxLength: 1000,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Public description',
                        ),
                        onChanged: (v) => selection['description'] = v,
                      ),
                      TextFormField(
                        key: ValueKey('$key-$itemId-image'),
                        initialValue: '${selection['imageUrl']}',
                        enabled: !_busy,
                        maxLength: 1600,
                        decoration: const InputDecoration(
                          labelText: 'Public image HTTPS URL (optional)',
                        ),
                        onChanged: (v) => selection['imageUrl'] = v,
                      ),
                      SwitchListTile(
                        title: const Text('Display catalog price publicly'),
                        value: selection['showPrice'] == true,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => selection['showPrice'] = v),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      for (final missing
          in _selected[key]!.keys
              .where((id) => !_catalog[key]!.any((s) => s['id'] == id))
              .toList())
        ListTile(
          title: Text('Missing catalog item: $missing'),
          trailing: TextButton(
            onPressed: _busy
                ? null
                : () => setState(() => _selected[key]!.remove(missing)),
            child: const Text('Remove'),
          ),
        ),
    ],
  );
  int _max(String key) => switch (key) {
    'slug' => 60,
    'displayName' => 120,
    'description' => 3000,
    'services' => 1000,
    'phone' => 30,
    'email' => 160,
    'location' => 200,
    _ => 1600,
  };
  String _label(String key) => switch (key) {
    'slug' => 'Public slug',
    'displayName' => 'Business display name',
    'description' => 'About your business',
    'services' => 'Services offered',
    'phone' => 'Public phone (optional)',
    'email' => 'Public email (optional)',
    'location' => 'Public location (optional)',
    'logoUrl' => 'Logo image URL',
    _ => 'Hero image URL',
  };
}
