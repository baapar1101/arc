import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/frequent_description_item.dart';
import '../../services/frequent_description_api_service.dart';

/// فیلد متنی شرح با پیشنهادهای پرتکرار؛ لیست فقط هنگام فوکوس روی فیلد بارگذاری/نمایش داده می‌شود.
class FrequentDescriptionTextField extends StatefulWidget {
  final int businessId;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final InputDecoration decoration;
  final int? maxLines;
  final int? maxLength;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final bool readOnly;
  final TextStyle? style;
  final TextInputType? keyboardType;
  final Widget? Function(BuildContext, {required int currentLength, required bool isFocused, int? maxLength})? buildCounter;
  final void Function(String value)? onSubmitted;

  const FrequentDescriptionTextField({
    super.key,
    required this.businessId,
    required this.controller,
    required this.decoration,
    this.focusNode,
    this.maxLines = 1,
    this.maxLength,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.readOnly = false,
    this.style,
    this.keyboardType,
    this.buildCounter,
  });

  @override
  State<FrequentDescriptionTextField> createState() => _FrequentDescriptionTextFieldState();
}

class _FrequentDescriptionTextFieldState extends State<FrequentDescriptionTextField> {
  late final FocusNode _focusNode;
  late final bool _ownsFocus;
  bool _showPanel = false;
  bool _loading = false;
  String? _loadError;
  List<FrequentDescriptionItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _ownsFocus = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    if (_ownsFocus) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      setState(() {
        _showPanel = true;
      });
      _fetchItems();
    } else {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (!mounted) return;
        if (!_focusNode.hasFocus) {
          setState(() => _showPanel = false);
        }
      });
    }
  }

  Future<void> _fetchItems() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final list = await FrequentDescriptionApiService.list(widget.businessId);
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.toString();
      });
    }
  }

  Future<void> _openManageSheet(BuildContext context) async {
    final t = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _ManageFrequentDescriptionsSheet(
        businessId: widget.businessId,
        title: t.frequentDescriptionsManage,
      ),
    );
    if (mounted && _focusNode.hasFocus) {
      await _fetchItems();
    }
  }

  void _applyText(String text) {
    widget.controller.text = text;
    widget.controller.selection = TextSelection.collapsed(offset: text.length);
    widget.onChanged?.call(text);
    setState(() => _showPanel = false);
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final mergedDecor = widget.decoration.copyWith(
      suffixIcon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.decoration.suffixIcon != null) widget.decoration.suffixIcon!,
          IconButton(
            tooltip: t.frequentDescriptionsManage,
            icon: const Icon(Icons.playlist_add_check_outlined, size: 22),
            onPressed: widget.readOnly ? null : () => _openManageSheet(context),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          maxLines: widget.maxLines,
          maxLength: widget.maxLength,
          buildCounter: widget.buildCounter,
          decoration: mergedDecor,
          textInputAction: widget.textInputAction,
          readOnly: widget.readOnly,
          style: widget.style,
          keyboardType: widget.keyboardType ?? TextInputType.text,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
        ),
        if (_showPanel)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Material(
              elevation: 3,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                      )
                    : _loadError != null
                        ? Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              t.frequentDescriptionsLoadError,
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                            ),
                          )
                        : _items.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(
                                  t.frequentDescriptionsEmpty,
                                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                itemCount: _items.length,
                                itemBuilder: (ctx, i) {
                                  final it = _items[i];
                                  return ListTile(
                                    dense: true,
                                    title: Text(it.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                                    onTap: () => _applyText(it.text),
                                  );
                                },
                              ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ManageFrequentDescriptionsSheet extends StatefulWidget {
  final int businessId;
  final String title;

  const _ManageFrequentDescriptionsSheet({
    required this.businessId,
    required this.title,
  });

  @override
  State<_ManageFrequentDescriptionsSheet> createState() => _ManageFrequentDescriptionsSheetState();
}

class _ManageFrequentDescriptionsSheetState extends State<_ManageFrequentDescriptionsSheet> {
  final TextEditingController _newCtrl = TextEditingController();
  List<FrequentDescriptionItem> _items = const [];
  bool _loading = true;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _newCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await FrequentDescriptionApiService.list(widget.businessId);
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _add() async {
    final t = AppLocalizations.of(context);
    final text = _newCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _saving = true);
    try {
      await FrequentDescriptionApiService.create(widget.businessId, text);
      if (!mounted) return;
      _newCtrl.clear();
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.frequentDescriptionsSaved)));
      }
    } on FrequentDescriptionLimitException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.frequentDescriptionsLimitReached)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.frequentDescriptionsLoadError)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(FrequentDescriptionItem it) async {
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.frequentDescriptionsDeleteTitle),
        content: Text(t.frequentDescriptionsDeleteConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(MaterialLocalizations.of(ctx).deleteButtonTooltip)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await FrequentDescriptionApiService.delete(widget.businessId, it.id);
      await _reload();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.frequentDescriptionsLoadError)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _newCtrl,
                  decoration: InputDecoration(
                    labelText: t.frequentDescriptionsNewLabel,
                    border: const OutlineInputBorder(),
                  ),
                  maxLines: 2,
                  maxLength: 2000,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton(
                  onPressed: _saving ? null : _add,
                  child: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(t.frequentDescriptionsAdd),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.45,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _items.isEmpty
                        ? Center(child: Text(t.frequentDescriptionsEmpty))
                        : ListView.separated(
                            itemCount: _items.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (ctx, i) {
                              final it = _items[i];
                              return ListTile(
                                title: Text(it.text),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _delete(it),
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
