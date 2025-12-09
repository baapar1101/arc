import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/api_client.dart';
import '../../widgets/data_table/data_table_widget.dart';
import '../../widgets/data_table/data_table_config.dart';
import '../../widgets/person/person_form_dialog.dart';
import '../../widgets/person/person_import_dialog.dart';
import '../../widgets/permission/permission_widgets.dart';
import '../../models/person_model.dart';
import '../../services/person_service.dart';
import '../../core/auth_store.dart';
import 'person_details_dialog.dart';
import '../../utils/snackbar_helper.dart';

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
      showExportButtons: true,
      businessId: widget.businessId,
      reportModuleKey: 'persons',
      reportSubtype: 'list',
      getExportParams: () => {
        'business_id': widget.businessId,
      },
      showBackButton: true,
      onBack: () {
        if (!mounted) return;
        if (context.canPop()) {
          context.pop();
        }
      },
      showTableIcon: false,
      showRowNumbers: true,
      enableRowSelection: true,
      enableMultiRowSelection: true,
      columns: [
        CustomColumn(
          'code',
          t.personCode,
          width: ColumnWidth.small,
          sortable: true,
          formatter: (person) => (person.code?.toString() ?? '-'),
          builder: (person, index) {
            final codeText = person.code?.toString() ?? '-';
            return InkWell(
              onTap: () {
                if (person.id != null) {
                  context.go(
                    '/business/${widget.businessId}/reports/kardex',
                    extra: {
                      'person_ids': [person.id]
                    },
                  );
                }
              },
              child: Text(
                codeText,
                textAlign: TextAlign.center,
                style: const TextStyle(decoration: TextDecoration.underline),
              ),
            );
          },
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
          filterType: ColumnFilterType.multiSelect,
          filterOptions: [
            FilterOption(value: 'مشتری', label: t.personTypeCustomer),
            FilterOption(value: 'بازاریاب', label: t.personTypeMarketer),
            FilterOption(value: 'کارمند', label: t.personTypeEmployee),
            FilterOption(value: 'تامین‌کننده', label: t.personTypeSupplier),
            FilterOption(value: 'همکار', label: t.personTypePartner),
            FilterOption(value: 'فروشنده', label: t.personTypeSeller),
            FilterOption(value: 'سهامدار', label: 'سهامدار'),
          ],
          formatter: (person) => person.personTypes.map((e) => e.persianName).join('، '),
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
        NumberColumn(
          'share_count',
          t.shareCount,
          width: ColumnWidth.small,
          textAlign: TextAlign.center,
          decimalPlaces: 0,
        ),
        NumberColumn(
          'commission_sale_percent',
          t.commissionSalePercentLabel,
          width: ColumnWidth.medium,
          decimalPlaces: 2,
          suffix: '٪',
        ),
        NumberColumn(
          'commission_sales_return_percent',
          t.commissionSalesReturnPercentLabel,
          width: ColumnWidth.medium,
          decimalPlaces: 2,
          suffix: '٪',
        ),
        NumberColumn(
          'commission_sales_amount',
          t.commissionSalesAmountLabel,
          width: ColumnWidth.large,
          decimalPlaces: 0,
        ),
        NumberColumn(
          'commission_sales_return_amount',
          t.commissionSalesReturnAmountLabel,
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
        CustomColumn(
          'balance',
          'تراز',
          width: ColumnWidth.medium,
          sortable: true,
          formatter: (person) {
            final balance = person.balance ?? 0.0;
            final formatter = NumberFormat('#,##0', 'en_US');
            return formatter.format(balance);
          },
          builder: (person, index) {
            final balance = person.balance ?? 0.0;
            final formatter = NumberFormat('#,##0', 'en_US');
            final formattedBalance = formatter.format(balance);
            
            Color balanceColor;
            if (balance > 0) {
              balanceColor = Colors.green;
            } else if (balance < 0) {
              balanceColor = Colors.red;
            } else {
              balanceColor = Colors.grey;
            }
            
            return Text(
              formattedBalance,
              style: TextStyle(
                color: balanceColor,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            );
          },
        ),
        CustomColumn(
          'status',
          'وضعیت',
          width: ColumnWidth.medium,
          filterType: ColumnFilterType.multiSelect,
          filterOptions: [
            FilterOption(value: 'بستانکار', label: 'بستانکار'),
            FilterOption(value: 'بدهکار', label: 'بدهکار'),
            FilterOption(value: 'بالانس', label: 'بالانس'),
            FilterOption(value: 'بدون تراکنش', label: 'بدون تراکنش'),
          ],
          formatter: (person) => person.status ?? '-',
          builder: (person, index) {
            final status = person.status ?? '-';
            Color statusColor;
            switch (status) {
              case 'بستانکار':
                statusColor = Colors.green;
                break;
              case 'بدهکار':
                statusColor = Colors.red;
                break;
              case 'بالانس':
                statusColor = Colors.blue;
                break;
              case 'بدون تراکنش':
                statusColor = Colors.grey;
                break;
              default:
                statusColor = Colors.black;
            }
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: statusColor.withValues(alpha: 0.3)),
              ),
              child: Text(
                status,
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            );
          },
        ),
        ActionColumn(
          'actions',
          t.actions,
          actions: [
            DataTableAction(
              icon: Icons.view_kanban,
              label: 'کاردکس',
              onTap: (person) {
                if (person is Person && person.id != null) {
                  context.go(
                    '/business/${widget.businessId}/reports/kardex',
                    extra: {
                      'person_ids': [person.id]
                    },
                  );
                } else if (person is Map<String, dynamic>) {
                  final id = person['id'];
                  if (id is int) {
                    context.go(
                      '/business/${widget.businessId}/reports/kardex',
                      extra: {
                        'person_ids': [id]
                      },
                    );
                  }
                }
              },
            ),
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
        if (widget.authStore.canDeleteSection('people'))
          Tooltip(
            message: AppLocalizations.of(context).deletePerson,
            child: IconButton(
              onPressed: () async {
                final t = AppLocalizations.of(context);
                try {
                  final state = _personsTableKey.currentState as dynamic;
                  final items = (state?.getSelectedItems() as List<dynamic>?) ?? const <dynamic>[];
                  if (items.isEmpty) {
                    SnackBarHelper.showError(context, message: t.noRowsSelectedError);
                    return;
                  }
                  final ids = <int>[];
                  for (final row in items) {
                    if (row is Person && row.id != null) {
                      ids.add(row.id!);
                    } else if (row is Map<String, dynamic>) {
                      final id = row['id'];
                      if (id is int) ids.add(id);
                    }
                  }
                  if (ids.isEmpty) return;

                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(t.deletePerson),
                      content: Text(t.deleteConfirm('${ids.length}')),
                      actions: [
                        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t.cancel)),
                        FilledButton.tonal(onPressed: () => Navigator.of(ctx).pop(true), child: Text(t.delete)),
                      ],
                    ),
                  );
                  if (confirm != true) return;

                  final client = ApiClient();
                  await client.post<Map<String, dynamic>>(
                    '/api/v1/persons/businesses/${widget.businessId}/persons/bulk-delete',
                    data: { 'ids': ids },
                  );
                  try { ( _personsTableKey.currentState as dynamic)?.refresh(); } catch (_) {}
                  if (mounted) {
                    // Reuse generic success text available in l10n
                    SnackBarHelper.show(context, message: t.productsDeletedSuccessfully);
                  }
                } catch (e) {
                  if (mounted) {
                    final t = AppLocalizations.of(context);
                    SnackBarHelper.showError(context, message: '${t.error}: $e');
                  }
                }
              },
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          ),
        Builder(builder: (context) {
          final theme = Theme.of(context);
          return Tooltip(
            message: t.importFromExcel,
            child: GestureDetector(
              onTap: () async {
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
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
                child: Icon(
                  Icons.upload_file,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        }),
      ],
      onRowTap: (item) {
        if (item is Person) {
          _showPersonDetails(item);
        }
      },
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

  void _showPersonDetails(Person person) {
    if (person.id == null) return;
    showDialog(
      context: context,
      builder: (context) => PersonDetailsDialog(
        businessId: widget.businessId,
        person: person,
        authStore: widget.authStore,
      ),
    );
  }
}
