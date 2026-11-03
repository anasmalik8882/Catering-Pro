import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/app/session_controller.dart';
import '../../business/domain/business.dart';
import 'package:flutter/material.dart';
import '../data/sales_repository.dart';
import '../domain/sales_models.dart';
import 'package:intl/intl.dart';
import 'quotation_export.dart';
import 'package:get/get.dart';

SalesRepository sales() {
  final session = Get.find<SessionController>();
  return SalesRepository(
    FirebaseFirestore.instance,
    session.business.value!.id,
    session.auth.currentUser!.uid,
  );
}

bool salesEditor() {
  final role = Get.find<SessionController>().membership.value?.role;
  return role == BusinessRole.owner ||
      role == BusinessRole.manager ||
      role == BusinessRole.sales;
}

void errorNotice(Object e) => Get.snackbar(
  'Could not save',
  e.toString(),
  snackPosition: SnackPosition.BOTTOM,
);
Future<void> execute(Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    errorNotice(e);
  }
}

InputDecoration field(String label) =>
    InputDecoration(labelText: label, border: const OutlineInputBorder());
Widget gap([double n = 12]) => SizedBox(height: n);
int parsePaisa(String s) {
  final amount = double.tryParse(s.trim());
  if (amount == null ||
      !amount.isFinite ||
      amount < 0 ||
      amount > 100000000000) {
    throw const FormatException('Enter a valid non-negative amount');
  }
  return money(amount);
}

String humanDate(DateTime? date) =>
    date == null ? 'Not set' : DateFormat('dd MMM yyyy').format(date);

class SalesHome extends StatelessWidget {
  const SalesHome({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sales & catering')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Customers, inquiries, menu and quotations',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        gap(),
        for (final entry in [
          (
            Icons.people_outline,
            'Customers',
            'Customer directory and history',
            const CustomersPage(),
          ),
          (
            Icons.forum_outlined,
            'Inquiries',
            'Event requests and follow-ups',
            const InquiriesPage(),
          ),
          (
            Icons.restaurant_menu,
            'Food menu',
            'Dishes and fixed-price daigs',
            const MenuPage(),
          ),
          (
            Icons.inventory_2_outlined,
            'Catering packages',
            'Per-head, daig and flat-rate packages',
            const PackagesPage(),
          ),
          (
            Icons.request_quote_outlined,
            'Quotations',
            'Create, revise and share quotations',
            const QuotationsPage(),
          ),
        ])
          Card(
            child: ListTile(
              leading: Icon(entry.$1),
              title: Text(entry.$2),
              subtitle: Text(entry.$3),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Get.to(() => entry.$4),
            ),
          ),
      ],
    ),
  );
}

class RecordsView extends StatelessWidget {
  final String collectionName;
  final Widget Function(BuildContext, SalesRecord) row;
  const RecordsView({
    super.key,
    required this.collectionName,
    required this.row,
  });
  @override
  Widget build(BuildContext context) => StreamBuilder<List<SalesRecord>>(
    stream: sales().watch(collectionName),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(child: Text('Could not load records: ${snapshot.error}'));
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.data!.isEmpty) {
        return const Center(
          child: Text('No records yet. Create your first entry.'),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: snapshot.data!.length,
        itemBuilder: (ctx, i) => row(ctx, snapshot.data![i]),
      );
    },
  );
}

class CustomersPage extends StatelessWidget {
  const CustomersPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Customers')),
    floatingActionButton: salesEditor()
        ? FloatingActionButton.extended(
            onPressed: () => customerForm(context),
            icon: const Icon(Icons.add),
            label: const Text('Customer'),
          )
        : null,
    body: RecordsView(
      collectionName: 'customers',
      row: (ctx, r) => Card(
        child: ListTile(
          title: Text(r.str('name')),
          subtitle: Text(r.str('phone')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => customerDetails(ctx, r),
          onLongPress: salesEditor()
              ? () => customerForm(ctx, existing: r)
              : null,
        ),
      ),
    ),
  );
}

Future<void> customerForm(BuildContext context, {SalesRecord? existing}) async {
  final name = TextEditingController(text: existing?.str('name'));
  final phone = TextEditingController(text: existing?.str('phone'));
  final email = TextEditingController(text: existing?.str('email'));
  final notes = TextEditingController(text: existing?.str('notes'));
  final key = GlobalKey<FormState>();
  Future<void>? routeCompleted;
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      routeCompleted ??= ModalRoute.of(ctx)?.completed;
      return AlertDialog(
        title: Text(existing == null ? 'New customer' : 'Edit customer'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: key,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    decoration: field('Full name'),
                    validator: (v) => v == null || v.trim().length < 2
                        ? 'Enter a name'
                        : null,
                  ),
                  gap(),
                  TextFormField(
                    controller: phone,
                    decoration: field('Phone / WhatsApp'),
                    validator: (v) => v == null || v.trim().length < 7
                        ? 'Enter a valid phone'
                        : null,
                  ),
                  gap(),
                  TextFormField(
                    controller: email,
                    decoration: field('Email (optional)'),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  gap(),
                  TextField(
                    controller: notes,
                    decoration: field('Notes'),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!key.currentState!.validate()) return;
              try {
                if (existing == null) {
                  await sales().createCustomer(
                    name: name.text,
                    phone: phone.text,
                    email: email.text,
                    notes: notes.text,
                  );
                } else {
                  await sales().updateCustomer(
                    existing.id,
                    name: name.text,
                    phone: phone.text,
                    email: email.text,
                    notes: notes.text,
                  );
                }
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                errorNotice(e);
              }
            },
            child: const Text('Save'),
          ),
        ],
      );
    },
  );
  if (routeCompleted != null) {
    await routeCompleted;
  }
  name.dispose();
  phone.dispose();
  email.dispose();
  notes.dispose();
}

void customerDetails(BuildContext context, SalesRecord customer) {
  Get.to(
    () => Scaffold(
      appBar: AppBar(title: Text(customer.str('name'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            title: const Text('Phone'),
            subtitle: Text(customer.str('phone')),
          ),
          ListTile(
            title: const Text('Email'),
            subtitle: Text(customer.str('email')),
          ),
          ListTile(
            title: const Text('Notes'),
            subtitle: Text(customer.str('notes')),
          ),
          const Divider(),
          const Text(
            'Inquiries',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          SizedBox(
            height: 210,
            child: RecordsView(
              collectionName: 'inquiries',
              row: (c, r) => r.str('customerId') == customer.id
                  ? ListTile(
                      title: Text(r.str('eventType')),
                      subtitle: Text(
                        '${r.str('status')} • ${humanDate(r.date('eventDate'))}',
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          const Text(
            'Quotations',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          SizedBox(
            height: 210,
            child: RecordsView(
              collectionName: 'quotations',
              row: (c, r) => r.str('customerId') == customer.id
                  ? ListTile(
                      title: Text(
                        '${pkr(r.number('totalPaisa'))} • ${r.str('status')}',
                      ),
                      onTap: () => quoteDetails(r),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    ),
  );
}

class InquiriesPage extends StatelessWidget {
  const InquiriesPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Inquiries')),
    floatingActionButton: salesEditor()
        ? FloatingActionButton.extended(
            onPressed: () => inquiryForm(context),
            label: const Text('Inquiry'),
            icon: const Icon(Icons.add),
          )
        : null,
    body: RecordsView(
      collectionName: 'inquiries',
      row: (ctx, r) => Card(
        child: ListTile(
          title: Text('${r.str('eventType')} • ${r.number('guests')} guests'),
          subtitle: Text(
            '${humanDate(r.date('eventDate'))} · ${r.str('source')} · ${r.str('status')}\nFollow-up: ${humanDate(r.date('followUpAt'))}',
          ),
          isThreeLine: true,
          onTap: () => inquiryDetails(ctx, r),
        ),
      ),
    ),
  );
}

Future<void> inquiryForm(BuildContext context) async {
  final customers = await sales().collection('customers').get();
  if (customers.docs.isEmpty) {
    errorNotice('Create a customer first.');
    return;
  }
  if (!context.mounted) return;
  String selected = customers.docs.first.id;
  String type = 'Wedding';
  String source = 'WhatsApp';
  DateTime date = DateTime.now().add(const Duration(days: 7));
  final guests = TextEditingController(text: '100');
  final notes = TextEditingController();
  Future<void>? routeCompleted;
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      routeCompleted ??= ModalRoute.of(ctx)?.completed;
      return StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('New inquiry'),
          content: SizedBox(
            width: 430,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selected,
                    decoration: field('Customer'),
                    items: customers.docs
                        .map(
                          (d) => DropdownMenuItem(
                            value: d.id,
                            child: Text('${d.data()['name']}'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => set(() => selected = v!),
                  ),
                  gap(),
                  DropdownButtonFormField(
                    initialValue: type,
                    decoration: field('Event type'),
                    items:
                        [
                              'Wedding',
                              'Mehndi',
                              'Baraat',
                              'Walima',
                              'Birthday',
                              'Corporate',
                              'Milad/Niyaz',
                              'Daig / bulk',
                              'Other',
                            ]
                            .map(
                              (v) => DropdownMenuItem(value: v, child: Text(v)),
                            )
                            .toList(),
                    onChanged: (v) => set(() => type = v!),
                  ),
                  gap(),
                  TextField(
                    controller: guests,
                    keyboardType: TextInputType.number,
                    decoration: field('Guests'),
                  ),
                  gap(),
                  ListTile(
                    title: Text('Event date: ${humanDate(date)}'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final next = await showDatePicker(
                        context: ctx,
                        initialDate: date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (next != null) set(() => date = next);
                    },
                  ),
                  gap(),
                  DropdownButtonFormField(
                    initialValue: source,
                    decoration: field('Inquiry source'),
                    items:
                        [
                              'WhatsApp',
                              'Call',
                              'Instagram',
                              'Referral',
                              'Website',
                              'Other',
                            ]
                            .map(
                              (v) => DropdownMenuItem(value: v, child: Text(v)),
                            )
                            .toList(),
                    onChanged: (v) => set(() => source = v!),
                  ),
                  gap(),
                  TextField(
                    controller: notes,
                    decoration: field('Event requirements'),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final count = int.tryParse(guests.text);
                if (count == null || count <= 0) {
                  errorNotice('Enter a positive guest count');
                  return;
                }
                try {
                  await sales().createInquiry(
                    customerId: selected,
                    eventType: type,
                    guests: count,
                    eventDate: date,
                    source: source,
                    notes: notes.text,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  errorNotice(e);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
    },
  );
  if (routeCompleted != null) {
    await routeCompleted;
  }
  guests.dispose();
  notes.dispose();
}

void inquiryDetails(BuildContext context, SalesRecord r) {
  String status = r.str('status');
  DateTime? next = r.date('followUpAt');
  showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(r.str('eventType')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Guests: ${r.number('guests')} · ${humanDate(r.date('eventDate'))}',
            ),
            gap(),
            DropdownButtonFormField<String>(
              initialValue: status,
              decoration: field('Status'),
              items: [
                'new',
                'contacted',
                'quoted',
                'won',
                'lost',
              ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: salesEditor() ? (v) => set(() => status = v!) : null,
            ),
            gap(),
            ListTile(
              title: Text('Follow up: ${humanDate(next)}'),
              trailing: const Icon(Icons.event),
              onTap: !salesEditor()
                  ? null
                  : () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: next ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      set(() => next = picked);
                    },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          if (salesEditor())
            FilledButton(
              onPressed: () async {
                try {
                  await sales().updateInquiry(r.id, status, next);
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  errorNotice(e);
                }
              },
              child: const Text('Save'),
            ),
        ],
      ),
    ),
  );
}

class MenuPage extends StatelessWidget {
  const MenuPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Food menu')),
    floatingActionButton: salesEditor()
        ? FloatingActionButton.extended(
            onPressed: () => menuForm(context),
            label: const Text('Add dish'),
            icon: const Icon(Icons.add),
          )
        : null,
    body: RecordsView(
      collectionName: 'menuItems',
      row: (ctx, r) => Card(
        child: ListTile(
          title: Text(r.str('name')),
          subtitle: Text(
            '${r.str('type')} · ${r.str('unit')} · ${r.data['active'] == false ? 'Inactive' : 'Active'}',
          ),
          trailing: Text(pkr(r.number('pricePaisa'))),
          onTap: salesEditor() ? () => menuForm(ctx, r) : null,
        ),
      ),
    ),
  );
}

Future<void> menuForm(BuildContext context, [SalesRecord? existing]) async {
  final name = TextEditingController(text: existing?.str('name'));
  final price = TextEditingController(
    text: existing == null
        ? ''
        : (existing.number('pricePaisa') / 100).toStringAsFixed(2),
  );
  final description = TextEditingController(text: existing?.str('description'));
  String type = existing?.str('type') ?? 'Dish';
  String unit = existing?.str('unit') ?? 'per head';
  bool active = existing?.data['active'] != false;
  Future<void>? routeCompleted;
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      routeCompleted ??= ModalRoute.of(ctx)?.completed;
      return StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(existing == null ? 'Add menu item' : 'Edit menu item'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: name, decoration: field('Item name')),
                  gap(),
                  DropdownButtonFormField(
                    initialValue: type,
                    decoration: field('Type'),
                    items:
                        [
                              'Dish',
                              'BBQ',
                              'Biryani',
                              'Pulao',
                              'Handi',
                              'Dessert',
                              'Daig',
                              'Extra',
                            ]
                            .map(
                              (s) => DropdownMenuItem(value: s, child: Text(s)),
                            )
                            .toList(),
                    onChanged: (v) => set(() => type = v!),
                  ),
                  gap(),
                  DropdownButtonFormField(
                    initialValue: unit,
                    decoration: field('Price unit'),
                    items:
                        ['per head', 'per daig', 'per tray', 'per kg', 'fixed']
                            .map(
                              (s) => DropdownMenuItem(value: s, child: Text(s)),
                            )
                            .toList(),
                    onChanged: (v) => set(() => unit = v!),
                  ),
                  gap(),
                  TextField(
                    controller: price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: field('Price (PKR)'),
                  ),
                  gap(),
                  TextField(
                    controller: description,
                    decoration: field('Description'),
                  ),
                  if (existing != null)
                    SwitchListTile(
                      title: const Text('Active'),
                      value: active,
                      onChanged: (v) => set(() => active = v),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (name.text.trim().length < 2) {
                  errorNotice('Enter a valid item name');
                  return;
                }
                try {
                  final amount = parsePaisa(price.text);
                  if (existing == null) {
                    await sales().createMenu(
                      name: name.text,
                      type: type,
                      pricePaisa: amount,
                      unit: unit,
                      description: description.text,
                    );
                  } else {
                    await sales().updateMenu(
                      existing.id,
                      name: name.text,
                      type: type,
                      pricePaisa: amount,
                      unit: unit,
                      description: description.text,
                      active: active,
                    );
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  errorNotice(e);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
    },
  );
  if (routeCompleted != null) {
    await routeCompleted;
  }
  name.dispose();
  price.dispose();
  description.dispose();
}

class PackagesPage extends StatelessWidget {
  const PackagesPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Catering packages')),
    floatingActionButton: salesEditor()
        ? FloatingActionButton.extended(
            onPressed: () => packageForm(context),
            label: const Text('Package'),
            icon: const Icon(Icons.add),
          )
        : null,
    body: RecordsView(
      collectionName: 'packages',
      row: (ctx, r) => Card(
        child: ListTile(
          title: Text(r.str('name')),
          subtitle: Text(
            '${r.str('pricingMode')} · Min guests: ${r.number('minimumGuests')}\n${r.str('description')}',
          ),
          isThreeLine: true,
          trailing: Text(pkr(r.number('pricePaisa'))),
        ),
      ),
    ),
  );
}

Future<void> packageForm(BuildContext context) async {
  final name = TextEditingController();
  final price = TextEditingController();
  final minimum = TextEditingController(text: '1');
  final description = TextEditingController();
  String mode = 'per head';
  Future<void>? routeCompleted;
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      routeCompleted ??= ModalRoute.of(ctx)?.completed;
      return StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Add package'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: field('Package name'),
                  ),
                  gap(),
                  DropdownButtonFormField(
                    initialValue: mode,
                    decoration: field('Pricing mode'),
                    items: ['per head', 'per daig', 'fixed']
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => set(() => mode = v!),
                  ),
                  gap(),
                  TextField(
                    controller: price,
                    keyboardType: TextInputType.number,
                    decoration: field('PKR per unit'),
                  ),
                  gap(),
                  TextField(
                    controller: minimum,
                    keyboardType: TextInputType.number,
                    decoration: field('Minimum guests'),
                  ),
                  gap(),
                  TextField(
                    controller: description,
                    decoration: field('Included dishes / details'),
                    maxLines: 3,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  final min = int.parse(minimum.text);
                  if (name.text.trim().length < 2 || min < 1) {
                    throw const FormatException('Invalid package details');
                  }
                  await sales().createPackage(
                    name: name.text,
                    pricingMode: mode,
                    pricePaisa: parsePaisa(price.text),
                    minimumGuests: min,
                    description: description.text,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  errorNotice(e);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
    },
  );
  if (routeCompleted != null) {
    await routeCompleted;
  }
  name.dispose();
  price.dispose();
  minimum.dispose();
  description.dispose();
}

class QuotationsPage extends StatelessWidget {
  const QuotationsPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Quotations')),
    floatingActionButton: salesEditor()
        ? FloatingActionButton.extended(
            onPressed: () => Get.to(() => const QuoteEditor()),
            label: const Text('Quotation'),
            icon: const Icon(Icons.add),
          )
        : null,
    body: RecordsView(
      collectionName: 'quotations',
      row: (ctx, r) => Card(
        child: ListTile(
          title: Text(
            '${pkr(r.number('totalPaisa'))} · ${r.str('status').toUpperCase()}',
          ),
          subtitle: Text(
            '${r.str('eventType')} • ${r.number('guests')} guests · ${humanDate(r.date('eventDate'))}\nRevision ${r.number('revision')}',
          ),
          isThreeLine: true,
          onTap: () => quoteDetails(r),
        ),
      ),
    ),
  );
}

class QuoteEditor extends StatefulWidget {
  final SalesRecord? existing;
  const QuoteEditor({super.key, this.existing});
  @override
  State<QuoteEditor> createState() => _QuoteEditorState();
}

class _QuoteEditorState extends State<QuoteEditor> {
  List<SalesRecord> customers = [];
  List<SalesRecord> items = [];
  List<SalesRecord> packages = [];
  List<QuoteLine> lines = [];
  String? customerId;
  String eventType = 'Wedding';
  DateTime eventDate = DateTime.now().add(const Duration(days: 7));
  final guests = TextEditingController(text: '100');
  final extras = TextEditingController(text: '0');
  final discount = TextEditingController(text: '0');
  final notes = TextEditingController();
  bool busy = true;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final values = await Future.wait([
        sales().collection('customers').get(),
        sales().collection('menuItems').get(),
        sales().collection('packages').get(),
      ]);
      customers = (values[0]).docs
          .map((d) => SalesRecord(d.id, d.data()))
          .toList();
      items = values[1].docs
          .where((d) => d.data()['active'] == true)
          .map((d) => SalesRecord(d.id, d.data()))
          .toList();
      packages = values[2].docs
          .where((d) => d.data()['active'] == true)
          .map((d) => SalesRecord(d.id, d.data()))
          .toList();
      customerId =
          widget.existing?.str('customerId') ??
          (customers.isEmpty ? null : customers.first.id);
      if (widget.existing != null) {
        final rev = await sales().revision(
          widget.existing!.id,
          widget.existing!.number('revision'),
        );
        lines = (rev.data['lines'] as List)
            .map((e) => QuoteLine.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        extras.text = (rev.number('extraPaisa') / 100).toStringAsFixed(2);
        discount.text = (rev.number('discountPaisa') / 100).toStringAsFixed(2);
        notes.text = rev.str('notes');
      }
    } catch (e) {
      errorNotice(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    guests.dispose();
    extras.dispose();
    discount.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> addLine() async {
    if (items.isEmpty && packages.isEmpty) {
      errorNotice('Add a menu item or catering package first.');
      return;
    }
    final all = [...items, ...packages];
    SalesRecord chosen = all.first;
    final qty = TextEditingController(text: '1');
    Future<void>? routeCompleted;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        routeCompleted ??= ModalRoute.of(ctx)?.completed;
        return StatefulBuilder(
          builder: (ctx, set) => AlertDialog(
            title: const Text('Add quotation line'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: chosen.id,
                  decoration: field('Menu item / package'),
                  isExpanded: true,
                  items: all
                      .map(
                        (r) => DropdownMenuItem(
                          value: r.id,
                          child: Text(
                            '${r.str('name')} · ${pkr(r.number('pricePaisa'))}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) =>
                      set(() => chosen = all.firstWhere((r) => r.id == v)),
                ),
                gap(),
                TextField(
                  controller: qty,
                  keyboardType: TextInputType.number,
                  decoration: field('Quantity (guests / daigs / units)'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final count = int.tryParse(qty.text);
                  if (count == null || count < 1) {
                    errorNotice('Quantity must be positive');
                    return;
                  }
                  setState(
                    () => lines.add(
                      QuoteLine(
                        chosen.id,
                        chosen.str('name'),
                        count,
                        chosen.number('pricePaisa'),
                      ),
                    ),
                  );
                  Navigator.pop(ctx);
                },
                child: const Text('Add'),
              ),
            ],
          ),
        );
      },
    );
    if (routeCompleted != null) {
      await routeCompleted;
    }
    qty.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subtotal = lines.fold<int>(0, (value, line) => value + line.total);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null ? 'New quotation' : 'Revise quotation',
        ),
      ),
      body: busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (customers.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Create a customer before making a quotation.',
                      ),
                    ),
                  ),
                if (customers.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: customers.any((r) => r.id == customerId)
                        ? customerId
                        : customers.first.id,
                    decoration: field('Customer'),
                    items: customers
                        .map(
                          (r) => DropdownMenuItem(
                            value: r.id,
                            child: Text(r.str('name')),
                          ),
                        )
                        .toList(),
                    onChanged: widget.existing == null
                        ? (v) => setState(() => customerId = v)
                        : null,
                  ),
                gap(),
                if (widget.existing == null) ...[
                  DropdownButtonFormField(
                    initialValue: eventType,
                    decoration: field('Event type'),
                    items:
                        [
                              'Wedding',
                              'Mehndi',
                              'Baraat',
                              'Walima',
                              'Birthday',
                              'Corporate',
                              'Daig / bulk',
                              'Other',
                            ]
                            .map(
                              (v) => DropdownMenuItem(value: v, child: Text(v)),
                            )
                            .toList(),
                    onChanged: (v) => setState(() => eventType = v!),
                  ),
                  gap(),
                  TextField(
                    controller: guests,
                    keyboardType: TextInputType.number,
                    decoration: field('Expected guests'),
                  ),
                  gap(),
                  ListTile(
                    title: Text('Event date: ${humanDate(eventDate)}'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final selected = await showDatePicker(
                        context: context,
                        initialDate: eventDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (selected != null) {
                        setState(() => eventDate = selected);
                      }
                    },
                  ),
                  gap(),
                ],
                const Text(
                  'Quotation lines',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                for (var i = 0; i < lines.length; i++)
                  Card(
                    child: ListTile(
                      title: Text(lines[i].title),
                      subtitle: Text(
                        '${lines[i].quantity} × ${pkr(lines[i].unitPaisa)}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(pkr(lines[i].total)),
                          IconButton(
                            onPressed: () => setState(() => lines.removeAt(i)),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: addLine,
                  icon: const Icon(Icons.add),
                  label: const Text('Add menu item or package'),
                ),
                gap(),
                TextField(
                  controller: extras,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: field('Service / delivery extras (PKR)'),
                  onChanged: (_) => setState(() {}),
                ),
                gap(),
                TextField(
                  controller: discount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: field('Discount (PKR)'),
                  onChanged: (_) => setState(() {}),
                ),
                gap(),
                TextField(
                  controller: notes,
                  decoration: field('Terms, notes and exclusions'),
                  maxLines: 3,
                ),
                gap(),
                Text('Subtotal: ${pkr(subtotal)}'),
                Text(
                  'Estimated total: ${pkr(subtotal + (((double.tryParse(extras.text) ?? 0) * 100).round()) - (((double.tryParse(discount.text) ?? 0) * 100).round()))}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                gap(),
                FilledButton.icon(
                  onPressed: saving || customerId == null ? null : save,
                  icon: const Icon(Icons.save),
                  label: Text(
                    saving
                        ? 'Saving…'
                        : widget.existing == null
                        ? 'Save quotation'
                        : 'Save revision',
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> save() async {
    setState(() => saving = true);
    try {
      final extra = parsePaisa(extras.text);
      final off = parsePaisa(discount.text);
      QuoteMath(lines, extraPaisa: extra, discountPaisa: off).validate();
      if (widget.existing == null) {
        final count = int.tryParse(guests.text);
        if (count == null || count < 1) {
          throw const FormatException('Invalid guest count');
        }
        await sales().createQuote(
          customerId: customerId!,
          eventType: eventType,
          guests: count,
          eventDate: eventDate,
          lines: lines,
          extraPaisa: extra,
          discountPaisa: off,
          notes: notes.text,
        );
      } else {
        await sales().reviseQuote(
          widget.existing!,
          lines,
          extraPaisa: extra,
          discountPaisa: off,
          notes: notes.text,
        );
      }
      if (mounted) Get.back();
    } catch (e) {
      errorNotice(e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

void quoteDetails(SalesRecord quote) {
  Get.to(() => QuoteDetailsPage(quoteId: quote.id));
}

class QuoteDetailsPage extends StatelessWidget {
  final String quoteId;
  final int? revisionNumber;
  const QuoteDetailsPage({
    super.key,
    required this.quoteId,
    this.revisionNumber,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        revisionNumber == null
            ? 'Quotation details'
            : 'Saved revision $revisionNumber',
      ),
    ),
    body: StreamBuilder<DocumentSnapshot<Json>>(
      stream: sales().collection('quotations').doc(quoteId).snapshots(),
      builder: (ctx, snap) {
        if (snap.hasError) return Center(child: Text('${snap.error}'));
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snap.data!.exists) {
          return const Center(child: Text('Quotation unavailable'));
        }
        final r = SalesRecord(quoteId, snap.data!.data()!);
        final currentRevision = r.number('revision');
        final selectedRevision = revisionNumber ?? currentRevision;
        final isHistorical = selectedRevision != currentRevision;
        return FutureBuilder<SalesRecord>(
          future: sales().revision(quoteId, selectedRevision),
          builder: (ctx, rev) {
            if (rev.hasError) return Center(child: Text('${rev.error}'));
            if (!rev.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final lines = (rev.data!.data['lines'] as List)
                .map(
                  (v) =>
                      QuoteLine.fromJson(Map<String, dynamic>.from(v as Map)),
                )
                .toList();
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '${r.str('eventType')} · ${isHistorical ? 'ARCHIVED REVISION' : r.str('status').toUpperCase()}',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                Text(
                  'Guests: ${r.number('guests')} | Event: ${humanDate(r.date('eventDate'))}',
                ),
                Text(
                  'Revision: $selectedRevision${isHistorical ? ' (read-only)' : ''}',
                ),
                gap(),
                for (final l in lines)
                  ListTile(
                    title: Text(l.title),
                    subtitle: Text('${l.quantity} × ${pkr(l.unitPaisa)}'),
                    trailing: Text(pkr(l.total)),
                  ),
                const Divider(),
                ListTile(
                  title: const Text('Extras'),
                  trailing: Text(pkr(rev.data!.number('extraPaisa'))),
                ),
                ListTile(
                  title: const Text('Discount'),
                  trailing: Text(pkr(rev.data!.number('discountPaisa'))),
                ),
                ListTile(
                  title: const Text(
                    'Total',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  trailing: Text(
                    pkr(rev.data!.number('totalPaisa')),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (rev.data!.str('notes').isNotEmpty)
                  Text('Notes: ${rev.data!.str('notes')}'),
                gap(),
                FilledButton.icon(
                  onPressed: () async {
                    try {
                      await exportQuotation(
                        Get.find<SessionController>().business.value!.name,
                        r,
                        rev.data!,
                        lines,
                      );
                    } catch (e) {
                      errorNotice(e);
                    }
                  },
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Preview, print or share PDF'),
                ),
                if (revisionNumber == null) ...[
                  gap(),
                  OutlinedButton.icon(
                    onPressed: () => Get.to(
                      () => QuoteRevisionHistoryPage(quoteId: quoteId),
                    ),
                    icon: const Icon(Icons.history),
                    label: const Text('View revision history'),
                  ),
                ],
                if (revisionNumber == null && salesEditor()) ...[
                  gap(),
                  if (['draft', 'sent'].contains(r.str('status')))
                    OutlinedButton(
                      onPressed: () => Get.to(() => QuoteEditor(existing: r)),
                      child: const Text('Create new revision'),
                    ),
                  if (r.str('status') == 'draft')
                    OutlinedButton(
                      onPressed: () =>
                          execute(() => sales().markQuote(quoteId, 'sent')),
                      child: const Text('Mark sent'),
                    ),
                  if (r.str('status') == 'sent')
                    OutlinedButton(
                      onPressed: () =>
                          execute(() => sales().markQuote(quoteId, 'accepted')),
                      child: const Text('Mark accepted (not booked yet)'),
                    ),
                  if (['draft', 'sent'].contains(r.str('status')))
                    TextButton(
                      onPressed: () =>
                          execute(() => sales().markQuote(quoteId, 'declined')),
                      child: const Text('Mark declined'),
                    ),
                ],
              ],
            );
          },
        );
      },
    ),
  );
}

/// Saved quotation revisions are immutable; the current quotation header is
/// intentionally not duplicated in the main quotation list.
class QuoteRevisionHistoryPage extends StatelessWidget {
  final String quoteId;
  const QuoteRevisionHistoryPage({super.key, required this.quoteId});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Revision history')),
    body: StreamBuilder<QuerySnapshot<Json>>(
      stream: sales()
          .collection('quotations')
          .doc(quoteId)
          .collection('revisions')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Could not load revision history: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final versions =
            snapshot.data!.docs
                .map((doc) => SalesRecord(doc.id, doc.data()))
                .toList()
              ..sort(
                (a, b) => b.number('revision').compareTo(a.number('revision')),
              );
        if (versions.isEmpty) {
          return const Center(child: Text('No saved revisions found.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: versions.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final version = versions[index];
            final n = version.number('revision');
            return Card(
              child: ListTile(
                leading: const Icon(Icons.history),
                title: Text('Revision $n'),
                subtitle: Text(
                  'Saved: ${humanDate(version.date('createdAt'))}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(pkr(version.number('totalPaisa'))),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () => Get.to(
                  () => QuoteDetailsPage(quoteId: quoteId, revisionNumber: n),
                ),
              ),
            );
          },
        );
      },
    ),
  );
}
