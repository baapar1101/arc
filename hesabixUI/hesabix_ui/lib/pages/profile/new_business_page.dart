import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../models/business_models.dart';
import '../../services/business_api_service.dart';

class NewBusinessPage extends StatefulWidget {
  const NewBusinessPage({super.key});

  @override
  State<NewBusinessPage> createState() => _NewBusinessPageState();
}

class _NewBusinessPageState extends State<NewBusinessPage> {
  final PageController _pageController = PageController();
  final BusinessData _businessData = BusinessData();
  int _currentStep = 0;
  bool _isLoading = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < 4) {
      setState(() {
        _currentStep++;
      });
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _goToStep(int step) {
    setState(() {
      _currentStep = step;
    });
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  bool _canGoToNextStep() {
    switch (_currentStep) {
      case 0:
        return _businessData.isStep1Valid();
      case 1:
        return _businessData.isStep2Valid();
      case 2:
        return _businessData.isStep3Valid();
      case 3:
        return _businessData.isStep4Valid();
      default:
        return false;
    }
  }

  Future<void> _submitBusiness() async {
    if (!_businessData.isFormValid()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لطفاً تمام فیلدهای اجباری را پر کنید'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await BusinessApiService.createBusiness(_businessData);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('کسب و کار با موفقیت ایجاد شد'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در ایجاد کسب و کار: $e'),
            backgroundColor: Colors.red,
          ),
        );
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
    final t = AppLocalizations.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: Text(t.newBusiness),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Progress indicator
          Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Column(
              children: [
                // Progress bar
                Row(
                  children: List.generate(5, (index) {
                    final isActive = index <= _currentStep;
                    final isCurrent = index == _currentStep;
                    
                    return Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        height: 6,
                        decoration: BoxDecoration(
                          color: isActive
                              ? Theme.of(context).primaryColor
                              : Colors.grey[300],
                          borderRadius: BorderRadius.circular(3),
                          boxShadow: isCurrent
                              ? [
                                  BoxShadow(
                                    color: Theme.of(context).primaryColor.withOpacity(0.3),
                                    blurRadius: 4,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 8),
                // Progress text
                Text(
                  'مرحله ${_currentStep + 1} از 5',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          
          // Step indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStepIndicator(0, 'اطلاعات پایه'),
                _buildStepIndicator(1, 'اطلاعات تماس'),
                _buildStepIndicator(2, 'اطلاعات قانونی'),
                _buildStepIndicator(3, 'اطلاعات جغرافیایی'),
                _buildStepIndicator(4, 'تأیید'),
              ],
            ),
          ),
          
          // Form content with scroll
          Expanded(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height - 
                    kToolbarHeight - 
                    200, // برای progress indicator، step indicator و navigation buttons
                ),
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (index) {
                    setState(() {
                      _currentStep = index;
                    });
                  },
                  children: [
                    _buildStep1(),
                    _buildStep2(),
                    _buildStep3(),
                    _buildStep4(),
                    _buildStep5(),
                  ],
                ),
              ),
            ),
          ),
          
          // Navigation buttons
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).dividerColor.withOpacity(0.1),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildNavigationButton(
                  text: 'قبلی',
                  icon: Icons.arrow_back_ios,
                  onPressed: _currentStep > 0 ? _previousStep : null,
                  isPrimary: false,
                ),
                Row(
                  children: [
                    if (_currentStep < 4) ...[
                      _buildNavigationButton(
                        text: 'بعدی',
                        icon: Icons.arrow_forward_ios,
                        onPressed: _canGoToNextStep() ? _nextStep : null,
                        isPrimary: true,
                      ),
                    ] else ...[
                      _buildNavigationButton(
                        text: 'ایجاد کسب و کار',
                        icon: Icons.check,
                        onPressed: _isLoading ? null : _submitBusiness,
                        isPrimary: true,
                        isLoading: _isLoading,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(int step, String title) {
    final isActive = step <= _currentStep;
    final isCurrent = step == _currentStep;
    
    return GestureDetector(
      onTap: () => _goToStep(step),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? Theme.of(context).primaryColor.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? Theme.of(context).primaryColor
                : Colors.grey[300]!,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isActive
                    ? Theme.of(context).primaryColor
                    : Colors.grey[300],
                shape: BoxShape.circle,
                boxShadow: isCurrent
                    ? [
                        BoxShadow(
                          color: Theme.of(context).primaryColor.withOpacity(0.3),
                          blurRadius: 6,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: isActive
                    ? Icon(
                        Icons.check,
                        size: 16,
                        color: Colors.white,
                      )
                    : Text(
                        '${step + 1}',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: isActive
                    ? Theme.of(context).primaryColor
                    : Colors.grey[600],
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationButton({
    required String text,
    required IconData icon,
    required VoidCallback? onPressed,
    required bool isPrimary,
    bool isLoading = false,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 48,
      constraints: const BoxConstraints(minWidth: 120),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary
              ? Theme.of(context).primaryColor
              : Theme.of(context).colorScheme.surface,
          foregroundColor: isPrimary
              ? Colors.white
              : Theme.of(context).colorScheme.onSurface,
          elevation: isPrimary ? 2 : 0,
          shadowColor: isPrimary
              ? Theme.of(context).primaryColor.withOpacity(0.3)
              : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isPrimary
                ? BorderSide.none
                : BorderSide(
                    color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                    width: 1,
                  ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          animationDuration: const Duration(milliseconds: 200),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: isLoading
              ? SizedBox(
                  key: const ValueKey('loading'),
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isPrimary ? Colors.white : Theme.of(context).primaryColor,
                    ),
                  ),
                )
              : Row(
                  key: ValueKey('content_$text'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isPrimary) ...[
                      Text(
                        text,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        icon,
                        size: 18,
                      ),
                    ] else ...[
                      Icon(
                        icon,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        text,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildStep1() {
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'اطلاعات پایه کسب و کار',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 24),
                
                // نام کسب و کار
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'نام کسب و کار *',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _businessData.name = value;
                    });
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'نام کسب و کار اجباری است';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                // نوع کسب و کار
                DropdownButtonFormField<BusinessType>(
                  decoration: const InputDecoration(
                    labelText: 'نوع کسب و کار *',
                    border: OutlineInputBorder(),
                  ),
                  value: _businessData.businessType,
                  items: BusinessType.values.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(type.displayName),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _businessData.businessType = value;
                    });
                  },
                  validator: (value) {
                    if (value == null) {
                      return 'نوع کسب و کار اجباری است';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                // زمینه فعالیت
                DropdownButtonFormField<BusinessField>(
                  decoration: const InputDecoration(
                    labelText: 'زمینه فعالیت *',
                    border: OutlineInputBorder(),
                  ),
                  value: _businessData.businessField,
                  items: BusinessField.values.map((field) {
                    return DropdownMenuItem(
                      value: field,
                      child: Text(field.displayName),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _businessData.businessField = value;
                    });
                  },
                  validator: (value) {
                    if (value == null) {
                      return 'زمینه فعالیت اجباری است';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep2() {
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'اطلاعات تماس',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 24),
                
                // آدرس - تمام عرض
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'آدرس',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  onChanged: (value) {
                    setState(() {
                      _businessData.address = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                
                // فیلدهای تماس در دو ستون
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth > 600) {
                      return Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              decoration: InputDecoration(
                                labelText: 'تلفن ثابت',
                                border: const OutlineInputBorder(),
                                errorText: _businessData.getValidationError('phone'),
                                helperText: 'مثال: 02112345678',
                              ),
                              keyboardType: TextInputType.phone,
                              onChanged: (value) {
                                setState(() {
                                  _businessData.phone = value;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              decoration: InputDecoration(
                                labelText: 'موبایل',
                                border: const OutlineInputBorder(),
                                errorText: _businessData.getValidationError('mobile'),
                                helperText: 'مثال: 09123456789',
                              ),
                              keyboardType: TextInputType.phone,
                              onChanged: (value) {
                                setState(() {
                                  _businessData.mobile = value;
                                });
                              },
                            ),
                          ),
                        ],
                      );
                    } else {
                      return Column(
                        children: [
                          TextFormField(
                            decoration: InputDecoration(
                              labelText: 'تلفن ثابت',
                              border: const OutlineInputBorder(),
                              errorText: _businessData.getValidationError('phone'),
                              helperText: 'مثال: 02112345678',
                            ),
                            keyboardType: TextInputType.phone,
                            onChanged: (value) {
                              setState(() {
                                _businessData.phone = value;
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            decoration: InputDecoration(
                              labelText: 'موبایل',
                              border: const OutlineInputBorder(),
                              errorText: _businessData.getValidationError('mobile'),
                              helperText: 'مثال: 09123456789',
                            ),
                            keyboardType: TextInputType.phone,
                            onChanged: (value) {
                              setState(() {
                                _businessData.mobile = value;
                              });
                            },
                          ),
                        ],
                      );
                    }
                  },
                ),
                const SizedBox(height: 16),
                
                // کد پستی
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'کد پستی',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    setState(() {
                      _businessData.postalCode = value;
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep3() {
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'اطلاعات قانونی',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 24),
                
                // فیلدهای قانونی در دو ستون
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth > 600) {
                      return Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  decoration: InputDecoration(
                                    labelText: 'کد ملی',
                                    border: const OutlineInputBorder(),
                                    errorText: _businessData.getValidationError('nationalId'),
                                    helperText: 'مثال: 1234567890',
                                  ),
                                  keyboardType: TextInputType.number,
                                  onChanged: (value) {
                                    setState(() {
                                      _businessData.nationalId = value;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextFormField(
                                  decoration: const InputDecoration(
                                    labelText: 'شماره ثبت',
                                    border: OutlineInputBorder(),
                                  ),
                                  keyboardType: TextInputType.text,
                                  onChanged: (value) {
                                    setState(() {
                                      _businessData.registrationNumber = value;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            decoration: const InputDecoration(
                              labelText: 'شناسه اقتصادی',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.text,
                            onChanged: (value) {
                              setState(() {
                                _businessData.economicId = value;
                              });
                            },
                          ),
                        ],
                      );
                    } else {
                      return Column(
                        children: [
                          TextFormField(
                            decoration: InputDecoration(
                              labelText: 'کد ملی',
                              border: const OutlineInputBorder(),
                              errorText: _businessData.getValidationError('nationalId'),
                              helperText: 'مثال: 1234567890',
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (value) {
                              setState(() {
                                _businessData.nationalId = value;
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            decoration: const InputDecoration(
                              labelText: 'شماره ثبت',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.text,
                            onChanged: (value) {
                              setState(() {
                                _businessData.registrationNumber = value;
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            decoration: const InputDecoration(
                              labelText: 'شناسه اقتصادی',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.text,
                            onChanged: (value) {
                              setState(() {
                                _businessData.economicId = value;
                              });
                            },
                          ),
                        ],
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep4() {
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'اطلاعات جغرافیایی',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 24),
                
                // فیلدهای جغرافیایی در دو ستون
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth > 600) {
                      return Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  decoration: const InputDecoration(
                                    labelText: 'کشور',
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (value) {
                                    setState(() {
                                      _businessData.country = value;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextFormField(
                                  decoration: const InputDecoration(
                                    labelText: 'استان',
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (value) {
                                    setState(() {
                                      _businessData.province = value;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            decoration: const InputDecoration(
                              labelText: 'شهر',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (value) {
                              setState(() {
                                _businessData.city = value;
                              });
                            },
                          ),
                        ],
                      );
                    } else {
                      return Column(
                        children: [
                          TextFormField(
                            decoration: const InputDecoration(
                              labelText: 'کشور',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (value) {
                              setState(() {
                                _businessData.country = value;
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            decoration: const InputDecoration(
                              labelText: 'استان',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (value) {
                              setState(() {
                                _businessData.province = value;
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            decoration: const InputDecoration(
                              labelText: 'شهر',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (value) {
                              setState(() {
                                _businessData.city = value;
                              });
                            },
                          ),
                        ],
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep5() {
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تأیید اطلاعات',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 24),
                
                // نمایش خلاصه اطلاعات
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).dividerColor.withOpacity(0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSummaryItem('نام کسب و کار', _businessData.name),
                      _buildSummaryItem('نوع کسب و کار', _businessData.businessType?.displayName ?? ''),
                      _buildSummaryItem('زمینه فعالیت', _businessData.businessField?.displayName ?? ''),
                      if (_businessData.address?.isNotEmpty == true)
                        _buildSummaryItem('آدرس', _businessData.address!),
                      if (_businessData.phone?.isNotEmpty == true)
                        _buildSummaryItem('تلفن ثابت', _businessData.phone!),
                      if (_businessData.mobile?.isNotEmpty == true)
                        _buildSummaryItem('موبایل', _businessData.mobile!),
                      if (_businessData.nationalId?.isNotEmpty == true)
                        _buildSummaryItem('کد ملی', _businessData.nationalId!),
                      if (_businessData.registrationNumber?.isNotEmpty == true)
                        _buildSummaryItem('شماره ثبت', _businessData.registrationNumber!),
                      if (_businessData.economicId?.isNotEmpty == true)
                        _buildSummaryItem('شناسه اقتصادی', _businessData.economicId!),
                      if (_businessData.country?.isNotEmpty == true)
                        _buildSummaryItem('کشور', _businessData.country!),
                      if (_businessData.province?.isNotEmpty == true)
                        _buildSummaryItem('استان', _businessData.province!),
                      if (_businessData.city?.isNotEmpty == true)
                        _buildSummaryItem('شهر', _businessData.city!),
                      if (_businessData.postalCode?.isNotEmpty == true)
                        _buildSummaryItem('کد پستی', _businessData.postalCode!),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                
                // پیام تأیید
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Theme.of(context).primaryColor,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'آیا از صحت اطلاعات وارد شده اطمینان دارید؟',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w400),
            ),
          ),
        ],
      ),
    );
  }
}