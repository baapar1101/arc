import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/warehouse_model.dart';
import '../../services/warehouse_service.dart';
import '../../utils/snackbar_helper.dart';

class WarehouseFormDialog extends StatefulWidget {
  final int businessId;
  final Warehouse? warehouse; // null برای افزودن، مقدار برای ویرایش
  final VoidCallback? onSuccess;

  const WarehouseFormDialog({
    super.key,
    required this.businessId,
    this.warehouse,
    this.onSuccess,
  });

  @override
  State<WarehouseFormDialog> createState() => _WarehouseFormDialogState();
}

class _WarehouseFormDialogState extends State<WarehouseFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _warehouseService = WarehouseService();
  bool _isLoading = false;
  String? _errorMessage;

  // Code controls
  final _codeController = TextEditingController();
  bool _autoGenerateCode = true;

  // Controllers
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _warehouseKeeperController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _postalCodeController = TextEditingController();

  bool _isDefault = false;

  @override
  void initState() {
    super.initState();
    _initializeForm();
  }

  void _initializeForm() {
    if (widget.warehouse != null) {
      final warehouse = widget.warehouse!;
      _codeController.text = warehouse.code;
      _autoGenerateCode = false; // در حالت ویرایش، کد همیشه دستی است
      _nameController.text = warehouse.name;
      _descriptionController.text = warehouse.description ?? '';
      _warehouseKeeperController.text = warehouse.warehouseKeeper ?? '';
      _phoneController.text = warehouse.phone ?? '';
      _addressController.text = warehouse.address ?? '';
      _postalCodeController.text = warehouse.postalCode ?? '';
      _isDefault = warehouse.isDefault;
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _warehouseKeeperController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _postalCodeController.dispose();
    super.dispose();
  }

  Future<void> _saveWarehouse() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final warehouseData = {
        'code': _autoGenerateCode ? null : (_codeController.text.trim().isEmpty ? null : _codeController.text.trim()),
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
        'warehouse_keeper': _warehouseKeeperController.text.trim().isEmpty ? null : _warehouseKeeperController.text.trim(),
        'phone': _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        'address': _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
        'postal_code': _postalCodeController.text.trim().isEmpty ? null : _postalCodeController.text.trim(),
        'is_default': _isDefault,
      };

      if (widget.warehouse == null) {
        // Create new warehouse
        await _warehouseService.createWarehouse(
          businessId: widget.businessId,
          payload: warehouseData,
        );
      } else {
        // Update existing warehouse
        await _warehouseService.updateWarehouse(
          businessId: widget.businessId,
          warehouseId: widget.warehouse!.id!,
          payload: warehouseData,
        );
      }

      if (mounted) {
        Navigator.of(context).pop(true);
        widget.onSuccess?.call();
        SnackBarHelper.showSuccess(context, message: widget.warehouse == null 
              ? 'انبار با موفقیت ایجاد شد'
              : 'انبار با موفقیت به‌روزرسانی شد');
      }
    } catch (e) {
      if (mounted) {
        final errorStr = e.toString();
        if (errorStr.contains('DUPLICATE_WAREHOUSE_CODE') || errorStr.contains('تکراری')) {
          setState(() {
            _errorMessage = 'کد انبار تکراری است. لطفاً کد دیگری انتخاب کنید.';
          });
        } else {
          setState(() {
            _errorMessage = 'خطا: $e';
          });
        }
        SnackBarHelper.showError(context, message: 'خطا: $e');
      }
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
    final theme = Theme.of(context);
    final isEditing = widget.warehouse != null;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 900;

    final screenHeight = MediaQuery.of(context).size.height;
    
    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
        ),
        child: Container(
        width: screenWidth,
        height: screenHeight,
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.primary.withValues(alpha: 0.8),
                  ],
                ),
                borderRadius: BorderRadius.zero,
              ),
              child: Row(
                children: [
                  Icon(
                    isEditing ? Icons.edit : Icons.add,
                    color: theme.colorScheme.onPrimary,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isEditing ? 'ویرایش انبار' : 'افزودن انبار',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    color: theme.colorScheme.onPrimary,
                  ),
                ],
              ),
            ),

            // Form
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // کد انبار با سویچ تولید خودکار/دستی
                      _buildCodeSection(theme, isDesktop),
                      const SizedBox(height: 20),

                      // اطلاعات پایه
                      _buildBasicInfoSection(theme, isDesktop),
                      const SizedBox(height: 20),

                      // اطلاعات تماس
                      _buildContactInfoSection(theme, isDesktop),
                      const SizedBox(height: 20),

                      // تنظیمات
                      _buildSettingsSection(theme, isDesktop),

                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade300),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline, color: Colors.red.shade700),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: TextStyle(color: Colors.red.shade700),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // Footer (دکمه‌ها)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.zero,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                    child: const Text('انصراف'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _isLoading ? null : _saveWarehouse,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('ذخیره'),
                  ),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildCodeSection(ThemeData theme, bool isDesktop) {
    if (isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'کد انبار',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  value: _autoGenerateCode,
                  onChanged: widget.warehouse != null
                      ? null
                      : (value) {
                          setState(() {
                            _autoGenerateCode = value;
                            if (value) {
                              _codeController.clear();
                            }
                          });
                        },
                  title: const Text('تولید خودکار کد'),
                  subtitle: const Text('کد به صورت خودکار تولید می‌شود'),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: TextFormField(
              controller: _codeController,
              enabled: !_autoGenerateCode || widget.warehouse != null,
              decoration: InputDecoration(
                labelText: 'کد',
                hintText: _autoGenerateCode ? 'کد به صورت خودکار تولید می‌شود' : 'کد انبار را وارد کنید',
                prefixIcon: const Icon(Icons.qr_code),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: _autoGenerateCode,
                fillColor: theme.colorScheme.surfaceVariant.withValues(alpha: 0.3),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              validator: (value) {
                if (!_autoGenerateCode && (value == null || value.trim().isEmpty)) {
                  return 'لطفاً کد انبار را وارد کنید';
                }
                return null;
              },
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'کد انبار',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        // سویچ تولید خودکار/دستی
        Row(
          children: [
            Expanded(
              child: SwitchListTile(
                value: _autoGenerateCode,
                onChanged: widget.warehouse != null
                    ? null // در حالت ویرایش غیرفعال
                    : (value) {
                        setState(() {
                          _autoGenerateCode = value;
                          if (value) {
                            _codeController.clear();
                          }
                        });
                      },
                title: const Text('تولید خودکار کد'),
                subtitle: const Text('کد به صورت خودکار تولید می‌شود'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // فیلد کد
        TextFormField(
          controller: _codeController,
          enabled: !_autoGenerateCode || widget.warehouse != null,
          decoration: InputDecoration(
            labelText: 'کد',
            hintText: _autoGenerateCode ? 'کد به صورت خودکار تولید می‌شود' : 'کد انبار را وارد کنید',
            prefixIcon: const Icon(Icons.qr_code),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: _autoGenerateCode,
            fillColor: theme.colorScheme.surfaceVariant.withValues(alpha: 0.3),
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
          ],
          validator: (value) {
            if (!_autoGenerateCode && (value == null || value.trim().isEmpty)) {
              return 'لطفاً کد انبار را وارد کنید';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildBasicInfoSection(ThemeData theme, bool isDesktop) {
    if (isDesktop) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'اطلاعات پایه',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'نام انبار *',
                    prefixIcon: const Icon(Icons.warehouse),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'لطفاً نام انبار را وارد کنید';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  controller: _descriptionController,
                  decoration: InputDecoration(
                    labelText: 'توضیحات',
                    prefixIcon: const Icon(Icons.description),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  maxLines: 3,
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'اطلاعات پایه',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _nameController,
          decoration: InputDecoration(
            labelText: 'نام انبار *',
            prefixIcon: const Icon(Icons.warehouse),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'لطفاً نام انبار را وارد کنید';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _descriptionController,
          decoration: InputDecoration(
            labelText: 'توضیحات',
            prefixIcon: const Icon(Icons.description),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          maxLines: 3,
        ),
      ],
    );
  }

  Widget _buildContactInfoSection(ThemeData theme, bool isDesktop) {
    if (isDesktop) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'اطلاعات تماس',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          // ردیف اول: انباردار و تلفن
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _warehouseKeeperController,
                  decoration: InputDecoration(
                    labelText: 'انباردار',
                    prefixIcon: const Icon(Icons.person),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  controller: _phoneController,
                  decoration: InputDecoration(
                    labelText: 'تلفن',
                    prefixIcon: const Icon(Icons.phone),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // ردیف دوم: آدرس و کد پستی
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _addressController,
                  decoration: InputDecoration(
                    labelText: 'آدرس',
                    prefixIcon: const Icon(Icons.location_on),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  maxLines: 3,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  controller: _postalCodeController,
                  decoration: InputDecoration(
                    labelText: 'کد پستی',
                    prefixIcon: const Icon(Icons.markunread_mailbox),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'اطلاعات تماس',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _warehouseKeeperController,
          decoration: InputDecoration(
            labelText: 'انباردار',
            prefixIcon: const Icon(Icons.person),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _phoneController,
          decoration: InputDecoration(
            labelText: 'تلفن',
            prefixIcon: const Icon(Icons.phone),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _addressController,
          decoration: InputDecoration(
            labelText: 'آدرس',
            prefixIcon: const Icon(Icons.location_on),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _postalCodeController,
          decoration: InputDecoration(
            labelText: 'کد پستی',
            prefixIcon: const Icon(Icons.markunread_mailbox),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
        ),
      ],
    );
  }

  Widget _buildSettingsSection(ThemeData theme, bool isDesktop) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'تنظیمات',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
          ),
          child: CheckboxListTile(
            value: _isDefault,
            onChanged: (value) {
              setState(() {
                _isDefault = value ?? false;
              });
            },
            title: const Text('انبار پیش‌فرض'),
            subtitle: const Text('این انبار به عنوان انبار پیش‌فرض انتخاب می‌شود'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ),
      ],
    );
  }
}

