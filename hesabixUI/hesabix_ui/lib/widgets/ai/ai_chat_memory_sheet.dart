import 'package:hesabix_ui/theme/glass.dart';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart' show SnackBarHelper;
import 'package:hesabix_ui/widgets/ai/ai_chat_design.dart';

/// برگهٔ واحد حافظه: سیاست‌های کاربر + آنچه دستیار بین گفت‌وگوها به خاطر می‌سپارد.
Future<void> showAIChatMemorySheet({
  required BuildContext context,
  required AIService aiService,
  required int? businessId,
}) async {
  await showGlassModalBottomSheet<void>(
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

  Map<String, List<_LearnedItem>> get _grouped {
    final map = <String, List<_LearnedItem>>{};
    for (final item in _items) {
      map.putIfAbsent(item.kind, () => []).add(item);
    }
    return map;
  }

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
                  kind: (e['kind'] as String?) ??
                      (e['category'] as String? ?? 'context'),
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
    final ok = await showGlassDialog<bool>(
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
    final saved = await showGlassDialog<String>(
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
    final ok = await showGlassDialog<bool>(
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
    final scheme = theme.colorScheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final overLimit = _charCount > _maxChars;
    final height = MediaQuery.sizeOf(context).height * 0.86;

    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom),
        child: ListView(
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.psychology_rounded,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.aiMemoryTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (_updatedAt != null)
                        Text(
                          l10n.aiMemoryUpdatedAt(_formatUpdatedAt(_updatedAt!)),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.outline,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              l10n.aiMemoryIntro,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            if (!_loading && _items.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StatChip(
                    icon: Icons.auto_awesome_outlined,
                    label: l10n.aiMemoryLearnedCount(_items.length),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else ...[
              DecoratedBox(
                decoration: AIChatDesign.elevatedCard(theme),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.aiMemoryPoliciesCardTitle,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.aiMemoryInstructionsHint,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _instructionsCtrl,
                        maxLines: 5,
                        minLines: 3,
                        decoration: InputDecoration(
                          hintText: l10n.aiMemoryInstructionsExample,
                          filled: true,
                          fillColor: scheme.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          errorText: overLimit ? l10n.aiMemoryMaxChars(_maxChars) : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            '$_charCount / $_maxChars',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: overLimit ? scheme.error : scheme.onSurfaceVariant,
                            ),
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: _saving || _clearing || overLimit
                                ? null
                                : _saveInstructions,
                            icon: _saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined, size: 18),
                            label: Text(l10n.aiMemorySaveInstructions),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                l10n.aiMemoryLearnedTitle,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.aiMemoryLearnedIntro,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              if (_items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    children: [
                      Icon(Icons.spa_outlined, size: 36, color: scheme.outline),
                      const SizedBox(height: 10),
                      Text(
                        l10n.aiMemoryLearnedEmpty,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.outline,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                )
              else
                ..._kindOrder.where((k) => _grouped.containsKey(k)).expand((kind) {
                  final group = _grouped[kind]!;
                  return [
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 8),
                      child: Text(
                        _kindLabel(kind, l10n),
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    ...group.map((item) => _MemoryItemCard(
                          item: item,
                          sourceLabel: _sourceLabel(item.source),
                          kindLabel: _kindLabel(item.kind, l10n),
                          onEdit: _clearing ? null : () => _editItem(item),
                          onDelete: _clearing ? null : () => _deleteItem(item),
                        )),
                  ];
                }),
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: _loading || _saving || _clearing ? null : _clearAll,
                  icon: _clearing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: Text(l10n.aiMemoryClearAll),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static const _kindOrder = [
    'identity',
    'preference',
    'context',
    'goal',
    'constraint',
    'fact',
    'term',
    'hint',
  ];

  String _kindLabel(String kind, AppLocalizations l10n) {
    switch (kind) {
      case 'identity':
        return l10n.aiMemoryKindIdentity;
      case 'preference':
        return l10n.aiMemoryKindPreference;
      case 'goal':
        return l10n.aiMemoryKindGoal;
      case 'constraint':
      case 'hint':
        return l10n.aiMemoryKindConstraint;
      case 'context':
      case 'fact':
      case 'term':
        return l10n.aiMemoryKindContext;
      default:
        return l10n.aiMemoryKindContext;
    }
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
      case 'profile':
        return l10n.aiMemorySourceProfile;
      case 'curator':
        return l10n.aiMemorySourceCurator;
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

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: AIChatDesign.chipDecoration(theme),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _MemoryItemCard extends StatelessWidget {
  final _LearnedItem item;
  final String sourceLabel;
  final String kindLabel;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _MemoryItemCard({
    required this.item,
    required this.sourceLabel,
    required this.kindLabel,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: AIChatDesign.elevatedCard(theme),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.content, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          kindLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (sourceLabel.isNotEmpty)
                          Text(
                            sourceLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.outline,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: AppLocalizations.of(context).edit,
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 20),
              ),
              IconButton(
                tooltip: AppLocalizations.of(context).delete,
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LearnedItem {
  final int id;
  final String content;
  final String source;
  final String kind;

  const _LearnedItem({
    required this.id,
    required this.content,
    required this.source,
    required this.kind,
  });

  _LearnedItem copyWith({String? content}) {
    return _LearnedItem(
      id: id,
      content: content ?? this.content,
      source: source,
      kind: kind,
    );
  }
}
