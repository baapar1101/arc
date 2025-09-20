import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/support_service.dart';
import 'package:hesabix_ui/models/support_models.dart';

class CreateTicketPage extends StatefulWidget {
  const CreateTicketPage({super.key});

  @override
  State<CreateTicketPage> createState() => _CreateTicketPageState();
}

class _CreateTicketPageState extends State<CreateTicketPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  final SupportService _supportService = SupportService(ApiClient());
  
  List<SupportCategory> _categories = [];
  List<SupportPriority> _priorities = [];
  
  SupportCategory? _selectedCategory;
  SupportPriority? _selectedPriority;
  
  bool _isLoading = false;
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final categories = await _supportService.getCategories();
      final priorities = await _supportService.getPriorities();
      
      setState(() {
        _categories = categories;
        _priorities = priorities;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _submitTicket() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategory == null || _selectedPriority == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لطفاً دسته‌بندی و اولویت را انتخاب کنید'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final request = CreateTicketRequest(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        categoryId: _selectedCategory!.id,
        priorityId: _selectedPriority!.id,
      );

      await _supportService.createTicket(request);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تیکت با موفقیت ایجاد شد'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ایجاد تیکت جدید'),
        actions: [
          if (_isSubmitting)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _submitTicket,
              child: const Text('ارسال'),
            ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red.withOpacity(0.6),
            ),
            const SizedBox(height: 16),
            Text(
              'خطا در بارگذاری داده‌ها',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.red,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              child: const Text('تلاش مجدد'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ایجاد تیکت پشتیبانی',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'لطفاً مشکل یا سوال خود را به تفصیل شرح دهید',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 24),
            
            // Title field
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'عنوان تیکت',
                hintText: 'عنوان کوتاه و واضح برای مشکل خود وارد کنید',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'عنوان تیکت الزامی است';
                }
                if (value.trim().length < 5) {
                  return 'عنوان باید حداقل 5 کاراکتر باشد';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            // Category dropdown
            DropdownButtonFormField<SupportCategory>(
              value: _selectedCategory,
              decoration: const InputDecoration(
                labelText: 'دسته‌بندی',
                border: OutlineInputBorder(),
              ),
              items: _categories.map((category) {
                return DropdownMenuItem(
                  value: category,
                  child: Text(category.name),
                );
              }).toList(),
              onChanged: (category) {
                setState(() {
                  _selectedCategory = category;
                });
              },
              validator: (value) {
                if (value == null) {
                  return 'لطفاً دسته‌بندی را انتخاب کنید';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            // Priority dropdown
            DropdownButtonFormField<SupportPriority>(
              value: _selectedPriority,
              decoration: const InputDecoration(
                labelText: 'اولویت',
                border: OutlineInputBorder(),
              ),
              items: _priorities.map((priority) {
                return DropdownMenuItem(
                  value: priority,
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: priority.color != null 
                              ? Color(int.parse(priority.color!.replaceFirst('#', '0xFF')))
                              : theme.colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(priority.name),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (priority) {
                setState(() {
                  _selectedPriority = priority;
                });
              },
              validator: (value) {
                if (value == null) {
                  return 'لطفاً اولویت را انتخاب کنید';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            // Description field
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'شرح مشکل',
                hintText: 'مشکل یا سوال خود را به تفصیل شرح دهید...',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 6,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'شرح مشکل الزامی است';
                }
                if (value.trim().length < 10) {
                  return 'شرح باید حداقل 10 کاراکتر باشد';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            
            // Submit button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitTicket,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isSubmitting
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          SizedBox(width: 8),
                          Text('در حال ارسال...'),
                        ],
                      )
                    : const Text('ارسال تیکت'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
