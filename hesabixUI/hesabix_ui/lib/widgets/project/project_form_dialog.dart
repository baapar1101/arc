import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/models/project_model.dart';
import 'package:hesabix_ui/services/project_service.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/widgets/invoice/person_combobox_widget.dart';
import 'package:hesabix_ui/widgets/banking/currency_picker_widget.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart';
import '../../models/person_model.dart';

/// دیالوگ ایجاد یا ویرایش پروژه
class ProjectFormDialog extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  final ProjectModel? project; // null = ایجاد جدید, not null = ویرایش
  final VoidCallback? onSuccess;

  const ProjectFormDialog({
    super.key,
    required this.businessId,
    required this.calendarController,
    this.project,
    this.onSuccess,
  });

  @override
  State<ProjectFormDialog> createState() => _ProjectFormDialogState();
}

class _ProjectFormDialogState extends State<ProjectFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final ProjectService _projectService;
  
  // Controllers
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _budgetController = TextEditingController();
  
  // State
  bool _autoGenerateCode = true;
  String _status = 'active';
  DateTime? _startDate;
  DateTime? _endDate;
  int? _currencyId;
  int? _managerUserId;
  Person? _selectedPerson;
  bool _isActive = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _projectService = ProjectService(ApiClient());
    _initializeForm();
  }

  void _initializeForm() {
    if (widget.project != null) {
      final project = widget.project!;
      _codeController.text = project.code;
      _autoGenerateCode = false;
      _nameController.text = project.name;
      _descriptionController.text = project.description ?? '';
      _status = project.status;
      _startDate = project.startDate;
      _endDate = project.endDate;
      if (project.budget != null) {
        _budgetController.text = project.budget!.toStringAsFixed(0);
      }
      _currencyId = project.currencyId;
      _managerUserId = project.managerUserId;
      // TODO: بارگذاری شخص انتخاب‌شده اگر person_id موجود باشد
      _isActive = project.isActive;
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  String _generateProjectCode() {
    // تولید کد خودکار بر اساس timestamp
    final now = DateTime.now();
    return 'PRJ-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final data = <String, dynamic>{
        'name': _nameController.text.trim(),
        'status': _status,
        'is_active': _isActive,
      };

      // کد پروژه
      if (_autoGenerateCode) {
        // تولید خودکار کد
        data['code'] = _generateProjectCode();
      } else if (_codeController.text.trim().isNotEmpty) {
        // استفاده از کد دستی
        data['code'] = _codeController.text.trim();
      } else {
        // اگر نه خودکار و نه دستی، خطا
        setState(() => _isLoading = false);
        if (mounted) {
          SnackBarHelper.showError(context, message: 'لطفاً کد پروژه را وارد کنید');
        }
        return;
      }

      // فیلدهای اختیاری
      if (_descriptionController.text.trim().isNotEmpty) {
        data['description'] = _descriptionController.text.trim();
      }
      
      if (_startDate != null) {
        data['start_date'] = _startDate!.toIso8601String();
      }
      
      if (_endDate != null) {
        data['end_date'] = _endDate!.toIso8601String();
      }
      
      if (_budgetController.text.trim().isNotEmpty) {
        final budget = double.tryParse(toEnglishDigits(_budgetController.text.trim()));
        if (budget != null) {
          data['budget'] = budget;
        }
      }
      
      if (_currencyId != null) {
        data['currency_id'] = _currencyId;
      }
      
      if (_managerUserId != null) {
        data['manager_user_id'] = _managerUserId;
      }
      
      if (_selectedPerson != null) {
        data['person_id'] = _selectedPerson!.id;
      }

      if (widget.project == null) {
        // ایجاد پروژه جدید
        await _projectService.createProject(
          businessId: widget.businessId,
          data: data,
        );
        
        if (!mounted) return;
        SnackBarHelper.showSuccess(context, message: 'پروژه با موفقیت ایجاد شد');
      } else {
        // ویرایش پروژه
        await _projectService.updateProject(
          projectId: widget.project!.id,
          data: data,
        );
        
        if (!mounted) return;
        SnackBarHelper.showSuccess(context, message: 'پروژه با موفقیت ویرایش شد');
      }

      if (widget.onSuccess != null) {
        widget.onSuccess!();
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: 'خطا: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.project != null;
    
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width > 800 ? 700 : MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isEditing ? Icons.edit : Icons.add_box,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isEditing ? 'ویرایش پروژه' : 'افزودن پروژه جدید',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ],
              ),
            ),
            
            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // کد پروژه
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _codeController,
                              enabled: !_autoGenerateCode,
                              decoration: const InputDecoration(
                                labelText: 'کد پروژه',
                                hintText: 'خودکار',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.tag),
                              ),
                              validator: (value) {
                                if (!_autoGenerateCode && (value == null || value.trim().isEmpty)) {
                                  return 'کد پروژه الزامی است';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 150,
                            child: CheckboxListTile(
                              title: const Text('خودکار', style: TextStyle(fontSize: 12)),
                              value: _autoGenerateCode,
                              onChanged: (value) {
                                setState(() {
                                  _autoGenerateCode = value ?? true;
                                  if (_autoGenerateCode) {
                                    _codeController.clear();
                                  }
                                });
                              },
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // نام پروژه
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'نام پروژه *',
                          hintText: 'مثال: پروژه توسعه نرم‌افزار',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.business_center),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'نام پروژه الزامی است';
                          }
                          return null;
                        },
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 16),
                      
                      // توضیحات
                      TextFormField(
                        controller: _descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'توضیحات',
                          hintText: 'توضیحات تکمیلی درباره پروژه',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.description),
                        ),
                        maxLines: 3,
                        textInputAction: TextInputAction.newline,
                      ),
                      const SizedBox(height: 16),
                      
                      // وضعیت پروژه
                      DropdownButtonFormField<String>(
                        value: _status,
                        decoration: const InputDecoration(
                          labelText: 'وضعیت پروژه',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.flag),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'active', child: Text('فعال')),
                          DropdownMenuItem(value: 'completed', child: Text('تکمیل شده')),
                          DropdownMenuItem(value: 'on_hold', child: Text('معلق')),
                          DropdownMenuItem(value: 'cancelled', child: Text('لغو شده')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _status = value;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      // تاریخ شروع و پایان
                      Row(
                        children: [
                          Expanded(
                            child: DateInputField(
                              calendarController: widget.calendarController,
                              labelText: 'تاریخ شروع',
                              value: _startDate,
                              onChanged: (date) {
                                setState(() {
                                  _startDate = date;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DateInputField(
                              calendarController: widget.calendarController,
                              labelText: 'تاریخ پایان',
                              value: _endDate,
                              onChanged: (date) {
                                setState(() {
                                  _endDate = date;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // بودجه و ارز
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _budgetController,
                              decoration: const InputDecoration(
                                labelText: 'بودجه',
                                hintText: '0',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.attach_money),
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'[0-9۰-۹.]')),
                              ],
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 1,
                            child: CurrencyPickerWidget(
                              businessId: widget.businessId,
                              selectedCurrencyId: _currencyId,
                              onChanged: (currencyId) {
                                setState(() {
                                  _currencyId = currencyId;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // مشتری/تامین‌کننده
                      PersonComboboxWidget(
                        businessId: widget.businessId,
                        selectedPerson: _selectedPerson,
                        onChanged: (person) {
                          setState(() {
                            _selectedPerson = person;
                          });
                        },
                        label: 'مشتری/تامین‌کننده',
                        hintText: 'جست‌وجو و انتخاب مشتری یا تامین‌کننده (اختیاری)',
                        isRequired: false,
                      ),
                      const SizedBox(height: 16),
                      
                      // TODO: مدیر پروژه (انتخاب از کاربران)
                      // این بخش نیاز به ویجت انتخاب کاربر دارد که فعلاً نداریم
                      // می‌توان در آینده اضافه کرد
                      
                      // فعال/غیرفعال
                      SwitchListTile(
                        title: const Text('پروژه فعال است'),
                        subtitle: const Text('پروژه‌های غیرفعال در لیست‌ها نمایش داده نمی‌شوند'),
                        value: _isActive,
                        onChanged: (value) {
                          setState(() {
                            _isActive = value;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).dividerColor,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                    child: const Text('انصراف'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _save,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(isEditing ? 'ذخیره تغییرات' : 'ایجاد پروژه'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

