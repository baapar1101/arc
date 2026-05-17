import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/payment_gateway_service.dart';
import 'package:hesabix_ui/services/business_api_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/business_subpage_back_leading.dart';

/// پیش‌فرض پرداخت آنلاین برای لینک‌های اشتراک عمومی فاکتور (هنگام ایجاد لینک جدید).
class InvoiceSharePaymentSettingsPage extends StatefulWidget {
  final int businessId;

  const InvoiceSharePaymentSettingsPage({super.key, required this.businessId});

  @override
  State<InvoiceSharePaymentSettingsPage> createState() => _InvoiceSharePaymentSettingsPageState();
}

class _InvoiceSharePaymentSettingsPageState extends State<InvoiceSharePaymentSettingsPage> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool _enabled = false;
  int? _gatewayId;
  List<Map<String, dynamic>> _gateways = const [];
  bool _loadingGateways = false;

  final _gatewayService = PaymentGatewayService(ApiClient());

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _loadGateways();
      final s = await BusinessApiService.getInvoiceShareSettings(widget.businessId);
      if (!mounted) return;
      setState(() {
        _enabled = s['default_online_payment_enabled'] == true;
        final g = s['default_online_payment_gateway_id'];
        if (g is int) {
          _gatewayId = g;
        } else if (g is num) {
          _gatewayId = g.toInt();
        } else {
          _gatewayId = int.tryParse(g?.toString() ?? '');
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
    }
  }

  Future<void> _loadGateways() async {
    setState(() => _loadingGateways = true);
    try {
      final list = await _gatewayService.listBusinessGateways(widget.businessId);
      if (!mounted) return;
      setState(() {
        _gateways = list;
        _loadingGateways = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _gateways = const [];
          _loadingGateways = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_enabled) {
      if (_gateways.isEmpty) {
        SnackBarHelper.showError(
          context,
          message: 'برای این کسب‌وکار درگاه پرداخت فعالی وجود ندارد.',
        );
        return;
      }
      if (_gatewayId == null) {
        SnackBarHelper.showError(context, message: 'انتخاب درگاه الزامی است.');
        return;
      }
    }

    setState(() => _saving = true);
    try {
      await BusinessApiService.updateInvoiceShareSettings(
        widget.businessId,
        {
          'default_online_payment_enabled': _enabled,
          'default_online_payment_gateway_id': _enabled ? _gatewayId : null,
        },
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: 'تنظیمات ذخیره شد');
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gatewayIds = _gateways.map((g) => (g['id'] as num?)?.toInt()).whereType<int>().toSet();
    final dropdownValue =
        _gatewayId != null && gatewayIds.contains(_gatewayId) ? _gatewayId : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('پرداخت آنلاین لینک فاکتور'),
        leading: businessSubpageBackLeading(context, widget.businessId),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _loadAll,
                          icon: const Icon(Icons.refresh),
                          label: const Text('تلاش مجدد'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'این مقادیر هنگام ایجاد لینک اشتراک جدید برای فاکتور فروش قطعی به‌صورت پیش‌فرض اعمال می‌شوند. '
                      'پس از بازگشت مشتری از درگاه، در صورت تنظیم آدرس اپ عمومی در سامانه، به همین صفحهٔ عمومی هدایت می‌شود.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SwitchListTile(
                      title: const Text('پیش‌فرض: پرداخت آنلاین فعال'),
                      subtitle: const Text('برای هر لینک جدید می‌توانید در جزئیات سند تغییر دهید.'),
                      value: _enabled,
                      onChanged: _saving
                          ? null
                          : (v) {
                              setState(() {
                                _enabled = v;
                                if (!v) _gatewayId = null;
                              });
                            },
                    ),
                    if (_loadingGateways)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: LinearProgressIndicator(),
                      )
                    else if (_gateways.isEmpty)
                      Text(
                        'درگاه پرداختی برای این کسب‌وکار تعریف نشده است.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                      )
                    else ...[
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int?>(
                        value: dropdownValue,
                        decoration: const InputDecoration(
                          labelText: 'درگاه پیش‌فرض',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          for (final g in _gateways)
                            DropdownMenuItem<int?>(
                              value: (g['id'] as num?)?.toInt(),
                              child: Text(
                                '${g['display_name'] ?? g['provider'] ?? g['id']}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: !_enabled || _saving
                            ? null
                            : (v) => setState(() => _gatewayId = v),
                      ),
                    ],
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(_saving ? 'در حال ذخیره…' : 'ذخیره'),
                    ),
                  ],
                ),
    );
  }
}
