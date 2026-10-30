import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../core/calendar_controller.dart';
import '../../../models/account_model.dart';
import '../../../models/person_model.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/date_input_field.dart';
import '../../../widgets/invoice/account_tree_combobox_widget.dart';
import '../../../widgets/invoice/bank_account_combobox_widget.dart';
import '../../../widgets/invoice/cash_register_combobox_widget.dart';
import '../../../widgets/invoice/person_combobox_widget.dart';
import '../../../widgets/invoice/petty_cash_combobox_widget.dart';
import 'fixed_assets_ui.dart';

int? _parseId(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  return int.tryParse(raw.trim());
}

String _isoDate(DateTime d) => d.toIso8601String().split('T').first;

class FixedAssetCounterpartyResult {
  const FixedAssetCounterpartyResult({
    required this.type,
    this.personId,
    this.bankAccountId,
    this.cashRegisterId,
    this.pettyCashId,
    this.accountId,
  });

  final String type;
  final int? personId;
  final int? bankAccountId;
  final int? cashRegisterId;
  final int? pettyCashId;
  final int? accountId;

  bool get isComplete {
    switch (type) {
      case 'opening':
        return true;
      case 'person':
        return personId != null;
      case 'bank':
        return bankAccountId != null;
      case 'cash_register':
        return cashRegisterId != null;
      case 'petty_cash':
        return pettyCashId != null;
      case 'account':
        return accountId != null;
      default:
        return false;
    }
  }

  Map<String, dynamic> toPayload() {
    return {
      'counterparty_type': type,
      if (type == 'person') 'person_id': personId,
      if (type == 'bank') 'bank_account_id': bankAccountId,
      if (type == 'cash_register') 'cash_register_id': cashRegisterId,
      if (type == 'petty_cash') 'petty_cash_id': pettyCashId,
      if (type == 'account') 'account_id': accountId,
    };
  }
}

class FixedAssetCounterpartyPicker extends StatefulWidget {
  const FixedAssetCounterpartyPicker({
    super.key,
    required this.businessId,
    required this.allowOpening,
    this.initialType = 'person',
    this.onChanged,
  });

  final int businessId;
  final bool allowOpening;
  final String initialType;
  final ValueChanged<FixedAssetCounterpartyResult>? onChanged;

  @override
  State<FixedAssetCounterpartyPicker> createState() => _FixedAssetCounterpartyPickerState();
}

class _FixedAssetCounterpartyPickerState extends State<FixedAssetCounterpartyPicker> {
  late String _type;
  Person? _person;
  String? _bankId;
  String? _cashId;
  String? _pettyId;
  Account? _account;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
  }

  void _emit() {
    widget.onChanged?.call(
      FixedAssetCounterpartyResult(
        type: _type,
        personId: _person?.id,
        bankAccountId: _parseId(_bankId),
        cashRegisterId: _parseId(_cashId),
        pettyCashId: _parseId(_pettyId),
        accountId: _account?.id,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return FixedAssetsUi.spacedColumn([
      DropdownButtonFormField<String>(
        value: _type,
        decoration: FixedAssetsUi.fieldDecoration(
          context,
          t.fixedAssetsCounterparty,
          prefixIcon: Icons.account_balance_wallet_outlined,
        ),
        items: [
          if (widget.allowOpening)
            DropdownMenuItem(value: 'opening', child: Text(t.fixedAssetsKindOpening)),
          DropdownMenuItem(value: 'person', child: Text(t.fixedAssetsCounterpartyPerson)),
          DropdownMenuItem(value: 'bank', child: Text(t.fixedAssetsCounterpartyBank)),
          DropdownMenuItem(value: 'cash_register', child: Text(t.fixedAssetsCounterpartyCash)),
          DropdownMenuItem(value: 'petty_cash', child: Text(t.fixedAssetsCounterpartyPetty)),
          DropdownMenuItem(value: 'account', child: Text(t.fixedAssetsCounterpartyAccount)),
        ],
        onChanged: (v) {
          if (v == null) return;
          setState(() {
            _type = v;
            _person = null;
            _bankId = null;
            _cashId = null;
            _pettyId = null;
            _account = null;
          });
          _emit();
        },
      ),
      if (_type == 'person')
        PersonComboboxWidget(
          businessId: widget.businessId,
          selectedPerson: _person,
          dense: true,
          isRequired: true,
          label: t.fixedAssetsCounterpartyPerson,
          onChanged: (p) {
            setState(() => _person = p);
            _emit();
          },
        ),
      if (_type == 'bank')
        BankAccountComboboxWidget(
          businessId: widget.businessId,
          selectedAccountId: _bankId,
          dense: true,
          isRequired: true,
          label: t.fixedAssetsCounterpartyBank,
          onChanged: (opt) {
            setState(() => _bankId = opt?.id);
            _emit();
          },
        ),
      if (_type == 'cash_register')
        CashRegisterComboboxWidget(
          businessId: widget.businessId,
          selectedRegisterId: _cashId,
          dense: true,
          isRequired: true,
          label: t.fixedAssetsCounterpartyCash,
          onChanged: (opt) {
            setState(() => _cashId = opt?.id);
            _emit();
          },
        ),
      if (_type == 'petty_cash')
        PettyCashComboboxWidget(
          businessId: widget.businessId,
          selectedPettyCashId: _pettyId,
          dense: true,
          isRequired: true,
          label: t.fixedAssetsCounterpartyPetty,
          onChanged: (opt) {
            setState(() => _pettyId = opt?.id);
            _emit();
          },
        ),
      if (_type == 'account')
        AccountTreeComboboxWidget(
          businessId: widget.businessId,
          selectedAccount: _account,
          dense: true,
          isRequired: true,
          label: t.fixedAssetsCounterpartyAccount,
          onChanged: (a) {
            setState(() => _account = a);
            _emit();
          },
        ),
    ]);
  }
}

class FixedAssetsCreateAssetDialog extends StatefulWidget {
  const FixedAssetsCreateAssetDialog({
    super.key,
    required this.businessId,
    required this.calendarController,
    required this.classes,
    this.locations = const [],
  });

  final int businessId;
  final CalendarController calendarController;
  final List<Map<String, dynamic>> classes;
  final List<Map<String, dynamic>> locations;

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required int businessId,
    required CalendarController calendarController,
    required List<Map<String, dynamic>> classes,
    List<Map<String, dynamic>> locations = const [],
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => FixedAssetsCreateAssetDialog(
        businessId: businessId,
        calendarController: calendarController,
        classes: classes,
        locations: locations,
      ),
    );
  }

  @override
  State<FixedAssetsCreateAssetDialog> createState() => _FixedAssetsCreateAssetDialogState();
}

class _FixedAssetsCreateAssetDialogState extends State<FixedAssetsCreateAssetDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _serialCtrl;
  late final TextEditingController _costCtrl;
  late final TextEditingController _salvageCtrl;
  late final TextEditingController _vatCtrl;
  late final TextEditingController _lifeCtrl;
  late int _classId;
  int? _locationId;
  Person? _custodian;
  String _kind = 'purchase';
  DateTime _acquisition = DateTime.now();

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _serialCtrl = TextEditingController();
    _costCtrl = TextEditingController();
    _salvageCtrl = TextEditingController(text: '0');
    _vatCtrl = TextEditingController(text: '0');
    final first = widget.classes.first;
    _classId = int.parse('${first['id']}');
    final defaultLife = first['default_useful_life_months'];
    _lifeCtrl = TextEditingController(text: '${defaultLife ?? 120}');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _serialCtrl.dispose();
    _costCtrl.dispose();
    _salvageCtrl.dispose();
    _vatCtrl.dispose();
    _lifeCtrl.dispose();
    super.dispose();
  }

  void _onClassChanged(int id) {
    final cls = widget.classes.firstWhere((c) => int.parse('${c['id']}') == id, orElse: () => widget.classes.first);
    setState(() {
      _classId = id;
      if (_lifeCtrl.text.trim().isEmpty || _lifeCtrl.text.trim() == '120') {
        _lifeCtrl.text = '${cls['default_useful_life_months'] ?? 120}';
      }
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, {
      'class_id': _classId,
      'name': _nameCtrl.text.trim(),
      'serial_number': _serialCtrl.text.trim().isEmpty ? null : _serialCtrl.text.trim(),
      'cost': FixedAssetsUi.parseMoney(_costCtrl.text) ?? 0,
      'salvage': FixedAssetsUi.parseMoney(_salvageCtrl.text) ?? 0,
      'vat_amount': FixedAssetsUi.parseMoney(_vatCtrl.text) ?? 0,
      'useful_life_months': FixedAssetsUi.parseInt(_lifeCtrl.text),
      'acquisition_kind': _kind,
      'acquisition_date': _isoDate(_acquisition),
      'commission_date': _isoDate(_acquisition),
      'method': 'straight_line',
      if (_locationId != null) 'location_id': _locationId,
      if (_custodian?.id != null) 'custodian_person_id': _custodian!.id,
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return FixedAssetsUi.dialogShell(
      context: context,
      title: t.fixedAssetsNewAsset,
      icon: Icons.add_box_outlined,
      child: Form(
        key: _formKey,
        child: FixedAssetsUi.spacedColumn([
          FixedAssetsUi.infoBanner(context, t.fixedAssetsNewAssetHint),
          FixedAssetsUi.sectionLabel(context, t.fixedAssetsSectionIdentity),
          DropdownButtonFormField<int>(
            value: _classId,
            decoration: FixedAssetsUi.fieldDecoration(context, t.fixedAssetsClass, prefixIcon: Icons.category_outlined),
            items: [
              for (final c in widget.classes)
                DropdownMenuItem(value: int.parse('${c['id']}'), child: Text('${c['name']}')),
            ],
            onChanged: (v) {
              if (v != null) _onClassChanged(v);
            },
          ),
          TextFormField(
            controller: _nameCtrl,
            textInputAction: TextInputAction.next,
            decoration: FixedAssetsUi.fieldDecoration(context, t.fixedAssetsAssetName, prefixIcon: Icons.badge_outlined),
            validator: (v) => (v == null || v.trim().isEmpty) ? t.required : null,
          ),
          TextFormField(
            controller: _serialCtrl,
            textInputAction: TextInputAction.next,
            decoration: FixedAssetsUi.fieldDecoration(context, t.fixedAssetsSerial, prefixIcon: Icons.qr_code_2),
          ),
          if (widget.locations.isNotEmpty)
            DropdownButtonFormField<int?>(
              value: _locationId,
              decoration: FixedAssetsUi.fieldDecoration(context, t.fixedAssetsLocation, prefixIcon: Icons.place_outlined),
              items: [
                DropdownMenuItem<int?>(value: null, child: Text(t.fixedAssetsNone)),
                for (final loc in widget.locations)
                  DropdownMenuItem<int?>(value: int.parse('${loc['id']}'), child: Text('${loc['name']}')),
              ],
              onChanged: (v) => setState(() => _locationId = v),
            ),
          PersonComboboxWidget(
            businessId: widget.businessId,
            selectedPerson: _custodian,
            dense: true,
            label: t.fixedAssetsCustodian,
            onChanged: (p) => setState(() => _custodian = p),
          ),
          FixedAssetsUi.sectionLabel(context, t.fixedAssetsSectionAmounts),
          TextFormField(
            controller: _costCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: FixedAssetsUi.numericFormatters(),
            decoration: FixedAssetsUi.fieldDecoration(context, t.fixedAssetsCost, prefixIcon: Icons.payments_outlined),
            validator: (v) {
              final n = FixedAssetsUi.parseMoney(v);
              if (n == null || n <= 0) return t.required;
              return null;
            },
          ),
          TextFormField(
            controller: _salvageCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: FixedAssetsUi.numericFormatters(),
            decoration: FixedAssetsUi.fieldDecoration(context, t.fixedAssetsSalvage, prefixIcon: Icons.savings_outlined),
          ),
          TextFormField(
            controller: _vatCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: FixedAssetsUi.numericFormatters(),
            decoration: FixedAssetsUi.fieldDecoration(context, t.fixedAssetsVat, prefixIcon: Icons.receipt_long_outlined),
          ),
          TextFormField(
            controller: _lifeCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: FixedAssetsUi.numericFormatters(allowDecimal: false),
            decoration: FixedAssetsUi.fieldDecoration(
              context,
              t.fixedAssetsUsefulLifeMonths,
              prefixIcon: Icons.timelapse_outlined,
            ),
          ),
          FixedAssetsUi.sectionLabel(context, t.fixedAssetsSectionAcquisition),
          DropdownButtonFormField<String>(
            value: _kind,
            decoration: FixedAssetsUi.fieldDecoration(
              context,
              t.fixedAssetsAcquisitionKind,
              prefixIcon: Icons.swap_horiz,
            ),
            items: [
              DropdownMenuItem(value: 'purchase', child: Text(t.fixedAssetsKindPurchase)),
              DropdownMenuItem(value: 'opening', child: Text(t.fixedAssetsKindOpening)),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _kind = v);
            },
          ),
          DateInputField(
            value: _acquisition,
            calendarController: widget.calendarController,
            labelText: t.fixedAssetsAcquisitionDate,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            onChanged: (d) {
              if (d != null) setState(() => _acquisition = d);
            },
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(onPressed: _submit, child: Text(t.save)),
      ],
    );
  }
}

class FixedAssetsCapitalizeDialog extends StatefulWidget {
  const FixedAssetsCapitalizeDialog({super.key, required this.businessId});

  final int businessId;

  static Future<Map<String, dynamic>?> show(BuildContext context, {required int businessId}) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => FixedAssetsCapitalizeDialog(businessId: businessId),
    );
  }

  @override
  State<FixedAssetsCapitalizeDialog> createState() => _FixedAssetsCapitalizeDialogState();
}

class _FixedAssetsCapitalizeDialogState extends State<FixedAssetsCapitalizeDialog> {
  FixedAssetCounterpartyResult _cp = const FixedAssetCounterpartyResult(type: 'opening');

  void _submit() {
    final t = AppLocalizations.of(context);
    if (!_cp.isComplete) {
      SnackBarHelper.showError(context, message: t.fixedAssetsCounterpartyRequired);
      return;
    }
    Navigator.pop(context, _cp.toPayload());
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return FixedAssetsUi.dialogShell(
      context: context,
      title: t.fixedAssetsCapitalize,
      icon: Icons.post_add_outlined,
      child: FixedAssetsUi.spacedColumn([
        FixedAssetsUi.infoBanner(context, t.fixedAssetsCapitalizeHint),
        FixedAssetCounterpartyPicker(
          businessId: widget.businessId,
          allowOpening: true,
          initialType: 'opening',
          onChanged: (v) => _cp = v,
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(onPressed: _submit, child: Text(t.fixedAssetsCapitalize)),
      ],
    );
  }
}

class FixedAssetsDisposeDialog extends StatefulWidget {
  const FixedAssetsDisposeDialog({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  final int businessId;
  final CalendarController calendarController;

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required int businessId,
    required CalendarController calendarController,
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => FixedAssetsDisposeDialog(
        businessId: businessId,
        calendarController: calendarController,
      ),
    );
  }

  @override
  State<FixedAssetsDisposeDialog> createState() => _FixedAssetsDisposeDialogState();
}

class _FixedAssetsDisposeDialogState extends State<FixedAssetsDisposeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _proceedsCtrl = TextEditingController();
  final _vatCtrl = TextEditingController(text: '0');
  String _kind = 'sale';
  DateTime _disposal = DateTime.now();
  FixedAssetCounterpartyResult _cp = const FixedAssetCounterpartyResult(type: 'bank');

  @override
  void dispose() {
    _proceedsCtrl.dispose();
    _vatCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final t = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;
    if (_kind == 'sale' && !_cp.isComplete) {
      SnackBarHelper.showError(context, message: t.fixedAssetsCounterpartyRequired);
      return;
    }
    Navigator.pop(context, {
      'kind': _kind,
      'disposal_date': _isoDate(_disposal),
      'proceeds': _kind == 'scrap' ? 0 : (FixedAssetsUi.parseMoney(_proceedsCtrl.text) ?? 0),
      'vat_output': _kind == 'scrap' ? 0 : (FixedAssetsUi.parseMoney(_vatCtrl.text) ?? 0),
      if (_kind == 'sale') ..._cp.toPayload(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return FixedAssetsUi.dialogShell(
      context: context,
      title: t.fixedAssetsDispose,
      icon: Icons.output_outlined,
      child: Form(
        key: _formKey,
        child: FixedAssetsUi.spacedColumn([
          DropdownButtonFormField<String>(
            value: _kind,
            decoration: FixedAssetsUi.fieldDecoration(context, t.fixedAssetsDispose, prefixIcon: Icons.swap_vert),
            items: [
              DropdownMenuItem(value: 'sale', child: Text(t.fixedAssetsSale)),
              DropdownMenuItem(value: 'scrap', child: Text(t.fixedAssetsScrap)),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _kind = v);
            },
          ),
          if (_kind == 'sale') ...[
            TextFormField(
              controller: _proceedsCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: FixedAssetsUi.numericFormatters(),
              decoration: FixedAssetsUi.fieldDecoration(
                context,
                t.fixedAssetsProceeds,
                prefixIcon: Icons.payments_outlined,
              ),
              validator: (v) {
                if (_kind != 'sale') return null;
                final n = FixedAssetsUi.parseMoney(v);
                if (n == null || n < 0) return t.required;
                return null;
              },
            ),
            TextFormField(
              controller: _vatCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: FixedAssetsUi.numericFormatters(),
              decoration: FixedAssetsUi.fieldDecoration(
                context,
                t.fixedAssetsVatOutput,
                prefixIcon: Icons.receipt_long_outlined,
              ),
            ),
            FixedAssetCounterpartyPicker(
              businessId: widget.businessId,
              allowOpening: false,
              initialType: 'bank',
              onChanged: (v) => _cp = v,
            ),
          ],
          DateInputField(
            value: _disposal,
            calendarController: widget.calendarController,
            labelText: t.fixedAssetsDisposalDate,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            onChanged: (d) {
              if (d != null) setState(() => _disposal = d);
            },
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(onPressed: _submit, child: Text(t.fixedAssetsDispose)),
      ],
    );
  }
}

class FixedAssetsSubsequentDialog extends StatefulWidget {
  const FixedAssetsSubsequentDialog({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  final int businessId;
  final CalendarController calendarController;

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required int businessId,
    required CalendarController calendarController,
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => FixedAssetsSubsequentDialog(
        businessId: businessId,
        calendarController: calendarController,
      ),
    );
  }

  @override
  State<FixedAssetsSubsequentDialog> createState() => _FixedAssetsSubsequentDialogState();
}

class _FixedAssetsSubsequentDialogState extends State<FixedAssetsSubsequentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _vatCtrl = TextEditingController(text: '0');
  final _lifeCtrl = TextEditingController();
  String _kind = 'routine';
  DateTime _date = DateTime.now();
  FixedAssetCounterpartyResult _cp = const FixedAssetCounterpartyResult(type: 'person');

  @override
  void dispose() {
    _amountCtrl.dispose();
    _vatCtrl.dispose();
    _lifeCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final t = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;
    if (!_cp.isComplete) {
      SnackBarHelper.showError(context, message: t.fixedAssetsCounterpartyRequired);
      return;
    }
    Navigator.pop(context, {
      'kind': _kind,
      'amount': FixedAssetsUi.parseMoney(_amountCtrl.text) ?? 0,
      'vat_amount': FixedAssetsUi.parseMoney(_vatCtrl.text) ?? 0,
      'expenditure_date': _isoDate(_date),
      ..._cp.toPayload(),
      if (_kind == 'major' && _lifeCtrl.text.trim().isNotEmpty)
        'remaining_useful_life_months': FixedAssetsUi.parseInt(_lifeCtrl.text),
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return FixedAssetsUi.dialogShell(
      context: context,
      title: t.fixedAssetsSubsequent,
      icon: Icons.build_outlined,
      child: Form(
        key: _formKey,
        child: FixedAssetsUi.spacedColumn([
          DropdownButtonFormField<String>(
            value: _kind,
            decoration: FixedAssetsUi.fieldDecoration(
              context,
              t.fixedAssetsSubsequent,
              prefixIcon: Icons.handyman_outlined,
            ),
            items: [
              DropdownMenuItem(value: 'routine', child: Text(t.fixedAssetsRoutineRepair)),
              DropdownMenuItem(value: 'major', child: Text(t.fixedAssetsMajorRepair)),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _kind = v);
            },
          ),
          TextFormField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: FixedAssetsUi.numericFormatters(),
            decoration: FixedAssetsUi.fieldDecoration(
              context,
              t.fixedAssetsExpenditureAmount,
              prefixIcon: Icons.payments_outlined,
            ),
            validator: (v) {
              final n = FixedAssetsUi.parseMoney(v);
              if (n == null || n <= 0) return t.required;
              return null;
            },
          ),
          TextFormField(
            controller: _vatCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: FixedAssetsUi.numericFormatters(),
            decoration: FixedAssetsUi.fieldDecoration(context, t.fixedAssetsVat, prefixIcon: Icons.receipt_long_outlined),
          ),
          if (_kind == 'major')
            TextFormField(
              controller: _lifeCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: FixedAssetsUi.numericFormatters(allowDecimal: false),
              decoration: FixedAssetsUi.fieldDecoration(
                context,
                t.fixedAssetsRemainingLife,
                prefixIcon: Icons.timelapse_outlined,
              ),
            ),
          FixedAssetCounterpartyPicker(
            businessId: widget.businessId,
            allowOpening: false,
            initialType: 'person',
            onChanged: (v) => _cp = v,
          ),
          DateInputField(
            value: _date,
            calendarController: widget.calendarController,
            labelText: t.fixedAssetsEffectiveDate,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            onChanged: (d) {
              if (d != null) setState(() => _date = d);
            },
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(onPressed: _submit, child: Text(t.save)),
      ],
    );
  }
}

class FixedAssetsEstimateDialog extends StatefulWidget {
  const FixedAssetsEstimateDialog({
    super.key,
    required this.calendarController,
    required this.asset,
  });

  final CalendarController calendarController;
  final Map<String, dynamic> asset;

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required CalendarController calendarController,
    required Map<String, dynamic> asset,
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => FixedAssetsEstimateDialog(calendarController: calendarController, asset: asset),
    );
  }

  @override
  State<FixedAssetsEstimateDialog> createState() => _FixedAssetsEstimateDialogState();
}

class _FixedAssetsEstimateDialogState extends State<FixedAssetsEstimateDialog> {
  late String _method;
  late final TextEditingController _lifeCtrl;
  late final TextEditingController _rateCtrl;
  DateTime _effective = DateTime.now();

  @override
  void initState() {
    super.initState();
    var method = '${widget.asset['method'] ?? 'straight_line'}';
    if (method == 'declining') method = 'declining_balance';
    _method = method == 'declining_balance' ? 'declining_balance' : 'straight_line';
    _lifeCtrl = TextEditingController(text: '${widget.asset['useful_life_months'] ?? ''}');
    _rateCtrl = TextEditingController(text: '${widget.asset['declining_annual_rate'] ?? ''}');
  }

  @override
  void dispose() {
    _lifeCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.pop(context, {
      'method': _method,
      'effective_date': _isoDate(_effective),
      if (_method == 'straight_line') 'remaining_useful_life_months': FixedAssetsUi.parseInt(_lifeCtrl.text),
      if (_method == 'declining_balance') 'declining_annual_rate': FixedAssetsUi.parseMoney(_rateCtrl.text),
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return FixedAssetsUi.dialogShell(
      context: context,
      title: t.fixedAssetsEstimateChange,
      icon: Icons.tune_outlined,
      child: FixedAssetsUi.spacedColumn([
        FixedAssetsUi.infoBanner(context, t.fixedAssetsEstimateHint),
        DropdownButtonFormField<String>(
          value: _method,
          decoration: FixedAssetsUi.fieldDecoration(
            context,
            t.fixedAssetsEstimateChange,
            prefixIcon: Icons.functions_outlined,
          ),
          items: [
            DropdownMenuItem(value: 'straight_line', child: Text(t.fixedAssetsMethodStraight)),
            DropdownMenuItem(value: 'declining_balance', child: Text(t.fixedAssetsMethodDeclining)),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _method = v);
          },
        ),
        if (_method == 'straight_line')
          TextFormField(
            controller: _lifeCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: FixedAssetsUi.numericFormatters(allowDecimal: false),
            decoration: FixedAssetsUi.fieldDecoration(
              context,
              t.fixedAssetsRemainingLife,
              prefixIcon: Icons.timelapse_outlined,
            ),
          ),
        if (_method == 'declining_balance')
          TextFormField(
            controller: _rateCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: FixedAssetsUi.fieldDecoration(
              context,
              t.fixedAssetsDecliningRate,
              hint: '0.25',
              prefixIcon: Icons.percent,
            ),
          ),
        DateInputField(
          value: _effective,
          calendarController: widget.calendarController,
          labelText: t.fixedAssetsEffectiveDate,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          onChanged: (d) {
            if (d != null) setState(() => _effective = d);
          },
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(onPressed: _submit, child: Text(t.save)),
      ],
    );
  }
}

class FixedAssetsIdleDialog extends StatefulWidget {
  const FixedAssetsIdleDialog({super.key, required this.calendarController});

  final CalendarController calendarController;

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required CalendarController calendarController,
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => FixedAssetsIdleDialog(calendarController: calendarController),
    );
  }

  @override
  State<FixedAssetsIdleDialog> createState() => _FixedAssetsIdleDialogState();
}

class _FixedAssetsIdleDialogState extends State<FixedAssetsIdleDialog> {
  DateTime _idleFrom = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return FixedAssetsUi.dialogShell(
      context: context,
      title: t.fixedAssetsMarkIdle,
      icon: Icons.pause_circle_outline,
      maxWidth: 460,
      child: FixedAssetsUi.spacedColumn([
        FixedAssetsUi.infoBanner(context, t.fixedAssetsIdleHint),
        DateInputField(
          value: _idleFrom,
          calendarController: widget.calendarController,
          labelText: t.fixedAssetsIdleFrom,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          onChanged: (d) {
            if (d != null) setState(() => _idleFrom = d);
          },
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(
          onPressed: () => Navigator.pop(context, {'idle_from': _isoDate(_idleFrom)}),
          child: Text(t.save),
        ),
      ],
    );
  }
}

class FixedAssetsDepreciationRunDialog extends StatefulWidget {
  const FixedAssetsDepreciationRunDialog({super.key});

  static Future<Map<String, dynamic>?> show(BuildContext context) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const FixedAssetsDepreciationRunDialog(),
    );
  }

  @override
  State<FixedAssetsDepreciationRunDialog> createState() => _FixedAssetsDepreciationRunDialogState();
}

class _FixedAssetsDepreciationRunDialogState extends State<FixedAssetsDepreciationRunDialog> {
  late final TextEditingController _yearCtrl;
  late final TextEditingController _monthCtrl;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _yearCtrl = TextEditingController(text: '${now.year}');
    _monthCtrl = TextEditingController(text: '${now.month}');
  }

  @override
  void dispose() {
    _yearCtrl.dispose();
    _monthCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final year = int.tryParse(_yearCtrl.text.trim());
    final month = int.tryParse(_monthCtrl.text.trim());
    if (year == null || month == null || month < 1 || month > 12) return;
    Navigator.pop(context, {'period_year': year, 'period_month': month});
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return FixedAssetsUi.dialogShell(
      context: context,
      title: t.fixedAssetsNewDepreciationRun,
      icon: Icons.calculate_outlined,
      maxWidth: 460,
      child: FixedAssetsUi.spacedColumn([
        FixedAssetsUi.infoBanner(context, t.fixedAssetsDepreciationGregorianHint),
        TextFormField(
          controller: _yearCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: FixedAssetsUi.numericFormatters(allowDecimal: false),
          decoration: FixedAssetsUi.fieldDecoration(context, t.fixedAssetsPeriodYear, prefixIcon: Icons.calendar_month),
        ),
        TextFormField(
          controller: _monthCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: FixedAssetsUi.numericFormatters(allowDecimal: false),
          decoration: FixedAssetsUi.fieldDecoration(context, t.fixedAssetsPeriodMonth, prefixIcon: Icons.date_range),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(onPressed: _submit, child: Text(t.save)),
      ],
    );
  }
}
