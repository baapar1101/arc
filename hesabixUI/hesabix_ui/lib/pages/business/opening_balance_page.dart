import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/permission_guard.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/opening_balance_service.dart';
import 'package:hesabix_ui/widgets/invoice/bank_account_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/cash_register_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/petty_cash_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/person_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/product_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/warehouse_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/account_combobox_widget.dart';
import 'package:hesabix_ui/models/account_model.dart';
import 'package:hesabix_ui/services/account_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OpeningBalancePage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const OpeningBalancePage({super.key, required this.businessId, required this.authStore});

  @override
  State<OpeningBalancePage> createState() => _OpeningBalancePageState();
}

class _OpeningBalancePageState extends State<OpeningBalancePage> {
  late final OpeningBalanceService _service;
  bool _loading = false;
  Map<String, dynamic>? _document;
  // Local form state
  final List<Map<String, dynamic>> _bankCashPettyLines = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> _personLines = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> _inventoryLines = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> _otherAccountLines = <Map<String, dynamic>>[];
  bool _autoBalance = true;
  int? _inventoryAccountId;
  int? _equityAccountId;
  Account? _inventoryAccount;
  Account? _equityAccount;
  int? _bankControlAccountId;    // 10203
  int? _cashControlAccountId;    // 10202
  int? _pettyControlAccountId;   // 10201
  int? _personReceivableAccountId; // 10401
  int? _personPayableAccountId;    // 20201

  @override
  void initState() {
    super.initState();
    _service = OpeningBalanceService(ApiClient());
    _load();
    _loadDefaultAccounts();
    _loadSavedDefaults();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final doc = await _service.fetch(businessId: widget.businessId);
      setState(() => _document = doc);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در دریافت تراز افتتاحیه: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadDefaultAccounts() async {
    try {
      final accountService = AccountService();
      Future<Account?> findByCode(String code) async {
        final res = await accountService.searchAccounts(businessId: widget.businessId, searchQuery: code, limit: 50);
        final items = (res['items'] as List<dynamic>? ?? const <dynamic>[]);
        for (final it in items) {
          final acc = Account.fromJson(Map<String, dynamic>.from(it as Map));
          if (acc.code == code) return acc;
        }
        return null;
      }

      final inv = await findByCode('10101');
      final bank = await findByCode('10203');
      final cash = await findByCode('10202');
      final petty = await findByCode('10201');
      final ar = await findByCode('10401');
      final ap = await findByCode('20201');
      // برای تراز خودکار: اگر 30201 نبود، سرمایه اولیه 30101 را استفاده کن
      final equity = (await findByCode('30201')) ?? (await findByCode('30101'));

      if (!mounted) return;
      setState(() {
        _inventoryAccount = inv;
        _inventoryAccountId = inv?.id;
        _bankControlAccountId = bank?.id;
        _cashControlAccountId = cash?.id;
        _pettyControlAccountId = petty?.id;
        _personReceivableAccountId = ar?.id;
        _personPayableAccountId = ap?.id;
        _equityAccount = equity;
        _equityAccountId = equity?.id;
      });
    } catch (_) {
      // نادیده بگیر؛ کاربر می‌تواند دستی انتخاب کند
    }
  }

  Future<void> _loadSavedDefaults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String k(String name) => 'ob_default_${widget.businessId}_$name';
      int? gi(String name) {
        final v = prefs.getInt(k(name));
        return v is int && v > 0 ? v : null;
      }
      setState(() {
        _inventoryAccountId = gi('inventory_account_id') ?? _inventoryAccountId;
        _equityAccountId = gi('equity_account_id') ?? _equityAccountId;
        _bankControlAccountId = gi('bank_control_id') ?? _bankControlAccountId;
        _cashControlAccountId = gi('cash_control_id') ?? _cashControlAccountId;
        _pettyControlAccountId = gi('petty_control_id') ?? _pettyControlAccountId;
        _personReceivableAccountId = gi('ar_control_id') ?? _personReceivableAccountId;
        _personPayableAccountId = gi('ap_control_id') ?? _personPayableAccountId;
      });
    } catch (_) {}
  }

  Future<void> _saveDefault(String name, int? id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'ob_default_${widget.businessId}_$name';
      if (id == null || id <= 0) {
        await prefs.remove(key);
      } else {
        await prefs.setInt(key, id);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    // Guard: view permission
    if (!widget.authStore.canReadSection('opening_balance')) {
      return PermissionGuard.buildAccessDeniedPage();
    }
    final canEdit = widget.authStore.hasBusinessPermission('opening_balance', 'edit');
    final validation = _computeValidation();
    final isPosted = (_document?['extra_info']?['posted'] ?? false) == true;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.openingBalance),
        actions: [
          TextButton.icon(
            onPressed: (_loading || !canEdit || (validation['save_disabled'] == true) || isPosted) ? null : _save,
            icon: const Icon(Icons.save),
            label: Text(t.save),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: (_loading || !canEdit || (validation['finalize_disabled'] == true) || isPosted) ? null : _post,
            icon: const Icon(Icons.how_to_reg),
            label: const Text('نهایی‌سازی'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(t),
    );
  }

  Widget _buildContent(AppLocalizations t) {
    final totals = _calcTotals();
    _computeValidation();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(t.openingBalance, style: Theme.of(context).textTheme.titleLarge),
              if ((_document?['extra_info']?['posted'] ?? false) == true)
                const Chip(label: Text('نهایی شده')),
            ],
          ),
          const SizedBox(height: 16),
          _buildValidationWarnings(),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('سال مالی: ${_document?['fiscal_year_title'] ?? '-'}'),
                  const SizedBox(height: 8),
                  Text('تاریخ سند: ${_document?['document_date'] ?? '-'}'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: Text('جمع بدهکار: ${totals['debit']?.toStringAsFixed(2) ?? '0'}')),
                      Expanded(child: Text('جمع بستانکار: ${totals['credit']?.toStringAsFixed(2) ?? '0'}')),
                      Expanded(child: Text('اختلاف: ${(totals['diff'] as double).toStringAsFixed(2)}')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Switch(value: _autoBalance, onChanged: (v) => setState(() => _autoBalance = v)),
                      const SizedBox(width: 8),
                      const Text('بستن خودکار اختلاف به حقوق صاحبان سهام'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildQuickSelectors(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(child: _buildTabs(t)),
        ],
      ),
    );
  }

  Widget _buildTabs(AppLocalizations t) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'بانک/صندوق/تنخواه'),
              Tab(text: 'اشخاص'),
              Tab(text: 'کالا'),
              Tab(text: 'سایر حساب‌ها'),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TabBarView(
              children: [
                _buildBankCashPettyTab(),
                _buildPersonsTab(),
                _buildInventoryTab(),
                _buildOtherAccountsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBankCashPettyTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: BankAccountComboboxWidget(
                businessId: widget.businessId,
                selectedAccountId: null,
                onChanged: (opt) {
                  if (opt == null) return;
                  _bankCashPettyLines.add({'type': 'bank', 'refId': opt.id, 'amount': 0.0});
                  setState(() {});
                },
                label: 'افزودن بانک',
                hintText: 'انتخاب و افزودن بانک',
                filterCurrencyId: widget.authStore.selectedCurrencyId,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: CashRegisterComboboxWidget(
                businessId: widget.businessId,
                selectedRegisterId: null,
                onChanged: (opt) {
                  if (opt == null) return;
                  _bankCashPettyLines.add({'type': 'cash', 'refId': opt.id, 'amount': 0.0});
                  setState(() {});
                },
                label: 'افزودن صندوق',
                hintText: 'انتخاب و افزودن صندوق',
                filterCurrencyId: widget.authStore.selectedCurrencyId,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: PettyCashComboboxWidget(
                businessId: widget.businessId,
                selectedPettyCashId: null,
                onChanged: (opt) {
                  if (opt == null) return;
                  _bankCashPettyLines.add({'type': 'petty', 'refId': opt.id, 'amount': 0.0});
                  setState(() {});
                },
                label: 'افزودن تنخواه',
                hintText: 'انتخاب و افزودن تنخواه',
                filterCurrencyId: widget.authStore.selectedCurrencyId,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            itemCount: _bankCashPettyLines.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final m = _bankCashPettyLines[index];
              return ListTile(
                leading: Icon(m['type'] == 'bank' ? Icons.account_balance : (m['type'] == 'cash' ? Icons.point_of_sale : Icons.wallet)),
                title: Text('${m['type']} - ${m['refId']}'),
                subtitle: TextField(
                  decoration: const InputDecoration(isDense: true, labelText: 'مبلغ'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (v) {
                    m['amount'] = double.tryParse(v.replaceAll(',', '')) ?? 0.0;
                    setState(() {});
                  },
                ),
                trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () { _bankCashPettyLines.removeAt(index); setState(() {}); }),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPersonsTab() {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: PersonComboboxWidget(
            businessId: widget.businessId,
            onChanged: (p) {
              if (p == null) return;
              _personLines.add({'personId': p.id, 'debit': 0.0, 'credit': 0.0});
              setState(() {});
            },
            label: 'افزودن شخص',
            searchHint: 'نام/کد/تلفن...',
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            itemCount: _personLines.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final m = _personLines[index];
              return ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text('شخص #${m['personId']}'),
                subtitle: Row(
                  children: [
                    Expanded(child: TextField(decoration: const InputDecoration(isDense: true, labelText: 'بدهکار'), keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (v) { m['debit'] = double.tryParse(v) ?? 0.0; setState(() {}); })),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(decoration: const InputDecoration(isDense: true, labelText: 'بستانکار'), keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (v) { m['credit'] = double.tryParse(v) ?? 0.0; setState(() {}); })),
                  ],
                ),
                trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () { _personLines.removeAt(index); setState(() {}); }),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildInventoryTab() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              flex: 2,
              child: ProductComboboxWidget(
                businessId: widget.businessId,
                onChanged: (p) {
                  if (p == null) return;
                  _inventoryLines.add({'product': p, 'warehouseId': null, 'quantity': 0.0, 'cost_price': 0.0});
                  setState(() {});
                },
                label: 'افزودن کالا',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AccountComboboxWidget(
                businessId: widget.businessId,
                selectedAccount: _inventoryAccount,
                onChanged: (acc) {
                  _inventoryAccount = acc;
                  _inventoryAccountId = acc?.id;
                  setState(() {});
                },
                label: 'حساب موجودی',
                hintText: 'انتخاب حساب موجودی کالا',
                isRequired: false,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            itemCount: _inventoryLines.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final m = _inventoryLines[index];
              return ListTile(
                leading: const Icon(Icons.inventory_outlined),
                title: Text('${m['product']?['code'] ?? ''} - ${m['product']?['name'] ?? ''}'),
                subtitle: Row(
                  children: [
                    Expanded(child: WarehouseComboboxWidget(businessId: widget.businessId, selectedWarehouseId: m['warehouseId'] as int?, onChanged: (wid) { m['warehouseId'] = wid; setState(() {}); })),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(decoration: const InputDecoration(isDense: true, labelText: 'تعداد'), keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (v) { m['quantity'] = double.tryParse(v) ?? 0.0; setState(() {}); })),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(decoration: const InputDecoration(isDense: true, labelText: 'بهای واحد'), keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (v) { m['cost_price'] = double.tryParse(v) ?? 0.0; setState(() {}); })),
                  ],
                ),
                trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () { _inventoryLines.removeAt(index); setState(() {}); }),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildOtherAccountsTab() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: AccountComboboxWidget(
                businessId: widget.businessId,
                selectedAccount: null,
                onChanged: (acc) {
                  if (acc != null) {
                    _otherAccountLines.add({'account': acc, 'debit': 0.0, 'credit': 0.0});
                    setState(() {});
                  }
                },
                label: 'افزودن حساب',
                hintText: 'جستجو و انتخاب حساب',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AccountComboboxWidget(
                businessId: widget.businessId,
                selectedAccount: _equityAccount,
                onChanged: (acc) {
                  _equityAccount = acc;
                  _equityAccountId = acc?.id;
                  setState(() {});
                },
                label: 'حساب حقوق صاحبان سهام',
                hintText: 'انتخاب حساب سرمایه/سنواتی',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.builder(
            itemCount: _otherAccountLines.length,
            itemBuilder: (context, index) {
              final m = _otherAccountLines[index];
              return ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: Text(m['account'] != null ? (m['account'] as Account).displayName : 'حساب'),
                subtitle: Row(
                  children: [
                    Expanded(child: TextField(decoration: const InputDecoration(isDense: true, labelText: 'بدهکار'), keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (v) { m['debit'] = double.tryParse(v) ?? 0.0; setState(() {}); })),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(decoration: const InputDecoration(isDense: true, labelText: 'بستانکار'), keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (v) { m['credit'] = double.tryParse(v) ?? 0.0; setState(() {}); })),
                  ],
                ),
                trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () { _otherAccountLines.removeAt(index); setState(() {}); }),
              );
            },
          ),
        ),
      ],
    );
  }

  Map<String, double> _calcTotals() {
    double debit = 0.0;
    double credit = 0.0;
    for (final m in _bankCashPettyLines) {
      debit += (m['amount'] as double? ?? 0.0);
    }
    for (final m in _personLines) {
      debit += (m['debit'] as double? ?? 0.0);
      credit += (m['credit'] as double? ?? 0.0);
    }
    for (final m in _otherAccountLines) {
      final d = (m['debit'] as double? ?? 0.0);
      final c = (m['credit'] as double? ?? 0.0);
      if (d <= 0 && c <= 0) continue;
      final acc = m['account'] as Account?;
      if (acc?.id == null) continue;
      debit += d;
      credit += c;
    }
    double invValue = 0.0;
    for (final m in _inventoryLines) {
      final q = (m['quantity'] as double? ?? 0.0);
      final c = (m['cost_price'] as double? ?? 0.0);
      invValue += (q * c);
    }
    debit += invValue;
    return {'debit': debit, 'credit': credit, 'diff': debit - credit};
  }
  
  Map<String, bool> _computeValidation() {
    final totals = _calcTotals();
    final diff = (totals['diff'] ?? 0.0).abs();
    final needsInventoryAccount = _inventoryLines.isNotEmpty && _inventoryAccountId == null;
    final canAutoBalance = _autoBalance && _equityAccountId != null;
    final balanced = diff <= 0.01 || canAutoBalance;
    final saveDisabled = needsInventoryAccount; // برای جلوگیری از ذخیره ناسالم با خطوط موجودی بدون حساب
    final finalizeDisabled = needsInventoryAccount || !balanced;
    return {
      'save_disabled': saveDisabled,
      'finalize_disabled': finalizeDisabled,
    };
  }

  Widget _buildValidationWarnings() {
    final List<Widget> msgs = [];
    if (_inventoryLines.isNotEmpty && _inventoryAccountId == null) {
      msgs.add(_warn('برای ثبت موجودی ابتدای دوره، انتخاب «حساب موجودی» الزامی است.'));
    }
    final totals = _calcTotals();
    final diff = (totals['diff'] ?? 0.0);
    if (diff.abs() > 0.01) {
      if (!_autoBalance) {
        msgs.add(_warn('سند متوازن نیست. اختلاف ${diff.toStringAsFixed(2)}. برای نهایی‌سازی، تراز را برابر کنید یا Auto-balance را روشن کنید.'));
      } else if (_autoBalance && _equityAccountId == null) {
        msgs.add(_warn('Auto-balance فعال است اما «حساب حقوق صاحبان سهام» انتخاب نشده است.'));
      }
    }
    if (msgs.isEmpty) return const SizedBox.shrink();
    return Column(children: msgs);
  }

  Widget _warn(String text) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.3),
        border: Border.all(color: cs.error.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: cs.error),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  // Deprecated helpers removed

  Widget _buildQuickSelectors() {
    final textStyle = Theme.of(context).textTheme.bodyMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('حساب‌های کلیدی (می‌توانید سریع تغییر دهید):', style: textStyle),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: AccountComboboxWidget(
                businessId: widget.businessId,
                selectedAccount: _inventoryAccount,
                onChanged: (acc) {
                  setState(() {
                    _inventoryAccount = acc;
                    _inventoryAccountId = acc?.id;
                  });
                  _saveDefault('inventory_account_id', _inventoryAccountId);
                },
                label: 'حساب موجودی',
                hintText: 'انتخاب حساب موجودی (مثل 10101)',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AccountComboboxWidget(
                businessId: widget.businessId,
                selectedAccount: _equityAccount,
                onChanged: (acc) {
                  setState(() {
                    _equityAccount = acc;
                    _equityAccountId = acc?.id;
                  });
                  _saveDefault('equity_account_id', _equityAccountId);
                },
                label: 'حساب حقوق صاحبان سهام',
                hintText: 'انتخاب سرمایه/سنواتی (مثل 30201/30101)',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: AccountComboboxWidget(
                businessId: widget.businessId,
                selectedAccount: null,
                onChanged: (acc) {
                  setState(() {
                    _bankControlAccountId = acc?.id;
                  });
                  _saveDefault('bank_control_id', _bankControlAccountId);
                },
                label: 'حساب کنترل بانک',
                hintText: 'مثال: 10203',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AccountComboboxWidget(
                businessId: widget.businessId,
                selectedAccount: null,
                onChanged: (acc) {
                  setState(() {
                    _cashControlAccountId = acc?.id;
                  });
                  _saveDefault('cash_control_id', _cashControlAccountId);
                },
                label: 'حساب کنترل صندوق',
                hintText: 'مثال: 10202',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: AccountComboboxWidget(
                businessId: widget.businessId,
                selectedAccount: null,
                onChanged: (acc) {
                  setState(() {
                    _pettyControlAccountId = acc?.id;
                  });
                  _saveDefault('petty_control_id', _pettyControlAccountId);
                },
                label: 'حساب کنترل تنخواه',
                hintText: 'مثال: 10201',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AccountComboboxWidget(
                businessId: widget.businessId,
                selectedAccount: null,
                onChanged: (acc) {
                  setState(() {
                    _personReceivableAccountId = acc?.id;
                  });
                  _saveDefault('ar_control_id', _personReceivableAccountId);
                },
                label: 'حساب دریافتنی اشخاص',
                hintText: 'مثال: 10401',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: AccountComboboxWidget(
                businessId: widget.businessId,
                selectedAccount: null,
                onChanged: (acc) {
                  setState(() {
                    _personPayableAccountId = acc?.id;
                  });
                  _saveDefault('ap_control_id', _personPayableAccountId);
                },
                label: 'حساب پرداختنی اشخاص',
                hintText: 'مثال: 20201',
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(child: SizedBox.shrink()),
          ],
        ),
      ],
    );
  }

  Future<void> _save() async {
    final accountLines = <Map<String, dynamic>>[];
    for (final m in _bankCashPettyLines) {
      final amount = (m['amount'] as double? ?? 0.0);
      if (amount <= 0) continue;
      accountLines.add({
        'account_id': _inferAccountIdForType(m['type'] as String),
        if (m['type'] == 'bank') 'bank_account_id': int.tryParse('${m['refId']}'),
        if (m['type'] == 'cash') 'cash_register_id': int.tryParse('${m['refId']}'),
        if (m['type'] == 'petty') 'petty_cash_id': int.tryParse('${m['refId']}'),
        'debit': amount,
        'credit': 0,
      });
    }
    for (final m in _personLines) {
      final d = (m['debit'] as double? ?? 0.0);
      final c = (m['credit'] as double? ?? 0.0);
      if (d <= 0 && c <= 0) continue;
      accountLines.add({'account_id': _inferPersonAccountId(d, c), 'person_id': m['personId'], 'debit': d, 'credit': c});
    }
    for (final m in _otherAccountLines) {
      final d = (m['debit'] as double? ?? 0.0);
      final c = (m['credit'] as double? ?? 0.0);
      if (d <= 0 && c <= 0) continue;
      final acc = m['account'] as Account?;
      if (acc?.id == null) continue;
      accountLines.add({'account_id': acc!.id, 'debit': d, 'credit': c});
    }
    final inventoryLines = <Map<String, dynamic>>[];
    for (final m in _inventoryLines) {
      final product = (m['product'] as Map<String, dynamic>?);
      final dynamic pidRaw = product != null ? product['id'] : null;
      final int? pid = pidRaw is int ? pidRaw : int.tryParse("$pidRaw");
      final wid = m['warehouseId'] as int?;
      final q = (m['quantity'] as double? ?? 0.0);
      final c = (m['cost_price'] as double? ?? 0.0);
      if (pid == null || wid == null || q <= 0) continue;
      inventoryLines.add({'product_id': pid, 'quantity': q, 'extra_info': {'movement': 'in', 'warehouse_id': wid, if (c > 0) 'cost_price': c}});
    }

    final payload = <String, dynamic>{
      'fiscal_year_id': _document?['fiscal_year_id'],
      'currency_id': _document?['currency_id'] ?? widget.authStore.selectedCurrencyId,
      'account_lines': accountLines,
      'inventory_lines': inventoryLines,
      if (_inventoryAccountId != null) 'inventory_account_id': _inventoryAccountId,
      'auto_balance_to_equity': _autoBalance,
      if (_equityAccountId != null) 'equity_account_id': _equityAccountId,
    };

    final saved = await _service.save(businessId: widget.businessId, payload: payload);
    setState(() => _document = saved);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ذخیره شد')));
    }
  }

  int? _inferAccountIdForType(String type) {
    switch (type) {
      case 'bank':
        return _bankControlAccountId;
      case 'cash':
        return _cashControlAccountId;
      case 'petty':
        return _pettyControlAccountId;
    }
    return null;
  }

  int? _inferPersonAccountId(double debit, double credit) {
    if (debit > 0 && (credit <= 0)) {
      return _personReceivableAccountId; // دریافتنی
    }
    if (credit > 0 && (debit <= 0)) {
      return _personPayableAccountId; // پرداختنی
    }
    return null;
  }

  Future<void> _post() async {
    final posted = await _service.post(businessId: widget.businessId);
    setState(() => _document = posted);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('نهایی شد')));
    }
  }
}


