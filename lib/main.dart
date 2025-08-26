import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/* ======================= MODELS ======================= */

enum OrderStatus { open, wip, done }
enum BottleSize { ml500, l1 }
String sizeLabel(BottleSize s) => s == BottleSize.ml500 ? "500 ml" : "1 L";

class Order {
  String id, customer;
  int qty500, qty1000;
  OrderStatus status;
  DateTime date;
  Order({
    required this.id,
    required this.customer,
    required this.qty500,
    required this.qty1000,
    required this.status,
    required this.date,
  });
  int get totalQty => qty500 + qty1000;
  Map<String, dynamic> toJson() => {
        'id': id,
        'customer': customer,
        'qty500': qty500,
        'qty1000': qty1000,
        'status': status.name,
        'date': date.toIso8601String(),
      };
  static Order fromJson(Map<String, dynamic> j) => Order(
        id: j['id'],
        customer: j['customer'],
        qty500: j['qty500'],
        qty1000: j['qty1000'],
        status: OrderStatus.values.firstWhere((e) => e.name == (j['status'] as String)),
        date: DateTime.parse(j['date']),
      );
}

class StockItem {
  String name, uom;
  double qty, unitCost;
  StockItem({required this.name, required this.uom, required this.qty, this.unitCost = 0});
  Map<String, dynamic> toJson() => {'name': name, 'uom': uom, 'qty': qty, 'unitCost': unitCost};
  static StockItem fromJson(Map<String, dynamic> j) => StockItem(
        name: j['name'],
        uom: j['uom'],
        qty: (j['qty'] as num).toDouble(),
        unitCost: (j['unitCost'] as num?)?.toDouble() ?? 0,
      );
}

class CostPart {
  String name;
  double value;
  CostPart(this.name, this.value);
  Map<String, dynamic> toJson() => {'name': name, 'value': value};
  static CostPart fromJson(Map<String, dynamic> j) => CostPart(j['name'], (j['value'] as num).toDouble());
}

class Txn {
  DateTime date;
  bool isCredit;
  double amount;
  String note;
  Txn({required this.date, required this.isCredit, required this.amount, required this.note});
  Map<String, dynamic> toJson() => {'date': date.toIso8601String(), 'isCredit': isCredit, 'amount': amount, 'note': note};
  static Txn fromJson(Map<String, dynamic> j) =>
      Txn(date: DateTime.parse(j['date']), isCredit: j['isCredit'], amount: (j['amount'] as num).toDouble(), note: j['note']);
}

class InvRow {
  String desc, hsn;
  BottleSize size;
  double qty, rate;
  InvRow(this.desc, this.hsn, this.size, this.qty, this.rate);
  Map<String, dynamic> toJson() => {'desc': desc, 'hsn': hsn, 'size': size.name, 'qty': qty, 'rate': rate};
  static InvRow fromJson(Map<String, dynamic> j) => InvRow(
      j['desc'], j['hsn'], BottleSize.values.firstWhere((e) => e.name == j['size']), (j['qty'] as num).toDouble(), (j['rate'] as num).toDouble());
}

class InvoiceDoc {
  String number, buyer, gstin, address;
  DateTime date;
  List<InvRow> rows;
  double cgst, sgst, subtotal, total;
  InvoiceDoc({
    required this.number,
    required this.buyer,
    required this.gstin,
    required this.address,
    required this.date,
    required this.rows,
    required this.cgst,
    required this.sgst,
    required this.subtotal,
    required this.total,
  });
  Map<String, dynamic> toJson() => {
        'number': number,
        'buyer': buyer,
        'gstin': gstin,
        'address': address,
        'date': date.toIso8601String(),
        'rows': rows.map((e) => e.toJson()).toList(),
        'cgst': cgst,
        'sgst': sgst,
        'subtotal': subtotal,
        'total': total,
      };
  static InvoiceDoc fromJson(Map<String, dynamic> j) => InvoiceDoc(
        number: j['number'],
        buyer: j['buyer'],
        gstin: j['gstin'],
        address: j['address'],
        date: DateTime.parse(j['date']),
        rows: (j['rows'] as List).map((e) => InvRow.fromJson(e)).toList(),
        cgst: (j['cgst'] as num).toDouble(),
        sgst: (j['sgst'] as num).toDouble(),
        subtotal: (j['subtotal'] as num).toDouble(),
        total: (j['total'] as num).toDouble(),
      );
}

/* ======================= APP STATE ======================= */

class AppState extends ChangeNotifier {
  static const _key = 'sara_state_v2';

  List<Order> orders = [];
  List<StockItem> raw = [];
  List<StockItem> finished = [
    StockItem(name: "Water Bottle 500 ml", uom: "pcs", qty: 0),
    StockItem(name: "Water Bottle 1 L", uom: "pcs", qty: 0),
  ];
  List<CostPart> costParts = [];
  List<Txn> txns = [];
  List<InvRow> lastInvoiceRows = [InvRow("Water Bottle", "373527", BottleSize.l1, 1, 10)];
  List<InvoiceDoc> invoices = [];

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final s = sp.getString(_key);
    if (s == null) {
      orders = [
        Order(id: "ORD-1001", customer: "Sanjay Traders", qty500: 500, qty1000: 0, status: OrderStatus.open, date: DateTime(2024, 7, 1)),
        Order(id: "ORD-1002", customer: "Akash Enterprises", qty500: 0, qty1000: 750, status: OrderStatus.done, date: DateTime(2024, 7, 1)),
        Order(id: "ORD-1003", customer: "Mehta Distributors", qty500: 250, qty1000: 0, status: OrderStatus.wip, date: DateTime(2024, 7, 2)),
      ];
      raw = [
        StockItem(name: "Preforms", uom: "pcs", qty: 5000, unitCost: 5.2),
        StockItem(name: "Caps", uom: "pcs", qty: 5000, unitCost: 0.8),
        StockItem(name: "Labels", uom: "pcs", qty: 5000, unitCost: 0.5),
      ];
      costParts = [CostPart("Preform", 5.2), CostPart("Cap", 0.8), CostPart("Label", 0.5), CostPart("Utilities", 0.35), CostPart("Labour", 0.5)];
      txns = [Txn(date: DateTime.now(), isCredit: true, amount: 1000, note: "Opening")];
      await save();
      return;
    }
    final j = jsonDecode(s) as Map<String, dynamic>;
    orders = (j['orders'] as List).map((e) => Order.fromJson(e)).toList();
    raw = (j['raw'] as List).map((e) => StockItem.fromJson(e)).toList();
    finished = (j['finished'] as List).map((e) => StockItem.fromJson(e)).toList();
    costParts = (j['costParts'] as List).map((e) => CostPart.fromJson(e)).toList();
    txns = (j['txns'] as List).map((e) => Txn.fromJson(e)).toList();
    lastInvoiceRows = (j['lastInvoiceRows'] as List).map((e) => InvRow.fromJson(e)).toList();
    invoices = (j['invoices'] as List? ?? []).map((e) => InvoiceDoc.fromJson(e)).toList();
    notifyListeners();
  }

  Future<void> save() async {
    final sp = await SharedPreferences.getInstance();
    final j = {
      'orders': orders.map((e) => e.toJson()).toList(),
      'raw': raw.map((e) => e.toJson()).toList(),
      'finished': finished.map((e) => e.toJson()).toList(),
      'costParts': costParts.map((e) => e.toJson()).toList(),
      'txns': txns.map((e) => e.toJson()).toList(),
      'lastInvoiceRows': lastInvoiceRows.map((e) => e.toJson()).toList(),
      'invoices': invoices.map((e) => e.toJson()).toList(),
    };
    await sp.setString(_key, jsonEncode(j));
  }

  int countStatus(OrderStatus st) => orders.where((o) => o.status == st).length;
  int qtyByStatus(OrderStatus st) => orders.where((o) => o.status == st).fold(0, (s, o) => s + o.totalQty);
  int qty500ByStatus(OrderStatus st) => orders.where((o) => o.status == st).fold(0, (s, o) => s + o.qty500);
  int qty1000ByStatus(OrderStatus st) => orders.where((o) => o.status == st).fold(0, (s, o) => s + o.qty1000);

  void addOrder(String customer, int q500, int q1000) {
    final next = 1000 + orders.length + 1;
    orders.insert(0, Order(id: "ORD-$next", customer: customer, qty500: q500, qty1000: q1000, status: OrderStatus.open, date: DateTime.now()));
    save();
    notifyListeners();
  }

  void updateOrderStatus(Order o, OrderStatus ns) {
    if (o.status != OrderStatus.done && ns == OrderStatus.done) {
      final total = o.totalQty;
      _consumeRaw("Preforms", total);
      _consumeRaw("Caps", total);
      _consumeRaw("Labels", total);
      _addFinished("Water Bottle 500 ml", o.qty500);
      _addFinished("Water Bottle 1 L", o.qty1000);
    }
    if (o.status == OrderStatus.done && ns != OrderStatus.done) {
      final total = o.totalQty;
      _addRaw("Preforms", total);
      _addRaw("Caps", total);
      _addRaw("Labels", total);
      _consumeFinished("Water Bottle 500 ml", o.qty500);
      _consumeFinished("Water Bottle 1 L", o.qty1000);
    }
    o.status = ns;
    save();
    notifyListeners();
  }

  void inwardRaw(String name, String uom, double qty, {double? unitCost}) {
    final i = raw.indexWhere((e) => e.name.toLowerCase() == name.toLowerCase());
    if (i >= 0) {
      raw[i].qty += qty;
      if (unitCost != null) raw[i].unitCost = unitCost;
    } else {
      raw.add(StockItem(name: name, uom: uom, qty: qty, unitCost: unitCost ?? 0));
    }
    save();
    notifyListeners();
  }

  void addTxn(bool credit, double amount, String note) {
    txns.insert(0, Txn(date: DateTime.now(), isCredit: credit, amount: amount, note: note));
    save();
    notifyListeners();
  }

  void addCost(String name, double value) {
    costParts.add(CostPart(name, value));
    save();
    notifyListeners();
  }

  void updateCost(int i, String name, double value) {
    costParts[i].name = name;
    costParts[i].value = value;
    save();
    notifyListeners();
  }

  void deleteCost(int i) {
    costParts.removeAt(i);
    save();
    notifyListeners();
  }

  double get unitCostTotal => costParts.fold(0.0, (s, c) => s + c.value);

  void storeInvoiceRows(List<InvRow> r) {
    lastInvoiceRows = r;
    save();
  }

  void saveInvoice(InvoiceDoc doc) {
    final i = invoices.indexWhere((e) => e.number == doc.number);
    if (i >= 0) {
      invoices[i] = doc;
    } else {
      invoices.insert(0, doc);
    }
    save();
    notifyListeners();
  }

  void _consumeRaw(String name, int q) {
    final i = raw.indexWhere((e) => e.name.toLowerCase() == name.toLowerCase());
    if (i >= 0) raw[i].qty = (raw[i].qty - q).clamp(0, double.infinity);
  }

  void _addRaw(String name, int q) {
    final i = raw.indexWhere((e) => e.name.toLowerCase() == name.toLowerCase());
    if (i >= 0) {
      raw[i].qty += q.toDouble();
    } else {
      raw.add(StockItem(name: name, uom: "pcs", qty: q.toDouble()));
    }
  }

  void _addFinished(String name, int q) {
    final i = finished.indexWhere((e) => e.name.toLowerCase() == name.toLowerCase());
    if (i >= 0) {
      finished[i].qty += q.toDouble();
    } else {
      finished.add(StockItem(name: name, uom: "pcs", qty: q.toDouble()));
    }
  }

  void _consumeFinished(String name, int q) {
    final i = finished.indexWhere((e) => e.name.toLowerCase() == name.toLowerCase());
    if (i >= 0) {
      finished[i].qty = (finished[i].qty - q).clamp(0, double.infinity);
    }
  }
}

/* ======================= APP ROOT ======================= */

void main() => runApp(const RootApp());

class RootApp extends StatefulWidget {
  const RootApp({super.key});
  @override
  State<RootApp> createState() => _RootAppState();
}

class _RootAppState extends State<RootApp> {
  final AppState state = AppState();
  bool ready = false;
  @override
  void initState() {
    super.initState();
    state.load().then((_) => setState(() => ready = true));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: "Sara Industries – GST",
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B74B5)),
        ),
        home: ready
            ? LoginPage(state: state)
            : const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
    );
  }
}

/* ======================= LOGIN ======================= */

class LoginPage extends StatefulWidget {
  final AppState state;
  const LoginPage({super.key, required this.state});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final u = TextEditingController(), p = TextEditingController();
  String? err;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text("AQUASAAR",
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 1.3)),
                  const SizedBox(height: 8),
                  const Text("Sara Industries", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  TextField(controller: u, decoration: const InputDecoration(labelText: "Username")),
                  const SizedBox(height: 8),
                  TextField(controller: p, obscureText: true, decoration: const InputDecoration(labelText: "Password")),
                  if (err != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(err!, style: const TextStyle(color: Colors.red))),
                  const SizedBox(height: 10),
                  FilledButton(
                      onPressed: () {
                        if (u.text.trim() == "admin" && p.text == "1234") {
                          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => Dashboard(state: widget.state)));
                        } else {
                          setState(() => err = "Invalid (use admin / 1234)");
                        }
                      },
                      child: const Text("Login")),
                ]),
              ),
            ),
          ),
        ),
      );
}

/* =================== DASHBOARD + TABS =================== */

class Dashboard extends StatefulWidget {
  final AppState state;
  const Dashboard({super.key, required this.state});
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  int idx = 0;
  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final pages = [HomeTab(s: s), InvoiceTab(s: s), OrdersTab(s: s), StockTab(s: s), MaterialsTab(s: s), AccountsTab(s: s)];
    return Scaffold(
      appBar: AppBar(title: const Text("SARA INDUSTRIES")),
      body: pages[idx],
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (v) => setState(() => idx = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: "Home"),
          NavigationDestination(icon: Icon(Icons.receipt_long), label: "Invoice"),
          NavigationDestination(icon: Icon(Icons.list_alt), label: "Orders"),
          NavigationDestination(icon: Icon(Icons.inventory_2), label: "Stock"),
          NavigationDestination(icon: Icon(Icons.precision_manufacturing), label: "Materials"),
          NavigationDestination(icon: Icon(Icons.account_balance), label: "Accounts"),
        ],
      ),
    );
  }
}

/* ======================= HOME ======================= */

class HomeTab extends StatelessWidget {
  final AppState s;
  const HomeTab({super.key, required this.s});
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: s,
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF0B74B5), borderRadius: BorderRadius.circular(14)),
            child: Row(children: const [
              Text("AQUASAAR",
                  style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
              Spacer(),
              Icon(Icons.water_drop, color: Colors.white),
            ]),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.orange.shade700, borderRadius: BorderRadius.circular(14)),
            child: Wrap(spacing: 16, runSpacing: 8, children: [
              _chip("Open", s.countStatus(OrderStatus.open), s.qtyByStatus(OrderStatus.open), Icons.water_drop),
              _chip("In Progress", s.countStatus(OrderStatus.wip), s.qtyByStatus(OrderStatus.wip), Icons.local_shipping),
              _chip("Completed", s.countStatus(OrderStatus.done), s.qtyByStatus(OrderStatus.done), Icons.verified),
            ]),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _miniStat("500 ml", "Open ${s.qty500ByStatus(OrderStatus.open)} • WIP ${s.qty500ByStatus(OrderStatus.wip)} • Done ${s.qty500ByStatus(OrderStatus.done)}")),
            const SizedBox(width: 8),
            Expanded(child: _miniStat("1 L", "Open ${s.qty1000ByStatus(OrderStatus.open)} • WIP ${s.qty1000ByStatus(OrderStatus.wip)} • Done ${s.qty1000ByStatus(OrderStatus.done)}")),
          ]),
          const SizedBox(height: 12),
          for (final o in s.orders.take(3))
            Card(
                child: ListTile(
              title: Text("${o.customer}  •  ${o.id}", style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text("${o.qty500}×500ml, ${o.qty1000}×1L  •  ${DateFormat('dd/MM/yyyy').format(o.date)}"),
              trailing: Chip(
                label: Text(o.status == OrderStatus.open ? "Open" : o.status == OrderStatus.wip ? "In Progress" : "Completed",
                    style: const TextStyle(color: Colors.white)),
                backgroundColor: o.status == OrderStatus.open
                    ? Colors.blue
                    : o.status == OrderStatus.wip
                        ? Colors.orange
                        : Colors.green,
              ),
            )),
        ]),
      ),
    );
  }

  Widget _chip(String label, int orders, int qty, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Colors.white.withOpacity(.12), borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            Text("$orders orders • $qty bottles", style: const TextStyle(color: Colors.white, fontSize: 12)),
          ]),
        ]),
      );

  Widget _miniStat(String title, String line) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 4),
          Text(line, style: const TextStyle(fontSize: 12)),
        ]),
      );
}

/* ======================= INVOICE (vertical + Save + PDF) ======================= */

class InvoiceTab extends StatefulWidget {
  final AppState s;
  const InvoiceTab({super.key, required this.s});
  @override
  State<InvoiceTab> createState() => _InvoiceTabState();
}

class _InvoiceTabState extends State<InvoiceTab> {
  late List<InvRow> rows;
  final cgst = TextEditingController(text: "9");
  final sgst = TextEditingController(text: "9");
  final buyer = TextEditingController(text: "Test Depot");
  final gstin = TextEditingController(text: "27ABCDE1234F1Z5");
  final addr = TextEditingController(text: "KGN layout, Ramtek");
  final inv = TextEditingController(text: "S/2025/001");

  @override
  void initState() {
    super.initState();
    rows = widget.s.lastInvoiceRows.map((e) => InvRow(e.desc, e.hsn, e.size, e.qty, e.rate)).toList();
  }

  void _persist() => widget.s.storeInvoiceRows(rows);

  double get sub => rows.fold(0.0, (s, r) => s + r.qty * r.rate);
  double get cg => sub * (double.tryParse(cgst.text) ?? 0) / 100;
  double get sg => sub * (double.tryParse(sgst.text) ?? 0) / 100;
  double get tot => sub + cg + sg;

  void _saveInvoice() {
    final doc = InvoiceDoc(
      number: inv.text.trim(),
      buyer: buyer.text.trim(),
      gstin: gstin.text.trim(),
      address: addr.text.trim(),
      date: DateTime.now(),
      rows: rows,
      cgst: double.tryParse(cgst.text) ?? 0,
      sgst: double.tryParse(sgst.text) ?? 0,
      subtotal: sub,
      total: tot,
    );
    widget.s.saveInvoice(doc);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invoice saved")));
  }

  Future<void> _sharePdf() async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        build: (c) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text("SARA INDUSTRIES — TAX INVOICE", style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text("Invoice: ${inv.text}"),
          pw.Text("Date: ${DateFormat('dd-MM-yyyy').format(DateTime.now())}"),
          pw.Text("Buyer: ${buyer.text}"),
          pw.Text("GSTIN: ${gstin.text}"),
          pw.Text("Address: ${addr.text}"),
          pw.SizedBox(height: 10),
          pw.Table.fromTextArray(
            headers: ["Description", "Size", "HSN", "Qty", "Rate", "Amount"],
            data: rows
                .map((r) => [
                      r.desc,
                      sizeLabel(r.size),
                      r.hsn,
                      r.qty.toStringAsFixed(2),
                      r.rate.toStringAsFixed(2),
                      (r.qty * r.rate).toStringAsFixed(2),
                    ])
                .toList(),
            cellAlignment: pw.Alignment.centerLeft,
          ),
          pw.SizedBox(height: 10),
          pw.Text("Subtotal: ₹${sub.toStringAsFixed(2)}"),
          pw.Text("CGST (${cgst.text}%): ₹${cg.toStringAsFixed(2)}"),
          pw.Text("SGST (${sgst.text}%): ₹${sg.toStringAsFixed(2)}"),
          pw.Text("Grand Total: ₹${tot.toStringAsFixed(2)}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        ]),
      ),
    );
    await Printing.sharePdf(bytes: await pdf.save(), filename: "${inv.text.replaceAll('/', '-')}.pdf");
  }

  @override
  Widget build(BuildContext context) {
    const txt = TextStyle(fontSize: 16);

    return Stack(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 160),
        child: ListView(children: [
          Row(children: [
            Expanded(child: TextField(controller: inv, decoration: const InputDecoration(labelText: "Invoice No"))),
            const SizedBox(width: 10),
            Expanded(
                child: TextField(
              readOnly: true,
              decoration: InputDecoration(labelText: "Date", hintText: DateFormat('dd-MM-yyyy').format(DateTime.now())),
            )),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: buyer, decoration: const InputDecoration(labelText: "Buyer Name"))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: gstin, decoration: const InputDecoration(labelText: "Buyer GSTIN"))),
          ]),
          const SizedBox(height: 8),
          TextField(controller: addr, decoration: const InputDecoration(labelText: "Buyer Address")),
          const SizedBox(height: 14),

          for (int i = 0; i < rows.length; i++)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  TextField(
                    controller: TextEditingController(text: rows[i].desc),
                    onChanged: (v) {
                      rows[i].desc = v;
                      _persist();
                    },
                    style: txt,
                    decoration: const InputDecoration(labelText: "Description"),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<BottleSize>(
                    value: rows[i].size,
                    items: const [
                      DropdownMenuItem(value: BottleSize.ml500, child: Text("500 ml")),
                      DropdownMenuItem(value: BottleSize.l1, child: Text("1 L")),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        rows[i].size = v;
                        _persist();
                        setState(() {});
                      }
                    },
                    decoration: const InputDecoration(labelText: "Size"),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: TextEditingController(text: rows[i].hsn),
                    onChanged: (v) {
                      rows[i].hsn = v;
                      _persist();
                    },
                    style: txt,
                    decoration: const InputDecoration(labelText: "HSN"),
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(
                        child: TextField(
                      controller: TextEditingController(text: rows[i].qty.toStringAsFixed(2)),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (v) {
                        rows[i].qty = double.tryParse(v) ?? 0;
                        _persist();
                        setState(() {});
                      },
                      decoration: const InputDecoration(labelText: "Quantity"),
                    )),
                    const SizedBox(width: 10),
                    Expanded(
                        child: TextField(
                      controller: TextEditingController(text: rows[i].rate.toStringAsFixed(2)),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (v) {
                        rows[i].rate = double.tryParse(v) ?? 0;
                        _persist();
                        setState(() {});
                      },
                      decoration: const InputDecoration(labelText: "Rate"),
                    )),
                  ]),
                  const SizedBox(height: 6),
                  Align(
                      alignment: Alignment.centerRight,
                      child: Text("Amount: ₹${(rows[i].qty * rows[i].rate).toStringAsFixed(2)}",
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                  Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                          onPressed: () {
                            setState(() => rows.removeAt(i));
                            _persist();
                          },
                          icon: const Icon(Icons.delete_outline))),
                ]),
              ),
            ),

          Row(children: [
            Expanded(
                child: TextField(
              controller: cgst,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "CGST %"),
              onChanged: (_) => setState(() {}),
            )),
            const SizedBox(width: 10),
            Expanded(
                child: TextField(
              controller: sgst,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "SGST %"),
              onChanged: (_) => setState(() {}),
            )),
          ]),
          const SizedBox(height: 8),
          Card(
              child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("Subtotal: ₹${sub.toStringAsFixed(2)}"),
              Text("CGST (${cgst.text}%): ₹${cg.toStringAsFixed(2)}"),
              Text("SGST (${sgst.text}%): ₹${sg.toStringAsFixed(2)}"),
              const SizedBox(height: 4),
              Text("Grand Total: ₹${tot.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          )),
        ]),
      ),

      Positioned(
        bottom: 12,
        right: 12,
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          FilledButton.icon(onPressed: _saveInvoice, icon: const Icon(Icons.save), label: const Text("Save")),
          const SizedBox(height: 8),
          FilledButton.icon(onPressed: _sharePdf, icon: const Icon(Icons.picture_as_pdf), label: const Text("Share PDF")),
          const SizedBox(height: 8),
          FilledButton.icon(
              onPressed: () {
                setState(() => rows.add(InvRow("Water Bottle", "373527", BottleSize.l1, 1, 10)));
                _persist();
              },
              icon: const Icon(Icons.add),
              label: const Text("Add item")),
        ]),
      ),
    ]);
  }
}

/* ======================= ORDERS ======================= */

class OrdersTab extends StatelessWidget {
  final AppState s;
  const OrdersTab({super.key, required this.s});
  @override
  Widget build(BuildContext context) {
    final cust = TextEditingController();
    final q500 = TextEditingController(text: "0");
    final q1000 = TextEditingController(text: "100");

    return AnimatedBuilder(
      animation: s,
      builder: (context, _) => Scaffold(
        floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                        title: const Text("New Order"),
                        content: Column(mainAxisSize: MainAxisSize.min, children: [
                          TextField(controller: cust, decoration: const InputDecoration(labelText: "Customer")),
                          const SizedBox(height: 8),
                          TextField(controller: q500, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Qty (500 ml)")),
                          const SizedBox(height: 8),
                          TextField(controller: q1000, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Qty (1 L)")),
                        ]),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                          FilledButton(
                              onPressed: () {
                                final a = int.tryParse(q500.text.trim()) ?? 0;
                                final b = int.tryParse(q1000.text.trim()) ?? 0;
                                if (cust.text.trim().isNotEmpty && (a > 0 || b > 0)) {
                                  s.addOrder(cust.text.trim(), a, b);
                                  Navigator.pop(context);
                                }
                              },
                              child: const Text("Add")),
                        ],
                      ));
            },
            icon: const Icon(Icons.add),
            label: const Text("New Order")),
        body: ListView.separated(
          padding: const EdgeInsets.all(12),
          itemBuilder: (_, i) {
            final o = s.orders[i];
            return Card(
              child: ListTile(
                title: Text("${o.customer}  •  ${o.id}"),
                subtitle: Text("500ml: ${o.qty500} • 1L: ${o.qty1000} • ${DateFormat('dd-MM-yyyy').format(o.date)}"),
                trailing: DropdownButton<OrderStatus>(
                  value: o.status,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: OrderStatus.open, child: Text("Open")),
                    DropdownMenuItem(value: OrderStatus.wip, child: Text("In Progress")),
                    DropdownMenuItem(value: OrderStatus.done, child: Text("Completed")),
                  ],
                  onChanged: (v) {
                    if (v != null) s.updateOrderStatus(o, v);
                  },
                ),
              ),
            );
          },
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemCount: s.orders.length,
        ),
      ),
    );
  }
}

/* ======================= STOCK ======================= */

class StockTab extends StatelessWidget {
  final AppState s;
  const StockTab({super.key, required this.s});
  @override
  Widget build(BuildContext context) {
    final name = TextEditingController();
    final uom = TextEditingController(text: "pcs");
    final qty = TextEditingController(text: "0");
    final cost = TextEditingController(text: "0");
    return AnimatedBuilder(
      animation: s,
      builder: (context, _) => Scaffold(
        floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                        title: const Text("Inward Raw Material"),
                        content: Column(mainAxisSize: MainAxisSize.min, children: [
                          TextField(controller: name, decoration: const InputDecoration(labelText: "Item name")),
                          const SizedBox(height: 8),
                          TextField(controller: uom, decoration: const InputDecoration(labelText: "UOM")),
                          const SizedBox(height: 8),
                          TextField(controller: qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Qty")),
                          const SizedBox(height: 8),
                          TextField(controller: cost, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Unit cost (₹)")),
                        ]),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                          FilledButton(
                              onPressed: () {
                                final q = double.tryParse(qty.text.trim()) ?? 0;
                                final c = double.tryParse(cost.text.trim());
                                if (name.text.trim().isNotEmpty && q > 0) {
                                  s.inwardRaw(name.text.trim(), uom.text.trim().isEmpty ? "pcs" : uom.text.trim(), q, unitCost: c);
                                  Navigator.pop(context);
                                }
                              },
                              child: const Text("Add")),
                        ],
                      ));
            },
            icon: const Icon(Icons.add),
            label: const Text("Add Inward")),
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            const Text("Raw Materials", style: TextStyle(fontWeight: FontWeight.w600)),
            Expanded(
                child: ListView(
                    children: s.raw
                        .map((r) => ListTile(
                              title: Text(r.name),
                              subtitle: Text("Qty: ${r.qty.toStringAsFixed(0)} ${r.uom}"),
                              trailing: r.unitCost > 0 ? Text("₹${r.unitCost}") : const SizedBox(),
                            ))
                        .toList())),
            const Divider(),
            const Text("Finished Goods", style: TextStyle(fontWeight: FontWeight.w600)),
            Expanded(
                child: ListView(
                    children: s.finished
                        .map((f) => ListTile(
                              title: Text(f.name),
                              subtitle: Text("Qty: ${f.qty.toStringAsFixed(0)} ${f.uom}"),
                            ))
                        .toList())),
          ]),
        ),
      ),
    );
  }
}

/* ======================= MATERIALS ======================= */

class MaterialsTab extends StatelessWidget {
  final AppState s;
  const MaterialsTab({super.key, required this.s});
  @override
  Widget build(BuildContext context) {
    final name = TextEditingController();
    final val = TextEditingController(text: "0");
    final cur = NumberFormat.currency(locale: "en_IN", symbol: "₹");
    return AnimatedBuilder(
      animation: s,
      builder: (context, _) => Scaffold(
        floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                        title: const Text("Add cost item"),
                        content: Column(mainAxisSize: MainAxisSize.min, children: [
                          TextField(controller: name, decoration: const InputDecoration(labelText: "Name")),
                          const SizedBox(height: 8),
                          TextField(controller: val, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Cost (₹)")),
                        ]),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                          FilledButton(
                              onPressed: () {
                                final v = double.tryParse(val.text.trim()) ?? 0;
                                if (name.text.trim().isNotEmpty) {
                                  s.addCost(name.text.trim(), v);
                                  Navigator.pop(context);
                                }
                              },
                              child: const Text("Add")),
                        ],
                      ));
            },
            icon: const Icon(Icons.add),
            label: const Text("Add Item")),
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: ListView.separated(
              itemBuilder: (_, i) {
                final cp = s.costParts[i];
                return Row(children: [
                  Expanded(
                      child: TextField(
                    controller: TextEditingController(text: cp.name),
                    decoration: const InputDecoration(labelText: "Item"),
                    onChanged: (v) => s.updateCost(i, v.trim().isEmpty ? cp.name : v.trim(), cp.value),
                  )),
                  const SizedBox(width: 8),
                  SizedBox(
                      width: 120,
                      child: TextField(
                        controller: TextEditingController(text: cp.value.toStringAsFixed(2)),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: "Cost (₹)"),
                        onChanged: (v) => s.updateCost(i, cp.name, double.tryParse(v.trim()) ?? cp.value),
                      )),
                  IconButton(onPressed: () => s.deleteCost(i), icon: const Icon(Icons.delete_outline)),
                ]);
              },
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemCount: s.costParts.length,
            )),
            Card(
                child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text("Grand Total (per bottle): ${cur.format(s.unitCostTotal)}", style: const TextStyle(fontWeight: FontWeight.w700)),
            )),
            const SizedBox(height: 70),
          ]),
        ),
      ),
    );
  }
}

/* ======================= ACCOUNTS ======================= */

class AccountsTab extends StatefulWidget {
  final AppState s;
  const AccountsTab({super.key, required this.s});
  @override
  State<AccountsTab> createState() => _AccountsTabState();
}

class _AccountsTabState extends State<AccountsTab> {
  DateTime? from, to;
  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final cur = NumberFormat.currency(locale: "en_IN", symbol: "₹");
    List<Txn> filtered = s.txns.where((t) {
      final d = DateTime(t.date.year, t.date.month, t.date.day);
      final okF = from == null || !d.isBefore(DateTime(from!.year, from!.month, from!.day));
      final okT = to == null || !d.isAfter(DateTime(to!.year, to!.month, to!.day));
      return okF && okT;
    }).toList();
    final cr = filtered.where((t) => t.isCredit).fold(0.0, (a, b) => a + b.amount);
    final dr = filtered.where((t) => !t.isCredit).fold(0.0, (a, b) => a + b.amount);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            final amt = TextEditingController(), note = TextEditingController();
            bool credit = true;
            showDialog(
                context: context,
                builder: (_) => StatefulBuilder(
                      builder: (context, setL) => AlertDialog(
                        title: const Text("Add Account Entry"),
                        content: Column(mainAxisSize: MainAxisSize.min, children: [
                          Row(children: [
                            ChoiceChip(label: const Text("Credit"), selected: credit, onSelected: (_) => setL(() => credit = true)),
                            const SizedBox(width: 8),
                            ChoiceChip(label: const Text("Debit"), selected: !credit, onSelected: (_) => setL(() => credit = false)),
                          ]),
                          const SizedBox(height: 8),
                          TextField(controller: amt, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Amount (₹)")),
                          const SizedBox(height: 8),
                          TextField(controller: note, decoration: const InputDecoration(labelText: "Description / Particular")),
                        ]),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                          FilledButton(
                              onPressed: () {
                                final a = double.tryParse(amt.text.trim()) ?? -1;
                                if (a > 0) {
                                  s.addTxn(credit, a, note.text.trim());
                                  Navigator.pop(context);
                                }
                              },
                              child: const Text("Save")),
                        ],
                      ),
                    ));
          },
          icon: const Icon(Icons.add),
          label: const Text("Add Entry")),
      body: Column(children: [
        const SizedBox(height: 8),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              Expanded(
                  child: OutlinedButton(
                      onPressed: () async {
                        final now = DateTime.now();
                        final d = await showDatePicker(
                            context: context, firstDate: DateTime(2020), lastDate: DateTime(now.year + 1), initialDate: from ?? now);
                        if (d != null) setState(() => from = d);
                      },
                      child: Text(from == null ? "From date" : DateFormat('dd-MM-yyyy').format(from!)))),
              const SizedBox(width: 8),
              Expanded(
                  child: OutlinedButton(
                      onPressed: () async {
                        final now = DateTime.now();
                        final d = await showDatePicker(
                            context: context, firstDate: DateTime(2020), lastDate: DateTime(now.year + 1), initialDate: to ?? now);
                        if (d != null) setState(() => to = d);
                      },
                      child: Text(to == null ? "To date" : DateFormat('dd-MM-yyyy').format(to!)))),
              IconButton(onPressed: () => setState(() => {from = null, to = null}), icon: const Icon(Icons.clear)),
            ])),
        Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Align(
                alignment: Alignment.centerLeft,
                child: Text("Selected: Credit ${cur.format(cr)} • Debit ${cur.format(dr)} • Net ${cur.format(cr - dr)}",
                    style: const TextStyle(fontWeight: FontWeight.w600)))),
        const Divider(height: 1),
        Expanded(
            child: ListView.separated(
          itemBuilder: (_, i) {
            final t = filtered[i];
            return ListTile(
              leading: Icon(t.isCredit ? Icons.trending_up : Icons.trending_down, color: t.isCredit ? Colors.green : Colors.red),
              title: Text("${t.isCredit ? "Credit" : "Debit"} • ${cur.format(t.amount)}"),
              subtitle: Text("${DateFormat('dd-MM-yyyy HH:mm').format(t.date)} • ${t.note}"),
            );
          },
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemCount: filtered.length,
        )),
      ]),
    );
  }
}
