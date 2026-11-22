import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'storefront_api.dart';

class CustomerSite extends StatelessWidget {
  final StorefrontGateway api;
  final String? path;
  const CustomerSite({super.key, required this.api, this.path});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Catering | Your next occasion',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff285448)),
      scaffoldBackgroundColor: const Color(0xfffaf8f2),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
    ),
    initialRoute: path ?? Uri.base.path,
    onGenerateInitialRoutes: (initial) => [
      MaterialPageRoute<void>(
        builder: (_) => StorefrontPage(api: api, slug: storefrontSlug(initial)),
      ),
    ],
    onGenerateRoute: (route) => MaterialPageRoute<void>(
      settings: route,
      builder: (_) => StorefrontPage(
        api: api,
        slug: storefrontSlug(Uri.tryParse(route.name ?? '/')?.path ?? '/'),
      ),
    ),
  );
}

class StorefrontPage extends StatefulWidget {
  final StorefrontGateway api;
  final String? slug;
  final StoreJson? preview;
  const StorefrontPage({super.key, required this.api, this.slug, this.preview});
  @override
  State<StorefrontPage> createState() => _StorefrontPageState();
}

class _StorefrontPageState extends State<StorefrontPage> {
  late Future<StoreJson> _data;
  final _inquiry = GlobalKey();
  String? _package;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _data = widget.preview != null
        ? Future.value(widget.preview)
        : widget.slug == null
        ? Future.error(const FormatException('Invalid storefront address'))
        : widget.api.load(widget.slug!);
  }

  void _quote([String? package]) {
    setState(() => _package = package);
    final target = _inquiry.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 450),
        alignment: 0.05,
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: FutureBuilder<StoreJson>(
      future: _data,
      builder: (context, state) {
        if (state.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(
              semanticsLabel: 'Loading storefront',
            ),
          );
        }
        if (state.hasError || !state.hasData) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.storefront_outlined, size: 64),
                  const SizedBox(height: 20),
                  Text(
                    widget.slug == null
                        ? 'Storefront not found'
                        : storefrontError(state.error!),
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Check your link or contact the catering business.',
                  ),
                  if (widget.slug != null)
                    TextButton(
                      onPressed: () => setState(_reload),
                      child: const Text('Try again'),
                    ),
                ],
              ),
            ),
          );
        }
        final data = state.data!;
        final menus = (data['menus'] as List? ?? [])
            .map((v) => Map<String, dynamic>.from(v as Map))
            .toList();
        final packages = (data['packages'] as List? ?? [])
            .map((v) => Map<String, dynamic>.from(v as Map))
            .toList();
        return SelectionArea(
          child: SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1240),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: MediaQuery.sizeOf(context).width < 600
                        ? 20
                        : 48,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.preview != null)
                        TextButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Back to storefront settings'),
                        ),
                      if (widget.preview != null)
                        const Padding(
                          padding: EdgeInsets.only(top: 16),
                          child: Text(
                            'OWNER PREVIEW · Inquiry submission is disabled',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Row(
                          children: [
                            if ('${data['logoUrl'] ?? ''}'.isNotEmpty)
                              SizedBox(
                                width: 48,
                                height: 48,
                                child: _Photo(
                                  url: data['logoUrl'],
                                  label: '${data['displayName']} logo',
                                ),
                              ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${data['displayName']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 21,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: _quote,
                              child: const Text('Get a quote'),
                            ),
                          ],
                        ),
                      ),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final copy = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'GOOD FOOD. GREAT GATHERINGS.',
                                style: TextStyle(
                                  letterSpacing: 2,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 22),
                              Text(
                                'Made for your\nmemorable moments.',
                                style: TextStyle(
                                  fontSize: constraints.maxWidth < 700
                                      ? 40
                                      : 60,
                                  height: 1.08,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xff204438),
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                '${data['description']}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  height: 1.7,
                                ),
                              ),
                              const SizedBox(height: 28),
                              FilledButton.icon(
                                onPressed: _quote,
                                icon: const Icon(Icons.arrow_forward),
                                label: const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text('Plan your occasion'),
                                ),
                              ),
                              const SizedBox(height: 20),
                              const Text(
                                'Tell us what you have in mind. We’ll help with the details.',
                              ),
                            ],
                          );
                          final photo = ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: SizedBox(
                              height: 420,
                              width: double.infinity,
                              child: _Photo(
                                url: '${data['heroUrl'] ?? ''}',
                                label: 'Catering by ${data['displayName']}',
                              ),
                            ),
                          );
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 30),
                            child: constraints.maxWidth < 800
                                ? Column(
                                    children: [
                                      copy,
                                      const SizedBox(height: 30),
                                      photo,
                                    ],
                                  )
                                : Row(
                                    children: [
                                      Expanded(child: copy),
                                      const SizedBox(width: 48),
                                      Expanded(child: photo),
                                    ],
                                  ),
                          );
                        },
                      ),
                      if ('${data['services'] ?? ''}'.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          margin: const EdgeInsets.symmetric(vertical: 24),
                          decoration: BoxDecoration(
                            color: const Color(0xffe7ede5),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'EVERY DETAIL, TAKEN CARE OF',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '${data['services']}',
                                style: const TextStyle(
                                  fontSize: 17,
                                  height: 1.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      _catalog(
                        'Packages for your occasion',
                        'A starting point for something special.',
                        packages,
                        true,
                      ),
                      _catalog(
                        'From our kitchen',
                        'Explore the dishes available for your event.',
                        menus,
                        false,
                      ),
                      const SizedBox(height: 50),
                      Container(
                        key: _inquiry,
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: const Color(0xffe7ede5),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Let’s bring your event to life.',
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Request a quotation. Your inquiry does not confirm a booking.',
                            ),
                            const SizedBox(height: 24),
                            InquiryForm(
                              api: widget.api,
                              slug: widget.slug ?? '',
                              packages: packages,
                              selectedPackage: _package,
                              preview: widget.preview != null,
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${data['displayName']}',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            for (final field in ['location', 'phone', 'email'])
                              if ('${data[field] ?? ''}'.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text('${data[field]}'),
                                ),
                            const SizedBox(height: 24),
                            const Text(
                              'Powered by Caterer Pro',
                              style: TextStyle(color: Color(0xff52635c)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
  Widget _catalog(
    String title,
    String subtitle,
    List<StoreJson> items,
    bool packages,
  ) => Padding(
    padding: const EdgeInsets.only(top: 40),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Text(subtitle),
        const SizedBox(height: 24),
        if (items.isEmpty)
          const Text('Please contact us for our latest options.'),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth > 1000
                ? 3
                : constraints.maxWidth > 650
                ? 2
                : 1;
            final width = (constraints.maxWidth - (columns - 1) * 20) / columns;
            return Wrap(
              spacing: 20,
              runSpacing: 20,
              children: items
                  .map(
                    (item) => SizedBox(
                      width: width,
                      child: Card(
                        margin: EdgeInsets.zero,
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if ('${item['imageUrl'] ?? ''}'.isNotEmpty)
                              SizedBox(
                                height: 190,
                                width: double.infinity,
                                child: _Photo(
                                  url: item['imageUrl'],
                                  label: '${item['name']}',
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.all(22),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${item['name']}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    '${item['description'] ?? ''}',
                                    style: const TextStyle(height: 1.6),
                                  ),
                                  if (packages)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 14),
                                      child: Text(
                                        'Minimum ${item['minimumGuests']} guests · ${item['pricingMode']}',
                                      ),
                                    ),
                                  const SizedBox(height: 16),
                                  Text(
                                    item['pricePaisa'] is num
                                        ? 'Rs ${(item['pricePaisa'] / 100).toStringAsFixed(2)} / ${packages ? item['pricingMode'] : item['unit']}'
                                        : 'Pricing on request',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (packages)
                                    TextButton(
                                      onPressed: () => _quote('${item['id']}'),
                                      child: const Text(
                                        'Ask about this package ?',
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    ),
  );
}

class _Photo extends StatelessWidget {
  final String url;
  final String label;
  const _Photo({required this.url, required this.label});
  Widget get fallback => Container(
    color: const Color(0xffdce5d8),
    child: const Center(
      child: Icon(Icons.restaurant, size: 80, color: Color(0xff42634f)),
    ),
  );
  @override
  Widget build(BuildContext context) => url.isEmpty
      ? fallback
      : Image.network(
          url,
          fit: BoxFit.cover,
          semanticLabel: label,
          errorBuilder: (_, error, stack) => fallback,
          loadingBuilder: (_, child, progress) =>
              progress == null ? child : fallback,
        );
}

class InquiryForm extends StatefulWidget {
  final StorefrontGateway api;
  final String slug;
  final List<StoreJson> packages;
  final String? selectedPackage;
  final bool preview;
  const InquiryForm({
    super.key,
    required this.api,
    required this.slug,
    required this.packages,
    this.selectedPackage,
    this.preview = false,
  });
  @override
  State<InquiryForm> createState() => _InquiryFormState();
}

class _InquiryFormState extends State<InquiryForm> {
  final _form = GlobalKey<FormState>();
  final _fields = {
    for (final name in [
      'name',
      'phone',
      'email',
      'eventType',
      'guests',
      'requirements',
    ])
      name: TextEditingController(),
  };
  DateTime? _date;
  String? _package;
  bool _busy = false;
  String? _error;
  String? _receipt;
  String _requestId = const Uuid().v4();
  String? _lastPayload;
  @override
  void initState() {
    super.initState();
    _package = widget.selectedPackage;
  }

  @override
  void didUpdateWidget(covariant InquiryForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedPackage != widget.selectedPackage) {
      _package = widget.selectedPackage;
    }
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_receipt != null) {
      return Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.check_circle_outline, size: 40),
            const SizedBox(height: 12),
            const Text(
              'Thank you! Your inquiry has been received.',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'The business will contact you using the details you provided. Your event is not booked yet.',
            ),
            const SizedBox(height: 8),
            SelectableText('Reference: $_receipt'),
          ],
        ),
      );
    }
    return Form(
      key: _form,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth > 650
              ? (constraints.maxWidth - 16) / 2
              : constraints.maxWidth;
          Widget field(
            String name,
            String label,
            int max, {
            bool required = true,
            TextInputType? keyboard,
            int lines = 1,
          }) => SizedBox(
            width: lines > 1 ? constraints.maxWidth : width,
            child: TextFormField(
              controller: _fields[name],
              enabled: !_busy,
              maxLength: max,
              maxLines: lines,
              keyboardType: keyboard,
              decoration: InputDecoration(labelText: label),
              validator: (value) {
                final v = (value ?? '').trim();
                if (required &&
                    v.length < (name == 'phone' ? 7 : 2) &&
                    name != 'guests') {
                  return 'Please enter $label.';
                }
                if (name == 'phone' &&
                    !RegExp(r'^[+\d() .-]{7,30}$').hasMatch(v)) {
                  return 'Enter a valid phone number.';
                }
                if (name == 'email' &&
                    v.isNotEmpty &&
                    !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v)) {
                  return 'Enter a valid email address.';
                }
                if (name == 'guests' &&
                    ((int.tryParse(v) ?? 0) < 1 ||
                        (int.tryParse(v) ?? 0) > 100000)) {
                  return 'Enter 1–100000 guests.';
                }
                return null;
              },
            ),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  field('name', 'Your name', 120, keyboard: TextInputType.name),
                  field(
                    'phone',
                    'Phone number',
                    30,
                    keyboard: TextInputType.phone,
                  ),
                  field(
                    'email',
                    'Email (optional)',
                    160,
                    required: false,
                    keyboard: TextInputType.emailAddress,
                  ),
                  field('eventType', 'Event type', 60),
                  SizedBox(
                    width: width,
                    child: FormField<DateTime>(
                      validator: (_) =>
                          _date == null ? 'Choose an event date.' : null,
                      builder: (state) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(Icons.event),
                            label: Text(
                              _date == null
                                  ? 'Choose event date'
                                  : _date!.toIso8601String().substring(0, 10),
                            ),
                            onPressed: _busy
                                ? null
                                : () async {
                                    final now = DateTime.now().toUtc();
                                    final today = DateTime(
                                      now.year,
                                      now.month,
                                      now.day,
                                    );
                                    final date = await showDatePicker(
                                      context: context,
                                      initialDate: _date ?? today,
                                      firstDate: today,
                                      lastDate: today.add(
                                        const Duration(days: 1097),
                                      ),
                                    );
                                    if (date != null && mounted) {
                                      setState(() {
                                        _date = date;
                                        state.didChange(date);
                                      });
                                    }
                                  },
                          ),
                          if (state.hasError)
                            Text(
                              state.errorText!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  field(
                    'guests',
                    'Expected guests',
                    6,
                    keyboard: TextInputType.number,
                  ),
                  SizedBox(
                    width: constraints.maxWidth,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(_package),
                      initialValue: _package ?? '',
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Package (optional)',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Help me choose'),
                        ),
                        ...widget.packages.map(
                          (p) => DropdownMenuItem(
                            value: '${p['id']}',
                            child: Text('${p['name']}'),
                          ),
                        ),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _package = v),
                    ),
                  ),
                  field(
                    'requirements',
                    'Additional requirements (optional)',
                    2000,
                    required: false,
                    lines: 4,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Your contact details will be shared with this catering business so they can respond to your request.',
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _busy || widget.preview ? null : _send,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                label: Text(_busy ? 'Sending…' : 'Request a quotation'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    final data = <String, dynamic>{
      'slug': widget.slug,
      for (final entry in _fields.entries) entry.key: entry.value.text.trim(),
      'guests': int.parse(_fields['guests']!.text.trim()),
      'eventDate': _date!.toIso8601String().substring(0, 10),
      'packageId': _package ?? '',
    };
    final signature = data.toString();
    if (_lastPayload != null && _lastPayload != signature) {
      _requestId = const Uuid().v4();
    }
    _lastPayload = signature;
    data['requestId'] = _requestId;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final receipt = await widget.api.submit(data);
      if (mounted) setState(() => _receipt = receipt);
    } catch (error) {
      if (mounted) setState(() => _error = storefrontError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
