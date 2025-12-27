import 'package:flutter/material.dart';

/// اینترفیس پایه برای ویجت‌های فرم ورودی سرویس‌های زحل
abstract class ZohalInquiryFormWidget extends StatelessWidget {
  final Map<String, dynamic> service;
  final Map<String, TextEditingController> controllers;
  final GlobalKey<FormState> formKey;
  final Function(Map<String, dynamic>) onSubmit;
  final bool isSubmitting;
  final VoidCallback? onClose;

  const ZohalInquiryFormWidget({
    super.key,
    required this.service,
    required this.controllers,
    required this.formKey,
    required this.onSubmit,
    required this.isSubmitting,
    this.onClose,
  });

  /// ساخت محتوای فرم
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context, theme),
              const Divider(),
              const SizedBox(height: 16),
              ...buildFormFields(context),
              const SizedBox(height: 16),
              _buildSubmitButton(context, theme),
            ],
          ),
        ),
      ),
    );
  }

  /// ساخت هدر فرم (نام سرویس و دکمه بستن)
  Widget _buildHeader(BuildContext context, ThemeData theme) {
    return Row(
      children: [
        Icon(Icons.edit_note, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            service['service_name']?.toString() ?? 'استعلام',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: onClose ?? () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
          tooltip: 'بستن',
        ),
      ],
    );
  }

  /// ساخت دکمه ارسال
  Widget _buildSubmitButton(BuildContext context, ThemeData theme) {
    return FilledButton.icon(
      onPressed: isSubmitting
          ? null
          : () {
              if (formKey.currentState?.validate() ?? false) {
                final data = collectFormData();
                onSubmit(data);
              }
            },
      icon: isSubmitting
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.send),
      label: Text(isSubmitting ? 'در حال ارسال...' : 'ارسال درخواست'),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
    );
  }

  /// ساخت فیلدهای فرم - باید در کلاس‌های فرزند پیاده‌سازی شود
  List<Widget> buildFormFields(BuildContext context);

  /// جمع‌آوری داده‌های فرم - باید در کلاس‌های فرزند پیاده‌سازی شود
  Map<String, dynamic> collectFormData();
}
