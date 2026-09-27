import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/models/task_model.dart';
import 'package:hesabix_ui/services/bytes_export/bytes_export_service.dart';
import 'package:hesabix_ui/services/task_service.dart';
import 'package:hesabix_ui/theme/glass.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:intl/intl.dart';

class TaskAttachmentsSection extends StatefulWidget {
  final int businessId;
  final TaskModel task;

  const TaskAttachmentsSection({
    super.key,
    required this.businessId,
    required this.task,
  });

  @override
  State<TaskAttachmentsSection> createState() => _TaskAttachmentsSectionState();
}

class _TaskAttachmentsSectionState extends State<TaskAttachmentsSection> {
  late final TaskService _service;
  List<TaskAttachmentModel> _items = const [];
  bool _loading = true;
  bool _uploading = false;
  final Set<int> _busyIds = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = TaskService(ApiClient());
    _load();
  }

  @override
  void didUpdateWidget(covariant TaskAttachmentsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id) _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _service.listAttachments(
        businessId: widget.businessId,
        taskId: widget.task.id,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ErrorExtractor.forContext(e, context);
      });
    }
  }

  Future<void> _pickAndUpload() async {
    if (_uploading) return;
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (mounted) {
        setState(() => _error = 'خواندن فایل انتخاب‌شده ممکن نبود.');
      }
      return;
    }

    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      await _service.uploadAttachment(
        businessId: widget.businessId,
        taskId: widget.task.id,
        bytes: bytes,
        filename: file.name,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _download(TaskAttachmentModel item) async {
    if (_busyIds.contains(item.id)) return;
    setState(() {
      _busyIds.add(item.id);
      _error = null;
    });
    try {
      final bytes = await _service.downloadAttachment(
        businessId: widget.businessId,
        taskId: widget.task.id,
        attachmentId: item.id,
      );
      final result = await BytesExportService.export(
        bytes: bytes,
        filename: item.originalName,
        mimeType: item.mimeType,
      );
      if (mounted) BytesExportService.showFeedback(context, result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _busyIds.remove(item.id));
    }
  }

  Future<void> _delete(TaskAttachmentModel item) async {
    if (_busyIds.contains(item.id)) return;
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف پیوست'),
        content: Text('«${item.originalName}» حذف شود؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _busyIds.add(item.id);
      _error = null;
    });
    try {
      await _service.deleteAttachment(
        businessId: widget.businessId,
        taskId: widget.task.id,
        attachmentId: item.id,
      );
      if (!mounted) return;
      setState(() => _items = _items.where((e) => e.id != item.id).toList());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _busyIds.remove(item.id));
    }
  }

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData _icon(String? mime) {
    final value = (mime ?? '').toLowerCase();
    if (value.startsWith('image/')) return Icons.image_outlined;
    if (value == 'application/pdf') return Icons.picture_as_pdf_outlined;
    if (value.contains('spreadsheet') || value.contains('excel')) {
      return Icons.table_chart_outlined;
    }
    if (value.contains('word')) return Icons.description_outlined;
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Attachments',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: 'بروزرسانی',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded, size: 19),
            ),
            FilledButton.tonalIcon(
              onPressed: _uploading ? null : _pickAndUpload,
              icon: _uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.attach_file_rounded, size: 18),
              label: const Text('افزودن'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_items.isEmpty)
          Text(
            'پیوستی برای این کار ثبت نشده است.',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          ..._items.map(
            (item) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(_icon(item.mimeType), color: scheme.primary),
              title: Text(
                item.originalName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  _size(item.sizeBytes),
                  if (item.uploadedByName?.isNotEmpty == true)
                    item.uploadedByName!,
                  if (item.createdAt != null)
                    DateFormat('yyyy/MM/dd HH:mm')
                        .format(item.createdAt!.toLocal()),
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: _busyIds.contains(item.id)
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Wrap(
                      spacing: 0,
                      children: [
                        IconButton(
                          tooltip: 'دانلود',
                          onPressed: () => _download(item),
                          icon: const Icon(Icons.download_outlined, size: 20),
                        ),
                        IconButton(
                          tooltip: 'حذف',
                          onPressed: () => _delete(item),
                          icon: Icon(
                            Icons.delete_outline,
                            size: 20,
                            color: scheme.error,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          GlassSurface(
            padding: const EdgeInsets.all(9),
            borderRadius: BorderRadius.circular(9),
            child: Text(_error!, style: TextStyle(color: scheme.error)),
          ),
        ],
      ],
    );
  }
}
