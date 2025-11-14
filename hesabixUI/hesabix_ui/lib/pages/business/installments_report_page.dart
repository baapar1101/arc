import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'dart:html' as html;
import 'package:hesabix_ui/widgets/invoice/person_combobox_widget.dart';
import 'package:hesabix_ui/models/person_model.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/services/invoice_service.dart';

class InstallmentsReportPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  final ApiClient apiClient;
  const InstallmentsReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
    required this.apiClient,
  });

  @override
  State<InstallmentsReportPage> createState() => _InstallmentsReportPageState();
}

class _InstallmentsReportPageState extends State<InstallmentsReportPage> {
  List<Map<String, dynamic>> _fiscalYears = <Map<String, dynamic>>[];
  int? _selectedFiscalYearId;
  Person? _selectedPerson;
  int? _selectedInvoiceId;
  String? _status; // pending|partial|paid|overdue
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _loading = false;
  List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _loadFiscalYears();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadFiscalYears() async {
    try {
      final resp = await widget.apiClient.get<Map<String, dynamic>>(
        '/api/v1/business/${widget.businessId}/fiscal-years',
      );
      final data = Map<String, dynamic>.from(resp.data?['data'] ?? {});
      final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
      setState(() {
        _fiscalYears = items;
        _selectedFiscalYearId = items.firstWhere(
          (e) => (e['is_current'] == true),
          orElse: () => (items.isNotEmpty ? items.first : const <String, dynamic>{}),
        )['id'] as int?;
      });
    } catch (_) {}
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final body = <String, dynamic>{
        if (_status != null && _status!.isNotEmpty) 'status': _status,
        if (_fromDate != null) 'due_from': _fromDate!.toIso8601String().split('T').first,
        if (_toDate != null) 'due_to': _toDate!.toIso8601String().split('T').first,
        if (_selectedFiscalYearId != null) 'fiscal_year_id': _selectedFiscalYearId,
        if (_selectedPerson != null) 'person_id': _selectedPerson!.id,
        if (_selectedInvoiceId != null) 'invoice_id': _selectedInvoiceId,
      };

      final res = await widget.apiClient.post<Map<String, dynamic>>(
        '/api/v1/invoices/business/${widget.businessId}/installments/search',
        data: body,
      );
      final data = Map<String, dynamic>.from(res.data?['data'] ?? const {});
      final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
      setState(() {
        _items = items;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطا در دریافت گزارش: ${e.toString()}'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('گزارش اقساط'),
        actions: [
          IconButton(
            onPressed: _fetch,
            icon: const Icon(Icons.refresh),
            tooltip: 'بروزرسانی',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<int>(
                    value: _selectedFiscalYearId,
                    items: _fiscalYears
                        .map((fy) => DropdownMenuItem<int>(
                              value: fy['id'] as int,
                              child: Text('${fy['title'] ?? ''}'),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedFiscalYearId = v),
                    decoration: const InputDecoration(
                      labelText: 'سال مالی',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    value: _status,
                    items: const [
                      DropdownMenuItem(value: null, child: Text('همه وضعیت‌ها')),
                      DropdownMenuItem(value: 'pending', child: Text('در انتظار')),
                      DropdownMenuItem(value: 'partial', child: Text('پرداخت جزئی')),
                      DropdownMenuItem(value: 'overdue', child: Text('سررسید گذشته')),
                      DropdownMenuItem(value: 'paid', child: Text('تسویه شده')),
                    ],
                    onChanged: (v) => setState(() => _status = v),
                    decoration: const InputDecoration(
                      labelText: 'وضعیت',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: DateInputField(
                    value: _fromDate,
                    onChanged: (d) => setState(() => _fromDate = d),
                    calendarController: widget.calendarController,
                    labelText: 'از تاریخ سررسید',
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: DateInputField(
                    value: _toDate,
                    onChanged: (d) => setState(() => _toDate = d),
                    calendarController: widget.calendarController,
                    labelText: 'تا تاریخ سررسید',
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: PersonComboboxWidget(
                    businessId: widget.businessId,
                    selectedPerson: _selectedPerson,
                    onChanged: (p) => setState(() {
                      _selectedPerson = p;
                      _selectedInvoiceId = null;
                    }),
                    label: 'شخص',
                    hintText: 'جستجو و انتخاب شخص',
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: TextFormField(
                    controller: TextEditingController(text: _selectedInvoiceId?.toString() ?? ''),
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'فاکتور',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        tooltip: 'انتخاب فاکتور',
                        onPressed: _pickInvoice,
                      ),
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _loading ? null : _fetch,
                  icon: const Icon(Icons.search),
                  label: const Text('جستجو'),
                ),
                FilledButton.icon(
                  onPressed: _loading ? null : _exportCsv,
                  icon: const Icon(Icons.download),
                  label: const Text('خروجی Excel'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? const Center(child: Text('داده‌ای یافت نشد'))
                    : ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final it = _items[i];
                          return ListTile(
                            dense: true,
                            title: Text('${it['invoice_code'] ?? '-'}  |  قسط ${it['seq'] ?? '-'}'),
                            subtitle: Text('سررسید: ${it['due_date'] ?? '-'}   |   وضعیت: ${it['status'] ?? '-'}'),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('مانده: ${(it['remaining'] ?? 0).toString()}'),
                                Text('پرداخت: ${(it['paid_amount'] ?? 0).toString()}'),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCsv() async {
    setState(() => _loading = true);
    try {
      final body = <String, dynamic>{
        if (_status != null && _status!.isNotEmpty) 'status': _status,
        if (_fromDate != null) 'due_from': _fromDate!.toIso8601String().split('T').first,
        if (_toDate != null) 'due_to': _toDate!.toIso8601String().split('T').first,
        if (_selectedFiscalYearId != null) 'fiscal_year_id': _selectedFiscalYearId,
        if (_selectedPerson != null) 'person_id': _selectedPerson!.id,
        if (_selectedInvoiceId != null) 'invoice_id': _selectedInvoiceId,
      };

      final bytes = await widget.apiClient.post<List<int>>(
        '/api/v1/invoices/business/${widget.businessId}/installments/export/excel',
        data: body,
        responseType: ResponseType.bytes,
        options: Options(
          headers: {'Accept': 'text/csv'},
        ),
      );
      final data = bytes.data ?? <int>[];
      // Save in web
      final blob = html.Blob([data], 'text/csv');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final a = html.AnchorElement(href: url)
        ..download = 'installments_${widget.businessId}.csv'
        ..style.display = 'none';
      html.document.body?.append(a);
      a.click();
      a.remove();
      html.Url.revokeObjectUrl(url);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطا در خروجی: ${e.toString()}'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickInvoice() async {
    final svc = InvoiceService(apiClient: widget.apiClient);
    final TextEditingController q = TextEditingController();
    List<Map<String, dynamic>> results = <Map<String, dynamic>>[];
    bool loading = false;
    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            Future<void> run() async {
              setStateDialog(() {
                loading = true;
              });
              try {
                final filters = <String, dynamic>{};
                if (_selectedPerson != null) {
                  filters['person_id'] = _selectedPerson!.id;
                }
                final data = await svc.searchInvoices(
                  businessId: widget.businessId,
                  page: 1,
                  limit: 20,
                  search: q.text.trim().isEmpty ? null : q.text.trim(),
                  filters: filters.isEmpty ? null : filters,
                );
                final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
                setStateDialog(() {
                  results = items;
                });
              } catch (_) {
                setStateDialog(() {
                  results = <Map<String, dynamic>>[];
                });
              } finally {
                setStateDialog(() {
                  loading = false;
                });
              }
            }
            return AlertDialog(
              title: const Text('انتخاب فاکتور'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: q,
                      decoration: const InputDecoration(
                        labelText: 'جستجو',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => run(),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: run,
                      icon: const Icon(Icons.search),
                      label: const Text('جستجو'),
                    ),
                    const SizedBox(height: 8),
                    if (loading) const LinearProgressIndicator(),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 360),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: results.length,
                        itemBuilder: (c, i) {
                          final it = results[i];
                          return ListTile(
                            leading: const Icon(Icons.receipt_long),
                            title: Text(it['code']?.toString() ?? '-'),
                            subtitle: Text(it['description']?.toString() ?? ''),
                            onTap: () => Navigator.pop(ctx, it),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
              ],
            );
          },
        );
      },
    ).then((picked) {
      if (picked is Map<String, dynamic>) {
        final id = picked['id'] as int?;
        if (id != null) {
          setState(() {
            _selectedInvoiceId = id;
          });
        }
      }
    });
  }
}


