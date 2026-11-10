import 'package:flutter/material.dart';
import 'package:hesabix_ui/services/crm_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';

/// ثبت‌نام سرنخ یا فرصت در یک توالی فعال.
class CrmSequenceEnrollButton extends StatelessWidget {
  final int businessId;
  final int entityId;
  final String entityType;
  final CrmService crmService;
  final bool enabled;

  const CrmSequenceEnrollButton({
    super.key,
    required this.businessId,
    required this.entityId,
    required this.entityType,
    required this.crmService,
    this.enabled = true,
  });

  Future<void> _open(BuildContext context) async {
    if (!enabled) return;
    List<Map<String, dynamic>> sequences = [];
    try {
      sequences = await crmService.listSequences(businessId: businessId);
    } catch (e) {
      if (context.mounted) {
        SnackBarHelper.show(context, message: ErrorExtractor.forContext(e, context), isError: true);
      }
      return;
    }
    final active = sequences.where((s) => s['is_active'] != false).toList();
    if (!context.mounted) return;
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ثبت در توالی'),
        content: SizedBox(
          width: 360,
          child: active.isEmpty
              ? const Text('توالی فعالی تعریف نشده است. از صفحه توالی‌ها یکی بسازید.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: active
                      .map((s) => ListTile(
                            title: Text(s['name']?.toString() ?? ''),
                            subtitle: Text(s['description']?.toString() ?? ''),
                            onTap: () => Navigator.pop(ctx, (s['id'] as num?)?.toInt()),
                          ))
                      .toList(),
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن')),
        ],
      ),
    );
    if (picked == null || !context.mounted) return;
    try {
      await crmService.enrollSequence(
        businessId: businessId,
        sequenceId: picked,
        entityType: entityType,
        entityId: entityId,
      );
      if (context.mounted) SnackBarHelper.show(context, message: 'در توالی ثبت شد');
    } catch (e) {
      if (context.mounted) {
        SnackBarHelper.show(context, message: ErrorExtractor.forContext(e, context), isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: enabled ? () => _open(context) : null,
      icon: const Icon(Icons.playlist_add_check_outlined, size: 18),
      label: const Text('توالی'),
    );
  }
}
