import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../widgets/data_table/data_table_widget.dart';
import '../../widgets/data_table/data_table_config.dart';
import '../../widgets/person/person_form_dialog.dart';
import '../../widgets/person/person_import_dialog.dart';
import '../../widgets/permission/permission_widgets.dart';
import '../../models/person_model.dart';
import '../../services/person_service.dart';
import '../../core/auth_store.dart';

class PersonsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const PersonsPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<PersonsPage> createState() => _PersonsPageState();
}

class _PersonsPageState extends State<PersonsPage> {
  final _personService = PersonService();
  final GlobalKey _personsTableKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    // بررسی دسترسی خواندن
    if (!widget.authStore.canReadSection('people')) {
      return AccessDeniedPage(
        message: 'شما دسترسی لازم برای مشاهده لیست اشخاص را ندارید',
      );
    }

    return Scaffold(
      body: DataTableWidget<Person>(
        key: _personsTableKey,
        config: _buildDataTableConfig(t),
        fromJson: Person.fromJson,
      ),
    );
  }

  DataTableConfig<Person> _buildDataTableConfig(AppLocalizations t) {
    return DataTableConfig<Person>(
      endpoint: '/api/v1/persons/businesses/${widget.businessId}/persons',
      title: t.personsList,
      excelEndpoint: '/api/v1/persons/businesses/${widget.businessId}/persons/export/excel',
      pdfEndpoint: '/api/v1/persons/businesses/${widget.businessId}/persons/export/pdf',
      getExportParams: () => {
        'business_id': widget.businessId,
      },
      showBackButton: true,
      onBack: () => Navigator.of(context).maybePop(),
      showTableIcon: false,
      showRowNumbers: true,
      enableRowSelection: true,
      enableMultiRowSelection: true,
      columns: [
        NumberColumn(
          'code',
          'کد شخص',
          width: ColumnWidth.small,
          formatter: (person) => (person.code?.toString() ?? '-'),
          textAlign: TextAlign.center,
        ),
        TextColumn(
          'alias_name',
          t.personAliasName,
          width: ColumnWidth.large,
          formatter: (person) => person.aliasName,
        ),
        TextColumn(
          'first_name',
          t.personFirstName,
          width: ColumnWidth.medium,
          formatter: (person) => person.firstName ?? '-',
        ),
        TextColumn(
          'last_name',
          t.personLastName,
          width: ColumnWidth.medium,
          formatter: (person) => person.lastName ?? '-',
        ),
        TextColumn(
          'person_type',
          t.personType,
          width: ColumnWidth.medium,
          formatter: (person) => (person.personTypes.isNotEmpty
              ? person.personTypes.map((e) => e.persianName).join('، ')
              : person.personType.persianName),
        ),
        TextColumn(
          'company_name',
          t.personCompanyName,
          width: ColumnWidth.medium,
          formatter: (person) => person.companyName ?? '-',
        ),
        TextColumn(
          'mobile',
          t.personMobile,
          width: ColumnWidth.medium,
          formatter: (person) => person.mobile ?? '-',
        ),
        TextColumn(
          'email',
          t.personEmail,
          width: ColumnWidth.large,
          formatter: (person) => person.email ?? '-',
        ),
        TextColumn(
          'national_id',
          t.personNationalId,
          width: ColumnWidth.medium,
          formatter: (person) => person.nationalId ?? '-',
        ),
        DateColumn(
          'created_at',
          'تاریخ ایجاد',
          width: ColumnWidth.medium,
        ),
        NumberColumn(
          'share_count',
          'تعداد سهام',
          width: ColumnWidth.small,
          textAlign: TextAlign.center,
          decimalPlaces: 0,
        ),
        NumberColumn(
          'commission_sale_percent',
          'درصد پورسانت فروش',
          width: ColumnWidth.medium,
          decimalPlaces: 2,
          suffix: '٪',
        ),
        NumberColumn(
          'commission_sales_return_percent',
          'درصد پورسانت برگشت از فروش',
          width: ColumnWidth.medium,
          decimalPlaces: 2,
          suffix: '٪',
        ),
        NumberColumn(
          'commission_sales_amount',
          'مبلغ پورسانت فروش',
          width: ColumnWidth.large,
          decimalPlaces: 0,
        ),
        NumberColumn(
          'commission_sales_return_amount',
          'مبلغ پورسانت برگشت از فروش',
          width: ColumnWidth.large,
          decimalPlaces: 0,
        ),
        TextColumn(
          'payment_id',
          t.personPaymentId,
          width: ColumnWidth.medium,
          formatter: (person) => person.paymentId ?? '-',
        ),
        TextColumn(
          'registration_number',
          t.personRegistrationNumber,
          width: ColumnWidth.medium,
          formatter: (person) => person.registrationNumber ?? '-',
        ),
        TextColumn(
          'economic_id',
          t.personEconomicId,
          width: ColumnWidth.medium,
          formatter: (person) => person.economicId ?? '-',
        ),
        TextColumn(
          'country',
          t.personCountry,
          width: ColumnWidth.medium,
          formatter: (person) => person.country ?? '-',
        ),
        TextColumn(
          'province',
          t.personProvince,
          width: ColumnWidth.medium,
          formatter: (person) => person.province ?? '-',
        ),
        TextColumn(
          'city',
          t.personCity,
          width: ColumnWidth.medium,
          formatter: (person) => person.city ?? '-',
        ),
        TextColumn(
          'address',
          t.personAddress,
          width: ColumnWidth.extraLarge,
          formatter: (person) => person.address ?? '-',
        ),
        TextColumn(
          'postal_code',
          t.personPostalCode,
          width: ColumnWidth.medium,
          formatter: (person) => person.postalCode ?? '-',
        ),
        TextColumn(
          'phone',
          t.personPhone,
          width: ColumnWidth.medium,
          formatter: (person) => person.phone ?? '-',
        ),
        TextColumn(
          'fax',
          t.personFax,
          width: ColumnWidth.medium,
          formatter: (person) => person.fax ?? '-',
        ),
        TextColumn(
          'website',
          t.personWebsite,
          width: ColumnWidth.large,
          formatter: (person) => person.website ?? '-',
        ),
        ActionColumn(
          'actions',
          'عملیات',
          actions: [
            DataTableAction(
              icon: Icons.edit,
              label: t.edit,
              onTap: (person) => _editPerson(person),
            ),
            DataTableAction(
              icon: Icons.delete,
              label: t.delete,
              color: Colors.red,
              onTap: (person) => _deletePerson(person),
            ),
          ],
        ),
      ],
      searchFields: [
        'code',
        'alias_name',
        'first_name',
        'last_name',
        'company_name',
        'mobile',
        'email',
        'national_id',
      ],
      filterFields: [
        'person_type',
        'person_types',
        'is_active',
        'country',
        'province',
      ],
      defaultPageSize: 20,
      // انتقال دکمه افزودن به اکشن‌های هدر جدول با کنترل دسترسی
      customHeaderActions: [
        PermissionButton(
          section: 'people',
          action: 'add',
          authStore: widget.authStore,
          child: Tooltip(
            message: t.addPerson,
            child: IconButton(
              onPressed: _addPerson,
              icon: const Icon(Icons.add),
            ),
          ),
        ),
        Tooltip(
          message: 'ایمپورت اشخاص از اکسل',
          child: IconButton(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (context) => PersonImportDialog(businessId: widget.businessId),
              );
              if (ok == true) {
                final state = _personsTableKey.currentState;
                try {
                  // ignore: avoid_dynamic_calls
                  (state as dynamic)?.refresh();
                } catch (_) {}
              }
            },
            icon: const Icon(Icons.upload_file),
          ),
        ),
      ],
    );
  }


  void _addPerson() {
    showDialog(
      context: context,
      builder: (context) => PersonFormDialog(
        businessId: widget.businessId,
        onSuccess: () {
          final state = _personsTableKey.currentState;
          try {
            // Call public refresh() via dynamic to avoid private state typing
            // ignore: avoid_dynamic_calls
            (state as dynamic)?.refresh();
          } catch (_) {}
        },
      ),
    );
  }

  void _editPerson(Person person) {
    showDialog(
      context: context,
      builder: (context) => PersonFormDialog(
        businessId: widget.businessId,
        person: person,
        onSuccess: () {
          final state = _personsTableKey.currentState;
          try {
            // ignore: avoid_dynamic_calls
            (state as dynamic)?.refresh();
          } catch (_) {}
        },
      ),
    );
  }

  void _deletePerson(Person person) {
    final t = AppLocalizations.of(context);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.deletePerson),
        content: Text('آیا از حذف شخص "${person.displayName}" مطمئن هستید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _performDelete(person);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(t.delete),
          ),
        ],
      ),
    );
  }

  Future<void> _performDelete(Person person) async {
    try {
      await _personService.deletePerson(person.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).personDeletedSuccessfully),
            backgroundColor: Colors.green,
          ),
        );
        // DataTableWidget will automatically refresh
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در حذف شخص: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
