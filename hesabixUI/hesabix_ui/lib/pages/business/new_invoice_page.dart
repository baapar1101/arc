import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/auth_store.dart';
import '../../widgets/permission/access_denied_page.dart';

class NewInvoicePage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const NewInvoicePage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<NewInvoicePage> createState() => _NewInvoicePageState();
}

class _NewInvoicePageState extends State<NewInvoicePage> {
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    if (!widget.authStore.canWriteSection('invoices')) {
      return AccessDeniedPage(message: t.accessDenied);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(t.addInvoice),
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_circle_outline,
              size: 80,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.6),
            ),
            const SizedBox(height: 24),
            Text(
              t.addInvoice,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'فرم ایجاد فاکتور جدید در حال توسعه است',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                // TODO: پیاده‌سازی منطق ایجاد فاکتور
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('فرم ایجاد فاکتور به زودی اضافه خواهد شد'),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                  ),
                );
              },
              icon: const Icon(Icons.add),
              label: Text(t.addInvoice),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
