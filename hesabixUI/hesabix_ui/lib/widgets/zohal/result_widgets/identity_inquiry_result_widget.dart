import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../zohal_result_widget.dart';

/// ویجت نمایش نتیجه برای استعلام اطلاعات هویتی
class IdentityInquiryResultWidget extends ZohalResultWidget {
  const IdentityInquiryResultWidget({
    super.key,
    required super.result,
    required super.amountCharged,
    required super.remainingBalance,
    required super.walletCurrency,
  });

  @override
  List<Widget> buildResultContent(BuildContext context) {
    final theme = Theme.of(context);
    final responseBody = result['result']?['response_body'] as Map<String, dynamic>?;
    final data = responseBody?['data'] as Map<String, dynamic>?;
    final message = responseBody?['message']?.toString() ?? '';
    final errorCode = responseBody?['error_code'];

    // اگر خطا وجود دارد
    if (errorCode != null) {
      return [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.error,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(height: 16),
              Text(
                'خطا در استعلام',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message.isNotEmpty ? message : 'خطای نامشخص',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer.withValues(alpha: 0.9),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ];
    }

    final matched = data?['matched'] as bool? ?? false;

    // اگر تطابق نداشته باشد
    if (!matched) {
      return [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.error,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              Icon(
                Icons.cancel,
                size: 64,
                color: theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(height: 16),
              Text(
                'عدم تطابق',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'کد ملی و تاریخ تولد با یکدیگر مطابقت ندارند',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer.withValues(alpha: 0.9),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ];
    }

    // اگر تطابق داشته باشد - نمایش اطلاعات هویتی
    final firstName = data?['first_name']?.toString();
    final lastName = data?['last_name']?.toString();
    final fatherName = data?['father_name']?.toString();
    final alive = data?['alive'] as bool?;
    final isDead = data?['is_dead'] as bool?;
    final nationalCode = data?['national_code']?.toString();

    return [
      // هدر با نام و نام خانوادگی
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.primaryContainer,
              theme.colorScheme.primaryContainer.withValues(alpha: 0.7),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(
              Icons.person,
              size: 64,
              color: theme.colorScheme.onPrimaryContainer,
            ),
            const SizedBox(height: 16),
            if (firstName != null || lastName != null)
              Text(
                '${firstName ?? ''} ${lastName ?? ''}'.trim(),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                textAlign: TextAlign.center,
              ),
            if (nationalCode != null) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.badge,
                    size: 20,
                    color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.9),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    nationalCode,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ],
            // نمایش وضعیت حیات
            if (alive != null || isDead != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: (alive == true || isDead == false)
                      ? Colors.green.withValues(alpha: 0.2)
                      : Colors.red.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: (alive == true || isDead == false)
                        ? Colors.green
                        : Colors.red,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      (alive == true || isDead == false)
                          ? Icons.check_circle
                          : Icons.cancel,
                      size: 20,
                      color: (alive == true || isDead == false)
                          ? Colors.green
                          : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      (alive == true || isDead == false) ? 'زنده' : 'فوت شده',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: (alive == true || isDead == false)
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 16),
      // کارت اطلاعات شخصی
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.person_outline,
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  'اطلاعات شخصی',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(),
            if (firstName != null)
              _buildInfoRow(
                context,
                'نام',
                firstName,
                Icons.badge_outlined,
                onCopy: () => _copyToClipboard(context, firstName),
              ),
            if (lastName != null)
              _buildInfoRow(
                context,
                'نام خانوادگی',
                lastName,
                Icons.badge_outlined,
                onCopy: () => _copyToClipboard(context, lastName),
              ),
            if (fatherName != null)
              _buildInfoRow(
                context,
                'نام پدر',
                fatherName,
                Icons.family_restroom,
                onCopy: () => _copyToClipboard(context, fatherName),
              ),
            if (nationalCode != null)
              _buildInfoRow(
                context,
                'کد ملی',
                nationalCode,
                Icons.badge,
                onCopy: () => _copyToClipboard(context, nationalCode),
              ),
          ],
        ),
      ),
    ];
  }

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value,
    IconData icon, {
    VoidCallback? onCopy,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.end,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (onCopy != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: onCopy,
                    tooltip: 'کپی',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    color: theme.colorScheme.primary,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('کپی شد: $text'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

