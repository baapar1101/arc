import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart' show SnackBarHelper;

/// مدیریت دانشنامه کسب‌وکار (RAG lite).
Future<void> showAIChatKnowledgeSheet({
  required BuildContext context,
  required AIService aiService,
  required int? businessId,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _AIChatKnowledgeSheet(
      aiService: aiService,
      businessId: businessId,
    ),
  );
}

class _AIChatKnowledgeSheet extends StatefulWidget {
  final AIService aiService;
  final int? businessId;

  const _AIChatKnowledgeSheet({
    required this.aiService,
    required this.businessId,
  });

  @override
  State<_AIChatKnowledgeSheet> createState() => _AIChatKnowledgeSheetState();
}

class _AIChatKnowledgeSheetState extends State<_AIChatKnowledgeSheet> {
  bool _loading = true;
  bool _reindexing = false;
  List<Map<String, dynamic>> _docs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await widget.aiService.listKnowledgeDocuments(
        businessId: widget.businessId,
      );
      if (!mounted) return;
      setState(() => _docs = rows);
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: 'خطا: ${ErrorExtractor.forContext(e, context)}',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addManual() async {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('سند جدید'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'عنوان'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bodyCtrl,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'متن',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ذخیره')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.aiService.createKnowledgeDocument(
        title: titleCtrl.text.trim().isEmpty ? 'بدون عنوان' : titleCtrl.text.trim(),
        content: bodyCtrl.text,
        businessId: widget.businessId,
      );
      await _load();
      if (mounted) SnackBarHelper.show(context, message: 'سند اضافه شد');
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: ErrorExtractor.forContext(e, context),
          isError: true,
        );
      }
    }
  }

  Future<void> _uploadFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    try {
      await widget.aiService.uploadKnowledgeDocument(
        filename: file.name,
        bytes: bytes,
        title: file.name,
        businessId: widget.businessId,
      );
      await _load();
      if (mounted) SnackBarHelper.show(context, message: 'فایل آپلود شد');
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: ErrorExtractor.forContext(e, context),
          isError: true,
        );
      }
    }
  }

  Future<void> _reindex() async {
    setState(() => _reindexing = true);
    try {
      final stats = await widget.aiService.reindexKnowledge(businessId: widget.businessId);
      await _load();
      if (!mounted) return;
      SnackBarHelper.show(
        context,
        message: 'بازنمایه‌سازی: ${stats['documents']} سند، ${stats['chunks']} بخش',
      );
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: ErrorExtractor.forContext(e, context),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _reindexing = false);
    }
  }

  Future<void> _deleteDoc(int id) async {
    try {
      await widget.aiService.deleteKnowledgeDocument(
        documentId: id,
        businessId: widget.businessId,
      );
      await _load();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: ErrorExtractor.forContext(e, context),
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'دانشنامه کسب‌وکار',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'اسناد مرتبط هنگام پاسخ‌دهی به پرسش شما جستجو و به context اضافه می‌شوند.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: _addManual,
                icon: const Icon(Icons.note_add_outlined, size: 20),
                label: const Text('متن'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _uploadFile,
                icon: const Icon(Icons.upload_file_outlined, size: 20),
                label: const Text('فایل'),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _reindexing ? null : _reindex,
                icon: _reindexing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded, size: 20),
                label: const Text('بازنمایه'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_docs.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('هنوز سندی ثبت نشده است.'),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _docs.length,
                itemBuilder: (context, i) {
                  final doc = _docs[i];
                  final id = doc['id'] as int;
                  final title = doc['title'] as String? ?? '';
                  final chars = doc['char_count'] as int? ?? 0;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('$chars کاراکتر'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deleteDoc(id),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
