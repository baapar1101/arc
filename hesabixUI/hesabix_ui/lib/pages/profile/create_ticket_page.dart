import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
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
      final t = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t.pleaseSelectCategoryAndPriority),
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
        final t = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t.ticketCreatedSuccessfully),
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
    final t = AppLocalizations.of(context);
    final isDesktop = MediaQuery.of(context).size.width > 768;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: isDesktop ? 600 : double.infinity,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with close button
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary.withOpacity(0.1),
                    theme.colorScheme.primary.withOpacity(0.05),
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
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.support_agent,
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
                          t.createNewTicket,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          t.descriptionHint,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    style: IconButton.styleFrom(
                      backgroundColor: theme.colorScheme.surface,
                      foregroundColor: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            // Form content
            Flexible(
              child: _buildBody(theme, isDesktop, t),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, bool isDesktop, AppLocalizations t) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              t.loadingData,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Colors.red.withOpacity(0.8),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                t.dataLoadingError,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.red,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh),
                label: Text(t.retry),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
                      
                      // Form Fields
                      if (isDesktop) ...[
                        // Desktop Layout - Title full width, Category and Priority in one row
                        _buildTitleField(theme, t),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            // Category field
                            Expanded(
                              child: _buildCategoryField(theme, t),
                            ),
                            const SizedBox(width: 20),
                            // Priority field
                            Expanded(
                              child: _buildPriorityField(theme, t),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                      ] else ...[
                        // Mobile Layout - Single Column
                        _buildTitleField(theme, t),
                        const SizedBox(height: 20),
                        _buildCategoryField(theme, t),
                        const SizedBox(height: 20),
                        _buildPriorityField(theme, t),
                        const SizedBox(height: 20),
                      ],
                      
                      // Description Field (Full Width)
                      _buildDescriptionField(theme, t),
                      const SizedBox(height: 32),
                      
            // Submit Button
            _buildSubmitButton(theme, isDesktop, t),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleField(ThemeData theme, AppLocalizations t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.ticketTitleLabel,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _titleController,
          decoration: InputDecoration(
            hintText: t.ticketTitleHint,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: theme.colorScheme.outline.withOpacity(0.3),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: theme.colorScheme.primary,
                width: 2,
              ),
            ),
            filled: true,
            fillColor: theme.colorScheme.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return t.ticketTitleRequired;
            }
            if (value.trim().length < 5) {
              return t.ticketTitleMinLength;
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildCategoryField(ThemeData theme, AppLocalizations t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.categoryLabel,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<SupportCategory>(
          value: _selectedCategory,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: theme.colorScheme.outline.withOpacity(0.3),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: theme.colorScheme.primary,
                width: 2,
              ),
            ),
            filled: true,
            fillColor: theme.colorScheme.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
              return t.categoryRequired;
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildPriorityField(ThemeData theme, AppLocalizations t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.priorityLabel,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<SupportPriority>(
          value: _selectedPriority,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: theme.colorScheme.outline.withOpacity(0.3),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: theme.colorScheme.primary,
                width: 2,
              ),
            ),
            filled: true,
            fillColor: theme.colorScheme.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                  const SizedBox(width: 12),
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
              return t.priorityRequired;
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildDescriptionField(ThemeData theme, AppLocalizations t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.descriptionLabel,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _descriptionController,
          decoration: InputDecoration(
            hintText: t.descriptionHint,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: theme.colorScheme.outline.withOpacity(0.3),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: theme.colorScheme.primary,
                width: 2,
              ),
            ),
            filled: true,
            fillColor: theme.colorScheme.surface,
            contentPadding: const EdgeInsets.all(16),
            alignLabelWithHint: true,
          ),
          maxLines: 6,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return t.descriptionRequired;
            }
            if (value.trim().length < 10) {
              return t.descriptionMinLength;
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildSubmitButton(ThemeData theme, bool isDesktop, AppLocalizations t) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outline.withOpacity(0.2),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _submitTicket,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.send),
              label: Text(_isSubmitting ? t.submittingTicket : t.submitTicket),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                elevation: 4,
                shadowColor: theme.colorScheme.primary.withOpacity(0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(t.cancel),
          ),
        ],
      ),
    );
  }
}
