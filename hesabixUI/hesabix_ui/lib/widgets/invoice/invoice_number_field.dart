import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/number_normalizer.dart';

class InvoiceNumberField extends StatefulWidget {
  final String? initialValue;
  final ValueChanged<String?> onChanged;
  final bool isRequired;
  final String? label;
  final String? hintText;
  final bool autoGenerate;

  const InvoiceNumberField({
    super.key,
    this.initialValue,
    required this.onChanged,
    this.isRequired = true,
    this.label,
    this.hintText,
    this.autoGenerate = true,
  });

  @override
  State<InvoiceNumberField> createState() => _InvoiceNumberFieldState();
}

class _InvoiceNumberFieldState extends State<InvoiceNumberField> {
  late TextEditingController _controller;
  bool _isAutoGenerate = true;
  bool _isManualEntry = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
    _isAutoGenerate = widget.autoGenerate;
    _isManualEntry = widget.initialValue != null && widget.initialValue!.isNotEmpty;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(InvoiceNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue) {
      _controller.text = widget.initialValue ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // هدر با عنوان و دکمه‌های انتخاب نوع
          Row(
            children: [
              Icon(
                Icons.confirmation_number_outlined,
                color: colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.label ?? 'شماره فاکتور',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (widget.isRequired)
                Text(
                  ' *',
                  style: TextStyle(
                    color: colorScheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // دکمه‌های انتخاب نوع شماره‌گذاری
          Row(
            children: [
              Expanded(
                child: _buildModeButton(
                  context: context,
                  icon: Icons.auto_awesome,
                  label: 'اتوماتیک',
                  isSelected: _isAutoGenerate,
                  onTap: () {
                    setState(() {
                      _isAutoGenerate = true;
                      _isManualEntry = false;
                      _controller.clear();
                    });
                    widget.onChanged(null);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildModeButton(
                  context: context,
                  icon: Icons.edit,
                  label: 'دستی',
                  isSelected: _isManualEntry,
                  onTap: () {
                    setState(() {
                      _isAutoGenerate = false;
                      _isManualEntry = true;
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // فیلد ورودی شماره فاکتور
          if (_isManualEntry) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText:
                          widget.hintText ?? 'شماره فاکتور را وارد کنید',
                      prefixIcon: const Icon(Icons.numbers),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                    ),
                    onChanged: (value) {
                      widget.onChanged(value.isEmpty ? null : value);
                    },
                    inputFormatters: [
                      const EnglishDigitsFormatter(),
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[a-zA-Z0-9\-_]')),
                    ],
                    validator: widget.isRequired && _isManualEntry
                        ? (value) {
                            if (value == null || value.isEmpty) {
                              return 'شماره فاکتور الزامی است';
                            }
                            return null;
                          }
                        : null,
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: ListenableBuilder(
                    listenable: _controller,
                    builder: (context, _) {
                      if (_controller.text.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          widget.onChanged('');
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ] else ...[
            // نمایش حالت اتوماتیک
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.auto_awesome,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'شماره فاکتور به صورت خودکار تولید خواهد شد',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // راهنما
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: colorScheme.onSurfaceVariant,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isAutoGenerate
                        ? 'شماره فاکتور بر اساس الگوی تعریف شده تولید می‌شود'
                        : 'شماره فاکتور را به صورت دستی وارد کنید (فقط حروف انگلیسی، اعداد، خط تیره و زیرخط مجاز است)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outline.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isSelected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
