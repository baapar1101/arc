import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart' show SnackBarHelper;

/// برگهٔ حافظهٔ دو لایه: دستورات همیشگی + حقایق یادگرفته‌شده.
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
  final _instructionsCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _clearing = false;
  int _maxChars = 4000;
  String? _updatedAt;
  List<_LearnedItem> _items = [];

  @override
  void initState() {
    super.initState();
    _instructionsCtrl.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _instructionsCtrl.dispose();
    super.dispose();
  }

  int get _charCount => _instructionsCtrl.text.length;

  Future<void> _load() async {
    try {
      final data = await widget.aiService.getAIMemory(businessId: widget.businessId);
      if (!mounted) return;
      final instructions = (data['instructions'] as String?) ??
          (data['content'] as String?) ??
          '';
      _instructionsCtrl.text = instructions;
      _maxChars = data['max_chars'] as int? ?? 4000;
      _updatedAt = data['updated_at'] as String?;
      final rawItems = data['items'];
      final items = <_LearnedItem>[];
      if (rawItems is List) {
        for (final e in rawItems) {
          if (e is Map) {
            final idRaw = e['id'];
            final id = idRaw is int
                ? idRaw
                : (idRaw is num ? idRaw.toInt() : null);
            final content = e['content'] as String? ?? '';
            if (id != null && content.isNotEmpty) {
              items.add(
                _LearnedItem(
                  id: id,
                  content: content,
                  source: e['source'] as String? ?? '',
                  category: e['category'] as String? ?? 'fact',
                ),
              );
            }
          }
        }
      }
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        SnackBarHelper.show(
          context,
          message: AppLocalizations.of(context).aiMemoryLoadFailed(
            ErrorExtractor.forContext(e, context),
          ),
          isError: true,
        );
      }
    }
  }

  Future<void> _saveInstructions() async {
    setState(() => _saving = true);
    try {
      final data = await widget.aiService.updateAIMemory(
        content: _instructionsCtrl.text,
        businessId: widget.businessId,
      );
      if (!mounted) return;
      final instructions = (data['instructions'] as String?) ??
          (data['content'] as String?) ??
          '';
      _instructionsCtrl.text = instructions;
      _updatedAt = data['updated_at'] as String?;
      SnackBarHelper.show(context, message: AppLocalizations.of(context).aiMemorySaved);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(
        context,
        message: AppLocalizations.of(context).aiMemoryError(
          ErrorExtractor.forContext(e, context),
        ),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clearAll() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.aiMemoryClearTitle),
        content: Text(l10n.aiMemoryClearBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.aiMemoryClearConfirm)),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _clearing = true);
    try {
      await widget.aiService.deleteAIMemory(businessId: widget.businessId);
      if (!mounted) return;
      _instructionsCtrl.clear();
      setState(() {
        _items = [];
        _updatedAt = null;
      });
      SnackBarHelper.show(context, message: AppLocalizations.of(context).aiMemoryCleared);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(
        context,
        message: AppLocalizations.of(context).aiMemoryError(
          ErrorExtractor.forContext(e, context),
        ),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Future<void> _editItem(_LearnedItem item) async {
    final l10n = AppLocalizations.of(context);
    final ctrl = TextEditingController(text: item.content);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.aiMemoryEditTitle),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          minLines: 2,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: l10n.aiMemoryEditHint,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (saved == null || saved.isEmpty || !mounted) return;

    try {
      final updated = await widget.aiService.updateAIMemoryItem(
        itemId: item.id,
        content: saved,
        businessId: widget.businessId,
      );
      if (!mounted) return;
      setState(() {
        _items = [
          for (final it in _items)
            if (it.id == item.id)
              it.copyWith(content: updated['content'] as String? ?? saved)
            else
              it,
        ];
      });
      SnackBarHelper.show(context, message: AppLocalizations.of(context).aiMemoryItemUpdated);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(
        context,
        message: AppLocalizations.of(context).aiMemoryError(
          ErrorExtractor.forContext(e, context),
        ),
        isError: true,
      );
    }
  }

  Future<void> _deleteItem(_LearnedItem item) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.aiMemoryDeleteItemTitle),
        content: Text(item.content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.delete)),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await widget.aiService.deleteAIMemoryItem(
        itemId: item.id,
        businessId: widget.businessId,
      );
      if (!mounted) return;
      setState(() => _items = _items.where((e) => e.id != item.id).toList());
      SnackBarHelper.show(context, message: AppLocalizations.of(context).aiMemoryDeleted);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(
        context,
        message: AppLocalizations.of(context).aiMemoryError(
          ErrorExtractor.forContext(e, context),
        ),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final overLimit = _charCount > _maxChars;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom),
      child: ListView(
        children: [
          Text(
            l10n.aiMemoryTitle,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.aiMemoryIntro,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (_updatedAt != null) ...[
            const SizedBox(height: 6),
            Text(
              l10n.aiMemoryUpdatedAt(_formatUpdatedAt(_updatedAt!)),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else ...[
            Text(l10n.aiMemoryInstructionsTitle, style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              l10n.aiMemoryInstructionsHint,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _instructionsCtrl,
              maxLines: 5,
              minLines: 3,
              decoration: InputDecoration(
                hintText: l10n.aiMemoryInstructionsExample,
                border: const OutlineInputBorder(),
                errorText: overLimit ? l10n.aiMemoryMaxChars(_maxChars) : null,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  '$_charCount / $_maxChars',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: overLimit
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _saving || _clearing || overLimit ? null : _saveInstructions,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(l10n.aiMemorySaveInstructions),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(l10n.aiMemoryLearnedTitle, style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              l10n.aiMemoryLearnedIntro,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  l10n.aiMemoryLearnedEmpty,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              )
            else
              ..._items.map((item) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.content, style: theme.textTheme.bodyMedium),
                                if (item.source.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    _sourceLabel(item.source),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.outline,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: l10n.edit,
                            onPressed: _clearing ? null : () => _editItem(item),
                            icon: const Icon(Icons.edit_outlined, size: 20),
                          ),
                          IconButton(
                            tooltip: l10n.delete,
                            onPressed: _clearing ? null : () => _deleteItem(item),
                            icon: const Icon(Icons.delete_outline, size: 20),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            const SizedBox(height: 16),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: _loading || _saving || _clearing ? null : _clearAll,
                child: _clearing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.aiMemoryClearAll),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _sourceLabel(String source) {
    final l10n = AppLocalizations.of(context);
    switch (source) {
      case 'auto':
        return l10n.aiMemorySourceAuto;
      case 'assistant':
        return l10n.aiMemorySourceAssistant;
      case 'feedback':
        return l10n.aiMemorySourceFeedback;
      case 'user':
        return l10n.aiMemorySourceUser;
      default:
        return source;
    }
  }

  String _formatUpdatedAt(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}

class _LearnedItem {
  final int id;
  final String content;
  final String source;
  final String category;

  const _LearnedItem({
    required this.id,
    required this.content,
    required this.source,
    required this.category,
  });

  _LearnedItem copyWith({String? content}) {
    return _LearnedItem(
      id: id,
      content: content ?? this.content,
      source: source,
      category: category,
    );
  }
}
