import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/models/support_models.dart';
import 'package:hesabix_ui/services/support_service.dart';

class TicketAttachmentPicker extends StatelessWidget {
  final List<SupportAttachment> pendingAttachments;
  final bool isUploading;
  final VoidCallback onPick;
  final ValueChanged<int> onRemove;

  const TicketAttachmentPicker({
    super.key,
    required this.pendingAttachments,
    required this.isUploading,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (pendingAttachments.isEmpty && !isUploading) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.attach_file, size: 18),
          label: const Text('پیوست فایل'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...pendingAttachments.map(
              (a) => InputChip(
                label: Text(a.originalName, overflow: TextOverflow.ellipsis),
                onDeleted: () => onRemove(a.id),
              ),
            ),
            if (isUploading)
              const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
          ],
        ),
        TextButton.icon(
          onPressed: isUploading ? null : onPick,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('افزودن پیوست'),
        ),
      ],
    );
  }

  static Future<PlatformFile?> pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true, allowMultiple: false);
    if (result == null || result.files.isEmpty) return null;
    return result.files.first;
  }
}
