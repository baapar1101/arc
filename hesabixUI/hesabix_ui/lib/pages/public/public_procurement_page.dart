import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/procurement_api.dart';

/// پاسخ تأمین‌کننده با لینک یک‌بارمصرف. شبکه عمومی تأمین‌کننده نیست.
class PublicProcurementPage extends StatefulWidget {
  final String token;

  const PublicProcurementPage({super.key, required this.token});

  @override
  State<PublicProcurementPage> createState() => _PublicProcurementPageState();
}

class _PublicProcurementPageState extends State<PublicProcurementPage> {
  final _api = ProcurementApi();
  Map<String, dynamic>? _view;
  String? _error;
  bool _loading = true;
  final _prices = <int, TextEditingController>{};
  final _delivery = TextEditingController(text: '7');
  final _payment = TextEditingController(text: '30');
  final _freight = TextEditingController(text: '0');
  final _tax = TextEditingController(text: '0');
  final _discount = TextEditingController(text: '0');
  final _warranty = TextEditingController();
  final _reference = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();

  bool get _fa => Localizations.localeOf(context).languageCode == 'fa';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _prices.values) {
      controller.dispose();
    }
    _delivery.dispose();
    _payment.dispose();
    _freight.dispose();
    _tax.dispose();
    _discount.dispose();
    _warranty.dispose();
    _reference.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final view = await _api.publicView(widget.token);
      if (!mounted) return;
      setState(() {
        _view = view;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = procurementErrorText(error);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fa = _fa;
    return Scaffold(
      appBar: AppBar(title: Text(fa ? 'پاسخ تأمین‌کننده' : 'Supplier response')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _body(),
    );
  }

  Widget _body() {
    final view = _view ?? {};
    final kind = view['kind'];
    if (kind == 'rfq') return _bid(view);
    if (kind == 'order') return _ack(view);
    return _invoice(view);
  }

  Widget _bid(Map<String, dynamic> view) {
    final lines = (view['lines'] as List? ?? []).whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('${view['title'] ?? ''} ${view['event_code'] ?? ''}', style: Theme.of(context).textTheme.titleLarge),
        Text(_fa ? 'مهلت: ${view['deadline_at'] ?? '—'}' : 'Deadline: ${view['deadline_at'] ?? '—'}'),
        for (final line in lines)
          TextField(
            controller: _prices.putIfAbsent(line['id'] as int, TextEditingController.new),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: InputDecoration(labelText: '${line['description']} × ${line['qty']}'),
          ),
        TextField(controller: _freight, decoration: InputDecoration(labelText: _fa ? 'کرایه' : 'Freight'), keyboardType: TextInputType.number),
        TextField(controller: _tax, decoration: InputDecoration(labelText: _fa ? 'مالیات' : 'Tax'), keyboardType: TextInputType.number),
        TextField(controller: _discount, decoration: InputDecoration(labelText: _fa ? 'تخفیف' : 'Discount'), keyboardType: TextInputType.number),
        TextField(controller: _warranty, decoration: InputDecoration(labelText: _fa ? 'ضمانت' : 'Warranty')),
        TextField(controller: _delivery, decoration: InputDecoration(labelText: _fa ? 'روز تحویل' : 'Delivery days'), keyboardType: TextInputType.number),
        TextField(controller: _payment, decoration: InputDecoration(labelText: _fa ? 'مهلت پرداخت' : 'Payment days'), keyboardType: TextInputType.number),
        const SizedBox(height: 12),
        FilledButton(onPressed: () => _submitBid(lines), child: Text(_fa ? 'ثبت پیشنهاد' : 'Submit bid')),
      ],
    );
  }

  Future<void> _submitBid(List<Map<String, dynamic>> lines) async {
    if (lines.isEmpty || lines.any((line) => (_prices[line['id']]?.text.trim().isEmpty ?? true))) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_fa ? 'برای هر قلم قیمت لازم است.' : 'Each line needs a price.')));
      return;
    }
    try {
      await _api.publicBid(widget.token, {
        'delivery_days': int.tryParse(_delivery.text) ?? 0,
        'payment_days': int.tryParse(_payment.text) ?? 0,
        'freight': num.tryParse(_freight.text) ?? 0,
        'tax': num.tryParse(_tax.text) ?? 0,
        'discount': num.tryParse(_discount.text) ?? 0,
        if (_warranty.text.trim().isNotEmpty) 'warranty': _warranty.text.trim(),
        'lines': [
          for (final line in lines)
            {'sourcing_line_id': line['id'], 'unit_price': num.parse(_prices[line['id']]!.text)}
        ],
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_fa ? 'پیشنهاد ثبت شد.' : 'Bid saved.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(procurementErrorText(error))));
    }
  }

  Widget _ack(Map<String, dynamic> view) {
    final lines = (view['lines'] as List? ?? []).whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
    final acknowledged = view['acknowledged_at'];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('${view['code']}', style: Theme.of(context).textTheme.titleLarge),
        Text(_fa ? 'تحویل: ${view['delivery_date'] ?? '—'}' : 'Delivery: ${view['delivery_date'] ?? '—'}'),
        if (acknowledged != null) Text(_fa ? 'قبلاً در $acknowledged تأیید شده است.' : 'Already acknowledged at $acknowledged.'),
        for (final line in lines)
          ListTile(
            title: Text('${line['description']}'),
            subtitle: Text(_fa ? 'مقدار ${line['qty']} — قیمت ${line['unit_price']}' : 'Qty ${line['qty']} — price ${line['unit_price']}'),
          ),
        const SizedBox(height: 12),
        FilledButton(
            onPressed: () async {
              try {
                await _api.publicAck(widget.token);
                await _load();
              } catch (error) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(procurementErrorText(error))));
              }
            },
            child: Text(_fa ? 'رؤیت سفارش را تأیید می‌کنم' : 'Acknowledge this order'),
          ),
      ],
    );
  }

  Widget _invoice(Map<String, dynamic> view) {
    final lines = (view['lines'] as List? ?? []).whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
          Text('${view['code'] ?? ''}', style: Theme.of(context).textTheme.titleLarge),
          Text(_fa ? 'این اعلام سند حسابداری نمی‌سازد. فایل را جدا برای خریدار بفرستید؛ اینجا بارگذاری عمومی فایل نیست.' : 'This notice does not create an accounting document. Send the file to the buyer separately; this page has no public file upload.'),
          for (final line in lines)
            ListTile(title: Text('${line['description']}'), subtitle: Text(_fa ? 'مقدار ${line['qty']} — قیمت ${line['unit_price']}' : 'Qty ${line['qty']} — price ${line['unit_price']}')),
          TextField(controller: _reference, decoration: InputDecoration(labelText: _fa ? 'شماره فاکتور شما' : 'Your invoice number')),
          TextField(controller: _amount, decoration: InputDecoration(labelText: _fa ? 'مبلغ' : 'Amount'), keyboardType: TextInputType.number),
          TextField(controller: _note, decoration: InputDecoration(labelText: _fa ? 'یادداشت' : 'Note')),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () async {
              final amount = num.tryParse(_amount.text);
              if (_reference.text.trim().isEmpty || amount == null || amount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_fa ? 'شماره و مبلغ معتبر لازم است.' : 'A reference and a positive amount are required.')));
                return;
              }
              try {
                await _api.publicInvoice(widget.token, {'reference': _reference.text.trim(), 'amount': amount, if (_note.text.trim().isNotEmpty) 'note': _note.text.trim()});
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_fa ? 'اعلام شد. این سند حسابداری نمی‌سازد.' : 'Sent. This does not create an accounting document.')));
              } catch (error) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(procurementErrorText(error))));
              }
            },
            child: Text(_fa ? 'اعلام فاکتور' : 'Send invoice notice'),
          ),
      ],
    );
  }
}
