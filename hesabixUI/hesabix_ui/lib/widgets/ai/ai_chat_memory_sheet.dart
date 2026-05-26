import 'package:flutter/material.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart' show SnackBarHelper;

/// برگهٔ ویرایش حافظهٔ دستیار (اهداف، ترجیحات، اصطلاحات).
Future<void> showAIChatMemorySheet({
  required BuildContext context,
  required AIService aiService,
  required int? businessId,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _AIChatMemorySheet(
      aiService: aiService,
      businessId: businessId,
    ),
  );
}

class _AIChatMemorySheet extends StatefulWidget {
  final AIService aiService;
  final int? businessId;

  const _AIChatMemorySheet({
    required this.aiService,
    required this.businessId,
  });

  @override
  State<_AIChatMemorySheet> createState() => _AIChatMemorySheetState();
}

class _AIChatMemorySheetState extends State<_AIChatMemorySheet> {
  final _ctrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await widget.aiService.getAIMemory(businessId: widget.businessId);
      if (!mounted) return;
      _ctrl.text = data['content'] as String? ?? '';
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: 'خطا در بارگذاری حافظه: ${ErrorExtractor.forContext(e, context)}',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.aiService.updateAIMemory(
        content: _ctrl.text,
        businessId: widget.businessId,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      SnackBarHelper.show(context, message: 'حافظه ذخیره شد');
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(
        context,
        message: 'خطا: ${ErrorExtractor.forContext(e, context)}',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'حافظه دستیار',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'اهداف فروش، ترجیحات گزارش، اصطلاحات داخلی و هر نکته‌ای که دستیار باید همیشه بداند.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            TextField(
              controller: _ctrl,
              maxLines: 8,
              minLines: 4,
              decoration: const InputDecoration(
                hintText: 'مثال: هدف فروش ماه ۵۰۰ میلیون است. گزارش‌ها را به تومان بده.',
                border: OutlineInputBorder(),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _loading || _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('ذخیره'),
          ),
        ],
      ),
    );
  }
}
