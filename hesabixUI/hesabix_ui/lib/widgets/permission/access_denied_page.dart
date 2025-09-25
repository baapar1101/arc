import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

/// صفحه نمایش عدم دسترسی
class AccessDeniedPage extends StatelessWidget {
  final String? message;
  final String? actionText;
  final VoidCallback? onAction;

  const AccessDeniedPage({
    super.key,
    this.message,
    this.actionText,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // آیکون عدم دسترسی
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(60),
                  ),
                  child: Icon(
                    Icons.lock_outline,
                    size: 60,
                    color: colorScheme.onErrorContainer,
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // عنوان
                Text(
                  t.accessDenied,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 16),
                
                // پیام
                Text(
                  message ?? 'شما دسترسی لازم برای مشاهده این بخش را ندارید',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 32),
                
                // دکمه‌های عمل
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // دکمه بازگشت
                    OutlinedButton.icon(
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('بازگشت'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                    
                    const SizedBox(width: 16),
                    
                    // دکمه عمل سفارشی
                    if (actionText != null && onAction != null)
                      ElevatedButton.icon(
                        onPressed: onAction,
                        icon: const Icon(Icons.refresh),
                        label: Text(actionText!),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
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
}

/// ویجت کوچک برای نمایش عدم دسترسی
class AccessDeniedWidget extends StatelessWidget {
  final String? message;
  final IconData? icon;

  const AccessDeniedWidget({
    super.key,
    this.message,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.errorContainer,
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon ?? Icons.lock_outline,
            size: 48,
            color: colorScheme.error,
          ),
          
          const SizedBox(height: 16),
          
          Text(
            message ?? t.accessDenied,
            style: theme.textTheme.titleMedium?.copyWith(
              color: colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
