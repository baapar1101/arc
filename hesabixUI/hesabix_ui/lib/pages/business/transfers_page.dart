import 'package:flutter/material.dart';
import '../../core/auth_store.dart';
import '../../core/calendar_controller.dart';
import '../../core/api_client.dart';
import '../../widgets/transfer/transfer_form_dialog.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

class TransfersPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController calendarController;
  final ApiClient apiClient;

  const TransfersPage({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.calendarController,
    required this.apiClient,
  });

  @override
  State<TransfersPage> createState() => _TransfersPageState();
}

class _TransfersPageState extends State<TransfersPage> {
  Future<void> _showAddTransferDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => TransferFormDialog(
        businessId: widget.businessId,
        calendarController: widget.calendarController,
        onSuccess: () {
          // TODO: بروزرسانی لیست انتقالات
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('انتقال با موفقیت ثبت شد'),
              backgroundColor: Colors.green,
            ),
          );
        },
      ),
    );
    
    if (result == true) {
      // بروزرسانی صفحه در صورت نیاز
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: Text(t.transfers),
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddTransferDialog(),
            tooltip: 'اضافه کردن انتقال جدید',
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.swap_horiz,
              size: 80,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'صفحه لیست انتقال',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'این صفحه به زودی آماده خواهد شد',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => _showAddTransferDialog(),
              icon: const Icon(Icons.add),
              label: const Text('اضافه کردن انتقال جدید'),
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
