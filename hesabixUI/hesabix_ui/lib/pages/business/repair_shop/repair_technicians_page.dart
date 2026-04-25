import 'package:flutter/material.dart';
import '../../../services/repair_shop_service.dart';
import '../../../services/person_service.dart';
import '../../../models/repair_technician_model.dart';
import '../../../models/person_model.dart';
import '../../../core/api_client.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../utils/error_extractor.dart';


/// صفحه مدیریت تعمیرکاران
class RepairTechniciansPage extends StatefulWidget {
  final int businessId;

  const RepairTechniciansPage({
    super.key,
    required this.businessId,
  });

  @override
  State<RepairTechniciansPage> createState() => _RepairTechniciansPageState();
}

class _RepairTechniciansPageState extends State<RepairTechniciansPage> {
  late final RepairShopService _service;

  bool _isLoading = true;
  List<RepairTechnician> _technicians = [];
  String? _errorMessage;
  bool _showInactive = false;

  @override
  void initState() {
    super.initState();
    _service = RepairShopService(ApiClient());
    _loadTechnicians();
  }

  Future<void> _loadTechnicians() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final technicians = await _service.listTechnicians(
        businessId: widget.businessId,
        onlyActive: !_showInactive,
      );

      setState(() {
        _technicians = technicians;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage =
            'خطا در بارگذاری تعمیرکاران: ${ErrorExtractor.forContext(e, context)}';
        _isLoading = false;
      });
    }
  }

  Future<void> _createTechnician() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => _TechnicianFormDialog(
          businessId: widget.businessId,
        ),
      ),
    );

    if (result == true) {
      _loadTechnicians();
    }
  }

  Future<void> _editTechnician(RepairTechnician technician) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => _TechnicianFormDialog(
          businessId: widget.businessId,
          technician: technician,
        ),
      ),
    );

    if (result == true) {
      _loadTechnicians();
    }
  }

  Future<void> _deleteTechnician(RepairTechnician technician) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('غیرفعال کردن تعمیرکار'),
        content: Text(
            'آیا مطمئن هستید که می‌خواهید "${technician.personName}" را غیرفعال کنید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('خیر'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('بله، غیرفعال کن'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _service.deleteTechnician(
        businessId: widget.businessId,
        technicianId: technician.id,
      );

      if (mounted) {
        SnackBarHelper.show(context, message: 'تعمیرکار غیرفعال شد');
        _loadTechnicians();
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('مدیریت تعمیرکاران'),
        actions: [
          IconButton(
            icon: Icon(_showInactive
                ? Icons.visibility_off
                : Icons.visibility),
            onPressed: () {
              setState(() => _showInactive = !_showInactive);
              _loadTechnicians();
            },
            tooltip: _showInactive
                ? 'مخفی کردن غیرفعال‌ها'
                : 'نمایش غیرفعال‌ها',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTechnicians,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error, size: 64, color: colorScheme.error),
                      const SizedBox(height: 16),
                      Text(_errorMessage!),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadTechnicians,
                        child: const Text('تلاش مجدد'),
                      ),
                    ],
                  ),
                )
              : _technicians.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.engineering_outlined,
                            size: 80,
                            color: colorScheme.primary.withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 16),
                          const Text('هنوز تعمیرکاری ثبت نشده است'),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: _createTechnician,
                            icon: const Icon(Icons.add),
                            label: const Text('افزودن تعمیرکار'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _technicians.length,
                      itemBuilder: (context, index) {
                        final technician = _technicians[index];
                        return _buildTechnicianCard(
                            technician, theme, colorScheme);
                      },
                    ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createTechnician,
        icon: const Icon(Icons.add),
        label: const Text('تعمیرکار جدید'),
      ),
    );
  }

  Widget _buildTechnicianCard(
    RepairTechnician technician,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: technician.isActive
              ? colorScheme.primary
              : Colors.grey,
          child: Text(
            technician.personName[0].toUpperCase(),
            style: const TextStyle(color: Colors.white),
          ),
        ),
        title: Text(
          technician.personName,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: technician.isActive ? null : Colors.grey,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('کد: ${technician.code}'),
            Text(
              '${technician.commissionTypeLabel}: ${technician.formattedCommission}',
              style: TextStyle(
                color: colorScheme.primary,
                fontSize: 12,
              ),
            ),
            if (!technician.isActive)
              const Text(
                'غیرفعال',
                style: TextStyle(color: Colors.red, fontSize: 12),
              ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'edit':
                _editTechnician(technician);
                break;
              case 'delete':
                _deleteTechnician(technician);
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, size: 20),
                  SizedBox(width: 8),
                  Text('ویرایش'),
                ],
              ),
            ),
            if (technician.isActive)
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, size: 20, color: Colors.red),
                    SizedBox(width: 8),
                    Text('غیرفعال کردن', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// فرم افزودن/ویرایش تعمیرکار
class _TechnicianFormDialog extends StatefulWidget {
  final int businessId;
  final RepairTechnician? technician;

  const _TechnicianFormDialog({
    required this.businessId,
    this.technician,
  });

  @override
  State<_TechnicianFormDialog> createState() => _TechnicianFormDialogState();
}

class _TechnicianFormDialogState extends State<_TechnicianFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final RepairShopService _service;
  late final PersonService _personService;

  Person? _selectedPerson;
  final TextEditingController _codeController = TextEditingController();
  String _commissionType = 'percentage';
  final TextEditingController _commissionValueController =
      TextEditingController();
  bool _isActive = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final apiClient = ApiClient();
    _service = RepairShopService(apiClient);
    _personService = PersonService(apiClient: apiClient);
    if (widget.technician != null) {
      _loadTechnician();
    }
  }

  Future<void> _loadTechnician() async {
    final tech = widget.technician!;
    _codeController.text = tech.code;
    _commissionType = tech.commissionType;
    _commissionValueController.text = tech.commissionValue.toString();
    _isActive = tech.isActive;

    // بارگذاری Person - فعلاً skip می‌کنیم چون تنها نام می‌خواهیم
    setState(() => _selectedPerson = null);
  }

  @override
  void dispose() {
    _codeController.dispose();
    _commissionValueController.dispose();
    super.dispose();
  }

  Future<void> _selectPerson() async {
    final response = await _personService.getPersons(
      businessId: widget.businessId,
    );

    final items = response['items'] as List<dynamic>;
    final persons = items.map((e) => Person.fromJson(e as Map<String, dynamic>)).toList();

    if (!mounted) return;

    final selected = await showDialog<Person>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('انتخاب فرد'),
        children: persons.map((person) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(context, person),
            child: Text(person.aliasName),
          );
        }).toList(),
      ),
    );

    if (selected != null) {
      setState(() => _selectedPerson = selected);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedPerson == null && widget.technician == null) {
      SnackBarHelper.show(context, message: 'لطفاً فرد را انتخاب کنید');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final data = {
        'code': _codeController.text,
        'commission_type': _commissionType,
        'commission_value': double.parse(_commissionValueController.text),
        'is_active': _isActive,
      };

      if (widget.technician == null) {
        // ایجاد جدید
        data['person_id'] = _selectedPerson!.id!;
        await _service.createTechnician(
          businessId: widget.businessId,
          technicianData: data,
        );
      } else {
        // ویرایش
        await _service.updateTechnician(
          businessId: widget.businessId,
          technicianId: widget.technician!.id,
          technicianData: data,
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
            widget.technician == null ? 'تعمیرکار جدید' : 'ویرایش تعمیرکار'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _save,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // انتخاب فرد (فقط برای ایجاد جدید)
              if (widget.technician == null)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.person),
                    title: Text(_selectedPerson?.aliasName ?? 'انتخاب فرد'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: _selectPerson,
                  ),
                )
              else
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.person),
                    title: Text(_selectedPerson?.aliasName ?? widget.technician?.personName ?? 'در حال بارگذاری...'),
                  ),
                ),

              const SizedBox(height: 16),

              // کد تعمیرکار
              TextFormField(
                controller: _codeController,
                decoration: const InputDecoration(
                  labelText: 'کد تعمیرکار',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.qr_code),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'کد الزامی است';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // نوع حق‌الزحمه
              DropdownButtonFormField<String>(
                initialValue: _commissionType,
                decoration: const InputDecoration(
                  labelText: 'نوع حق‌الزحمه',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.payments),
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'fixed', child: Text('مبلغ ثابت')),
                  DropdownMenuItem(
                      value: 'percentage', child: Text('درصدی')),
                  DropdownMenuItem(
                      value: 'case_by_case', child: Text('موردی')),
                ],
                onChanged: (value) {
                  setState(() => _commissionType = value!);
                },
              ),

              const SizedBox(height: 16),

              // مقدار حق‌الزحمه
              if (_commissionType != 'case_by_case')
                TextFormField(
                  controller: _commissionValueController,
                  decoration: InputDecoration(
                    labelText: _commissionType == 'percentage'
                        ? 'درصد حق‌الزحمه'
                        : 'مبلغ حق‌الزحمه',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.percent),
                    helperText: _commissionType == 'percentage' 
                        ? 'درصد از دستمزد تعمیر'
                        : 'مبلغ ثابت به واحد ارز پیش‌فرض کسب‌وکار',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'مقدار الزامی است';
                    }
                    if (double.tryParse(value) == null) {
                      return 'عدد معتبر وارد کنید';
                    }
                    return null;
                  },
                ),

              const SizedBox(height: 16),

              // وضعیت فعال/غیرفعال
              SwitchListTile(
                title: const Text('فعال'),
                subtitle: const Text('تعمیرکار فعال برای اختصاص سفارش'),
                value: _isActive,
                onChanged: (value) {
                  setState(() => _isActive = value);
                },
              ),

              const SizedBox(height: 32),

              // دکمه ذخیره
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(_isSaving ? 'در حال ذخیره...' : 'ذخیره'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

