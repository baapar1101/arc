import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../widgets/data_table/data_table_widget.dart';
import '../../widgets/data_table/data_table_config.dart';
import '../../widgets/person/person_form_dialog.dart';
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
      appBar: AppBar(
        title: Text(t.personsList),
        actions: [
          // دکمه اضافه کردن فقط در صورت داشتن دسترسی
          PermissionButton(
            section: 'people',
            action: 'add',
            authStore: widget.authStore,
            child: IconButton(
              onPressed: _addPerson,
              icon: const Icon(Icons.add),
              tooltip: t.addPerson,
            ),
          ),
        ],
      ),
      body: DataTableWidget<Person>(
        config: _buildDataTableConfig(t),
        fromJson: Person.fromJson,
      ),
    );
  }

  DataTableConfig<Person> _buildDataTableConfig(AppLocalizations t) {
    return DataTableConfig<Person>(
      endpoint: '/api/v1/persons/businesses/${widget.businessId}/persons',
      title: t.personsList,
      columns: [
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
          formatter: (person) => person.personType.persianName,
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
          'is_active',
          'وضعیت',
          width: ColumnWidth.small,
          formatter: (person) => person.isActive ? 'فعال' : 'غیرفعال',
        ),
        DateColumn(
          'created_at',
          'تاریخ ایجاد',
          width: ColumnWidth.medium,
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
        'is_active',
        'country',
        'province',
      ],
      defaultPageSize: 20,
    );
  }


  void _addPerson() {
    showDialog(
      context: context,
      builder: (context) => PersonFormDialog(
        businessId: widget.businessId,
        onSuccess: () {
          // DataTableWidget will automatically refresh
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
          // DataTableWidget will automatically refresh
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
