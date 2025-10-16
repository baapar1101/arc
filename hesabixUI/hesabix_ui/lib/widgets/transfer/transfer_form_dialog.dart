import 'package:flutter/material.dart';
import '../../core/calendar_controller.dart';
import '../../services/bank_account_service.dart';
import '../../services/cash_register_service.dart';
import '../../services/petty_cash_service.dart';
import '../date_input_field.dart';

class TransferFormDialog extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  final VoidCallback? onSuccess;

  const TransferFormDialog({
    super.key,
    required this.businessId,
    required this.calendarController,
    this.onSuccess,
  });

  @override
  State<TransferFormDialog> createState() => _TransferFormDialogState();
}

class _TransferFormDialogState extends State<TransferFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _commissionController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  bool _isLoading = false;
  DateTime _transferDate = DateTime.now();
  
  // سرویس‌ها
  final BankAccountService _bankService = BankAccountService();
  final CashRegisterService _cashRegisterService = CashRegisterService();
  final PettyCashService _pettyCashService = PettyCashService();
  
  // انتخاب مبدا و مقصد
  String? _fromType = 'bank'; // پیش‌فرض بانک
  String? _toType = 'bank';   // پیش‌فرض بانک
  int? _fromId;
  int? _toId;
  
  // لیست‌های داده
  List<Map<String, dynamic>> _banks = [];
  List<Map<String, dynamic>> _cashRegisters = [];
  List<Map<String, dynamic>> _pettyCashList = [];
  
  bool _isDataLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _commissionController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (_isDataLoaded) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      // بارگذاری لیست بانک‌ها
      final bankResponse = await _bankService.list(
        businessId: widget.businessId,
        queryInfo: {'take': 100, 'skip': 0},
      );
      _banks = (bankResponse['items'] as List<dynamic>?)
          ?.map((item) => item as Map<String, dynamic>)
          .toList() ?? [];

      // بارگذاری لیست صندوق‌ها
      final cashRegisterResponse = await _cashRegisterService.list(
        businessId: widget.businessId,
        queryInfo: {'take': 100, 'skip': 0},
      );
      _cashRegisters = (cashRegisterResponse['items'] as List<dynamic>?)
          ?.map((item) => item as Map<String, dynamic>)
          .toList() ?? [];

      // بارگذاری لیست تنخواه گردان‌ها
      final pettyCashResponse = await _pettyCashService.list(
        businessId: widget.businessId,
        queryInfo: {'take': 100, 'skip': 0},
      );
      _pettyCashList = (pettyCashResponse['items'] as List<dynamic>?)
          ?.map((item) => item as Map<String, dynamic>)
          .toList() ?? [];

      setState(() {
        _isDataLoaded = true;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در بارگذاری داده‌ها: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_fromType == null || _toType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لطفاً مبدا و مقصد انتقال را انتخاب کنید'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_fromId == null || _toId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لطفاً مبدا و مقصد انتقال را انتخاب کنید'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_fromType == _toType && _fromId == _toId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('مبدا و مقصد نمی‌توانند یکسان باشند'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // TODO: ایجاد سرویس انتقال و ارسال درخواست به API
      // فعلاً فقط پیام موفقیت نمایش می‌دهیم
      
      await Future.delayed(const Duration(seconds: 1)); // شبیه‌سازی درخواست API
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('انتقال با موفقیت ثبت شد'),
            backgroundColor: Colors.green,
          ),
        );
        
        Navigator.of(context).pop();
        widget.onSuccess?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در ثبت انتقال: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildAccountSelector({
    required String label,
    required String? selectedType,
    required int? selectedId,
    required ValueChanged<String?> onTypeChanged,
    required ValueChanged<int?> onIdChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        
        // انتخاب نوع حساب با SegmentedButton
        Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                  Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.1),
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // SegmentedButton برای انتخاب نوع
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment<String>(
                        value: 'bank',
                        label: Text('بانک'),
                        icon: Icon(Icons.account_balance, size: 16),
                      ),
                      ButtonSegment<String>(
                        value: 'cash_register',
                        label: Text('صندوق'),
                        icon: Icon(Icons.point_of_sale, size: 16),
                      ),
                      ButtonSegment<String>(
                        value: 'petty_cash',
                        label: Text('تنخواه'),
                        icon: Icon(Icons.money, size: 16),
                      ),
                    ],
                    selected: selectedType != null ? {selectedType} : <String>{},
                    onSelectionChanged: (Set<String> selection) {
                      if (selection.isNotEmpty) {
                        onTypeChanged(selection.first);
                        onIdChanged(null); // ریست کردن انتخاب قبلی
                      }
                    },
                    style: ButtonStyle(
                      backgroundColor: MaterialStateProperty.resolveWith((states) {
                        if (states.contains(MaterialState.selected)) {
                          return Theme.of(context).primaryColor;
                        }
                        return Theme.of(context).colorScheme.surface;
                      }),
                      foregroundColor: MaterialStateProperty.resolveWith((states) {
                        if (states.contains(MaterialState.selected)) {
                          return Colors.white;
                        }
                        return Theme.of(context).colorScheme.onSurface;
                      }),
                      minimumSize: MaterialStateProperty.all(const Size(0, 40)),
                      padding: MaterialStateProperty.all(const EdgeInsets.symmetric(horizontal: 8)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        
        const SizedBox(height: 12),
        
        // انتخاب حساب خاص
        if (selectedType != null)
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: DropdownButtonFormField<int>(
                value: selectedId,
                decoration: InputDecoration(
                  labelText: _getAccountTypeLabel(selectedType),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: Theme.of(context).primaryColor,
                      width: 2,
                    ),
                  ),
                  prefixIcon: Icon(
                    _getAccountTypeIcon(selectedType),
                    color: Theme.of(context).primaryColor,
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                ),
                items: _getAccountItems(selectedType),
                onChanged: onIdChanged,
                validator: (value) {
                  if (value == null) return 'لطفاً حساب را انتخاب کنید';
                  return null;
                },
              ),
            ),
          ),
      ],
    );
  }

  String _getAccountTypeLabel(String type) {
    switch (type) {
      case 'bank':
        return 'انتخاب بانک';
      case 'cash_register':
        return 'انتخاب صندوق';
      case 'petty_cash':
        return 'انتخاب تنخواه گردان';
      default:
        return 'انتخاب حساب';
    }
  }

  IconData _getAccountTypeIcon(String type) {
    switch (type) {
      case 'bank':
        return Icons.account_balance;
      case 'cash_register':
        return Icons.point_of_sale;
      case 'petty_cash':
        return Icons.money;
      default:
        return Icons.account_balance_wallet;
    }
  }


  List<DropdownMenuItem<int>> _getAccountItems(String type) {
    List<Map<String, dynamic>> items = [];
    
    switch (type) {
      case 'bank':
        items = _banks;
        break;
      case 'cash_register':
        items = _cashRegisters;
        break;
      case 'petty_cash':
        items = _pettyCashList;
        break;
    }
    
    return items.map((item) {
      return DropdownMenuItem<int>(
        value: item['id'] as int,
        child: Text(item['name'] as String? ?? 'نامشخص'),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 8,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
          maxWidth: 1000, // حداکثر عرض برای دسکتاپ
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.surface.withOpacity(0.95),
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // هدر دیالوگ با طراحی بهبود یافته
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).primaryColor,
                    Theme.of(context).primaryColor.withOpacity(0.8),
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.swap_horiz,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ثبت انتقال',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'انتقال بین حساب‌های مختلف',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // فرم
            Expanded(
              child: Form(
                key: _formKey,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isDesktop = constraints.maxWidth > 800;
                    
                    if (isDesktop) {
                      // طراحی دو ستونه برای دسکتاپ
                      return SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              // ردیف اول: انتخاب مبدا و مقصد
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _buildAccountSelector(
                                      label: 'از (مبدا)',
                                      selectedType: _fromType,
                                      selectedId: _fromId,
                                      onTypeChanged: (value) {
                                        setState(() {
                                          _fromType = value;
                                          _fromId = null;
                                        });
                                      },
                                      onIdChanged: (value) {
                                        setState(() {
                                          _fromId = value;
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 24),
                                  Expanded(
                                    child: _buildAccountSelector(
                                      label: 'به (مقصد)',
                                      selectedType: _toType,
                                      selectedId: _toId,
                                      onTypeChanged: (value) {
                                        setState(() {
                                          _toType = value;
                                          _toId = null;
                                        });
                                      },
                                      onIdChanged: (value) {
                                        setState(() {
                                          _toId = value;
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              
                              const SizedBox(height: 24),
                              
                              // ردیف دوم: مبلغ و کارمزد
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _amountController,
                                      decoration: InputDecoration(
                                        labelText: 'مبلغ انتقال',
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: BorderSide(
                                            color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: BorderSide(
                                            color: Theme.of(context).primaryColor,
                                            width: 2,
                                          ),
                                        ),
                                        suffixText: 'ریال',
                                        prefixIcon: Icon(
                                          Icons.attach_money,
                                          color: Theme.of(context).primaryColor,
                                        ),
                                        filled: true,
                                        fillColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                                      ),
                                      keyboardType: TextInputType.number,
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'لطفاً مبلغ را وارد کنید';
                                        }
                                        if (double.tryParse(value) == null) {
                                          return 'لطفاً مبلغ معتبر وارد کنید';
                                        }
                                        if (double.parse(value) <= 0) {
                                          return 'مبلغ باید بزرگتر از صفر باشد';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 24),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _commissionController,
                                      decoration: InputDecoration(
                                        labelText: 'کارمزد',
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: BorderSide(
                                            color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: BorderSide(
                                            color: Theme.of(context).primaryColor,
                                            width: 2,
                                          ),
                                        ),
                                        suffixText: 'ریال',
                                        helperText: 'اختیاری',
                                        prefixIcon: Icon(
                                          Icons.percent,
                                          color: Theme.of(context).primaryColor,
                                        ),
                                        filled: true,
                                        fillColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                                      ),
                                      keyboardType: TextInputType.number,
                                      validator: (value) {
                                        if (value != null && value.isNotEmpty) {
                                          if (double.tryParse(value) == null) {
                                            return 'لطفاً مبلغ معتبر وارد کنید';
                                          }
                                          if (double.parse(value) < 0) {
                                            return 'کارمزد نمی‌تواند منفی باشد';
                                          }
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              
                              const SizedBox(height: 24),
                              
                              // ردیف سوم: تاریخ
                              Row(
                                children: [
                                  Expanded(
                                    child: DateInputField(
                                      value: _transferDate,
                                      onChanged: (date) {
                                        if (date != null) {
                                          setState(() {
                                            _transferDate = date;
                                          });
                                        }
                                      },
                                      labelText: 'تاریخ انتقال',
                                      calendarController: widget.calendarController,
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime.now().add(const Duration(days: 365)),
                                    ),
                                  ),
                                  const SizedBox(width: 24),
                                  const Expanded(child: SizedBox()), // فضای خالی برای تراز کردن
                                ],
                              ),
                              
                              const SizedBox(height: 24),
                              
                              // ردیف چهارم: توضیحات (تمام عرض)
                              TextFormField(
                                controller: _descriptionController,
                                decoration: InputDecoration(
                                  labelText: 'توضیحات',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: Theme.of(context).primaryColor,
                                      width: 2,
                                    ),
                                  ),
                                  prefixIcon: Icon(
                                    Icons.description,
                                    color: Theme.of(context).primaryColor,
                                  ),
                                  filled: true,
                                  fillColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                                ),
                                maxLines: 3,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'لطفاً توضیحات را وارد کنید';
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    } else {
                      // طراحی تک ستونه برای موبایل
                      return SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              // انتخاب مبدا
                              _buildAccountSelector(
                                label: 'از (مبدا)',
                                selectedType: _fromType,
                                selectedId: _fromId,
                                onTypeChanged: (value) {
                                  setState(() {
                                    _fromType = value;
                                    _fromId = null;
                                  });
                                },
                                onIdChanged: (value) {
                                  setState(() {
                                    _fromId = value;
                                  });
                                },
                              ),
                              
                              const SizedBox(height: 24),
                              
                              // انتخاب مقصد
                              _buildAccountSelector(
                                label: 'به (مقصد)',
                                selectedType: _toType,
                                selectedId: _toId,
                                onTypeChanged: (value) {
                                  setState(() {
                                    _toType = value;
                                    _toId = null;
                                  });
                                },
                                onIdChanged: (value) {
                                  setState(() {
                                    _toId = value;
                                  });
                                },
                              ),
                              
                              const SizedBox(height: 24),
                              
                              // مبلغ
                              TextFormField(
                                controller: _amountController,
                                decoration: const InputDecoration(
                                  labelText: 'مبلغ انتقال',
                                  border: OutlineInputBorder(),
                                  suffixText: 'ریال',
                                ),
                                keyboardType: TextInputType.number,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'لطفاً مبلغ را وارد کنید';
                                  }
                                  if (double.tryParse(value) == null) {
                                    return 'لطفاً مبلغ معتبر وارد کنید';
                                  }
                                  if (double.parse(value) <= 0) {
                                    return 'مبلغ باید بزرگتر از صفر باشد';
                                  }
                                  return null;
                                },
                              ),
                              
                              const SizedBox(height: 24),
                              
                              // کارمزد
                              TextFormField(
                                controller: _commissionController,
                                decoration: const InputDecoration(
                                  labelText: 'کارمزد',
                                  border: OutlineInputBorder(),
                                  suffixText: 'ریال',
                                  helperText: 'اختیاری',
                                ),
                                keyboardType: TextInputType.number,
                                validator: (value) {
                                  if (value != null && value.isNotEmpty) {
                                    if (double.tryParse(value) == null) {
                                      return 'لطفاً مبلغ معتبر وارد کنید';
                                    }
                                    if (double.parse(value) < 0) {
                                      return 'کارمزد نمی‌تواند منفی باشد';
                                    }
                                  }
                                  return null;
                                },
                              ),
                              
                              const SizedBox(height: 24),
                              
                              // تاریخ
                              DateInputField(
                                value: _transferDate,
                                onChanged: (date) {
                                  if (date != null) {
                                    setState(() {
                                      _transferDate = date;
                                    });
                                  }
                                },
                                labelText: 'تاریخ انتقال',
                                calendarController: widget.calendarController,
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                              ),
                              
                              const SizedBox(height: 24),
                              
                              // توضیحات
                              TextFormField(
                                controller: _descriptionController,
                                decoration: InputDecoration(
                                  labelText: 'توضیحات',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: Theme.of(context).primaryColor,
                                      width: 2,
                                    ),
                                  ),
                                  prefixIcon: Icon(
                                    Icons.description,
                                    color: Theme.of(context).primaryColor,
                                  ),
                                  filled: true,
                                  fillColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                                ),
                                maxLines: 3,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'لطفاً توضیحات را وارد کنید';
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),
            ),
            
            // دکمه‌های عملیات با طراحی بهبود یافته
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    label: const Text('انصراف'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _save,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save),
                    label: Text(_isLoading ? 'در حال ثبت...' : 'ثبت انتقال'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                    ),
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
