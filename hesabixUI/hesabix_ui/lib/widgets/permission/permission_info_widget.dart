import 'package:flutter/material.dart';
import '../../core/auth_store.dart';

/// ویجت برای نمایش اطلاعات دسترسی‌های کاربر
class PermissionInfoWidget extends StatelessWidget {
  final String section;
  final bool showActions;
  final AuthStore authStore;

  const PermissionInfoWidget({
    super.key,
    required this.section,
    required this.authStore,
    this.showActions = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (authStore.currentBusiness == null) {
      return const SizedBox.shrink();
    }

    final availableActions = authStore.getAvailableActions(section);
    final isOwner = authStore.currentBusiness!.isOwner;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // عنوان بخش
          Row(
            children: [
              Icon(
                _getSectionIcon(section),
                size: 20,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                _getSectionTitle(section),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              if (isOwner)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.star,
                        size: 12,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'مالک',
                        style: TextStyle(
                          color: Colors.orange.shade700,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // نمایش دسترسی‌ها
          if (showActions) ...[
            Text(
              'دسترسی‌های موجود:',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: availableActions.map((action) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _getActionTitle(action),
                    style: TextStyle(
                      color: colorScheme.onPrimaryContainer,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  IconData _getSectionIcon(String section) {
    switch (section) {
      case 'people':
        return Icons.people;
      case 'products':
        return Icons.inventory;
      case 'price_lists':
        return Icons.list_alt;
      case 'categories':
        return Icons.category;
      case 'product_attributes':
        return Icons.tune;
      case 'bank_accounts':
        return Icons.account_balance_wallet;
      case 'cash':
        return Icons.money;
      case 'petty_cash':
        return Icons.money;
      case 'wallet':
        return Icons.wallet;
      case 'checks':
        return Icons.receipt_long;
      case 'transfers':
        return Icons.swap_horiz;
      case 'invoices':
        return Icons.receipt;
      case 'expenses_income':
        return Icons.account_balance_wallet;
      case 'accounting_documents':
        return Icons.description;
      case 'chart_of_accounts':
        return Icons.table_chart;
      case 'opening_balance':
        return Icons.play_arrow;
      case 'reports':
        return Icons.assessment;
      case 'warehouses':
        return Icons.warehouse;
      case 'warehouse_transfers':
        return Icons.local_shipping;
      case 'storage':
        return Icons.storage;
      case 'settings':
        return Icons.settings;
      case 'marketplace':
        return Icons.store;
      default:
        return Icons.lock;
    }
  }

  String _getSectionTitle(String section) {
    switch (section) {
      case 'people':
        return 'اشخاص';
      case 'products':
        return 'کالا و خدمات';
      case 'price_lists':
        return 'لیست‌های قیمت';
      case 'categories':
        return 'دسته‌بندی‌ها';
      case 'product_attributes':
        return 'ویژگی‌های کالا';
      case 'bank_accounts':
        return 'حساب‌های بانکی';
      case 'cash':
        return 'صندوق';
      case 'petty_cash':
        return 'تنخواه گردان';
      case 'wallet':
        return 'کیف پول';
      case 'checks':
        return 'چک‌ها';
      case 'transfers':
        return 'انتقال‌ها';
      case 'invoices':
        return 'فاکتورها';
      case 'expenses_income':
        return 'هزینه و درآمد';
      case 'accounting_documents':
        return 'اسناد حسابداری';
      case 'chart_of_accounts':
        return 'جدول حساب‌ها';
      case 'opening_balance':
        return 'تراز افتتاحیه';
      case 'reports':
        return 'گزارش‌ها';
      case 'warehouses':
        return 'انبارها';
      case 'warehouse_transfers':
        return 'حواله‌ها';
      case 'storage':
        return 'فضای ذخیره‌سازی';
      case 'settings':
        return 'تنظیمات';
      case 'marketplace':
        return 'بازار افزونه‌ها';
      default:
        return 'نامشخص';
    }
  }

  String _getActionTitle(String action) {
    switch (action) {
      case 'add':
        return 'افزودن';
      case 'view':
        return 'مشاهده';
      case 'edit':
        return 'ویرایش';
      case 'delete':
        return 'حذف';
      case 'draft':
        return 'پیش‌نویس';
      case 'collect':
        return 'وصول';
      case 'transfer':
        return 'انتقال';
      case 'return':
        return 'برگشت';
      case 'charge':
        return 'شارژ';
      default:
        return action;
    }
  }
}
