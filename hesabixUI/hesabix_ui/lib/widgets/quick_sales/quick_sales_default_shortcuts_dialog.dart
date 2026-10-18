import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/quick_sales_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';

class QuickSalesDefaultShortcutsDialog extends StatefulWidget {
  final int businessId;
  final QuickSalesService service;

  const QuickSalesDefaultShortcutsDialog({
    super.key,
    required this.businessId,
    required this.service,
  });

  @override
  State<QuickSalesDefaultShortcutsDialog> createState() =>
      _QuickSalesDefaultShortcutsDialogState();
}

class _QuickSalesDefaultShortcutsDialogState
    extends State<QuickSalesDefaultShortcutsDialog> {
  List<Map<String, dynamic>> _rows = const [];
  final Map<String, TextEditingController> _controllers = {};
  String _platform = 'windows';
  bool _loading = true;
  bool _saving = false;

  String _key(int id, String platform) => '$id:$platform';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await widget.service.listDefaultPaymentShortcuts(
        businessId: widget.businessId,
      );
      if (!mounted) return;
      for (final controller in _controllers.values) {
        controller.dispose();
      }
      _controllers.clear();
      for (final row in rows) {
        final id = (row['button_id'] as num).toInt();
        final raw = row['default_shortcuts'];
        final shortcuts = raw is Map
            ? Map<String, dynamic>.from(raw)
            : const {};
        _controllers[_key(id, 'windows')] = TextEditingController(
          text: (shortcuts['windows'] ?? row['default_shortcut'] ?? '')
              .toString(),
        );
        _controllers[_key(id, 'web')] = TextEditingController(
          text: (shortcuts['web'] ?? '').toString(),
        );
      }
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.show(
        context,
        message: ErrorExtractor.forContext(e, context),
        isError: true,
      );
    }
  }

  Future<void> _save() async {
    for (final platform in const ['windows', 'web']) {
      final seen = <String>{};
      for (final row in _rows) {
        final id = (row['button_id'] as num).toInt();
        final value = _controllers[_key(id, platform)]!.text
            .trim()
            .replaceAll(' ', '')
            .toUpperCase();
        if (value.isNotEmpty && !seen.add(value)) {
          SnackBarHelper.show(
            context,
            message:
                'در بخش ${platform == 'web' ? 'وب' : 'ویندوز'} یک میانبر برای چند دکمه انتخاب شده است.',
            isError: true,
          );
          return;
        }
      }
    }
    setState(() => _saving = true);
    try {
      await widget.service.updateDefaultPaymentShortcuts(
        businessId: widget.businessId,
        shortcuts: [
          for (final row in _rows)
            {
              'button_id': row['button_id'],
              'shortcuts': {
                for (final platform in const ['windows', 'web'])
                  platform:
                      _controllers[_key(
                            (row['button_id'] as num).toInt(),
                            platform,
                          )]!
                          .text
                          .trim(),
              },
            },
        ],
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      SnackBarHelper.show(
        context,
        message: ErrorExtractor.forContext(e, context),
        isError: true,
      );
    }
  }

  IconData _targetIcon(String type) => switch (type) {
    'cash_register' => Icons.payments_outlined,
    'bank' => Icons.account_balance_outlined,
    'person' => Icons.person_outline,
    _ => Icons.payment_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('میانبرهای پیش‌فرض کسب‌وکار'),
      content: SizedBox(
        width: 650,
        height: 500,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _rows.isEmpty
            ? const Center(
                child: Text(
                  'هنوز دکمه مشترکی تعریف نشده است. ابتدا در فروش سریع یک دکمه با گزینه «نمایش برای همه کاربران» بسازید.',
                  textAlign: TextAlign.center,
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'این میانبرها برای همه کاربران پیش‌فرض هستند. تنظیم شخصی هر کاربر اولویت دارد.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'windows',
                        icon: Icon(Icons.desktop_windows_outlined),
                        label: Text('ویندوز'),
                      ),
                      ButtonSegment(
                        value: 'web',
                        icon: Icon(Icons.language_outlined),
                        label: Text('وب'),
                      ),
                    ],
                    selected: {_platform},
                    onSelectionChanged: _saving
                        ? null
                        : (value) => setState(() => _platform = value.first),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _platform == 'web'
                        ? 'در وب از ترکیب Ctrl یا Alt با یک حرف یا عدد استفاده کنید؛ میانبرهای مرورگر پذیرفته نمی‌شوند.'
                        : 'در ویندوز کلیدهای F1 تا F12 و ترکیب‌هایی مانند Alt+R قابل استفاده‌اند.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final row = _rows[index];
                        final id = (row['button_id'] as num).toInt();
                        return Row(
                          children: [
                            Icon(
                              _targetIcon(row['target_type']?.toString() ?? ''),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    row['label']?.toString() ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    row['target_name']?.toString() ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 280,
                              child: QuickSalesShortcutRecorderField(
                                controller: _controllers[_key(id, _platform)]!,
                                enabled: !_saving,
                                platform: _platform,
                                compact: true,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('انصراف'),
        ),
        FilledButton.icon(
          onPressed: _saving || _loading || _rows.isEmpty ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: const Text('ذخیره همه'),
        ),
      ],
    );
  }
}

class QuickSalesShortcutRecorderField extends StatefulWidget {
  final TextEditingController controller;
  final bool enabled;
  final String platform;
  final bool compact;

  const QuickSalesShortcutRecorderField({
    super.key,
    required this.controller,
    required this.enabled,
    required this.platform,
    this.compact = false,
  });

  @override
  State<QuickSalesShortcutRecorderField> createState() =>
      _QuickSalesShortcutRecorderFieldState();
}

class _QuickSalesShortcutRecorderFieldState
    extends State<QuickSalesShortcutRecorderField> {
  final FocusNode _focusNode = FocusNode();
  bool _manualEntry = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  bool _isModifier(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.controlLeft ||
      key == LogicalKeyboardKey.controlRight ||
      key == LogicalKeyboardKey.metaLeft ||
      key == LogicalKeyboardKey.metaRight ||
      key == LogicalKeyboardKey.altLeft ||
      key == LogicalKeyboardKey.altRight ||
      key == LogicalKeyboardKey.shiftLeft ||
      key == LogicalKeyboardKey.shiftRight;

  KeyEventResult _record(KeyEvent event) {
    if (_manualEntry || !widget.enabled || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (_isModifier(key)) return KeyEventResult.handled;
    if (key == LogicalKeyboardKey.escape) {
      _focusNode.unfocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.delete) {
      setState(widget.controller.clear);
      return KeyEventResult.handled;
    }
    final keyLabel = key.keyLabel.trim().toUpperCase();
    if (keyLabel.isEmpty) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    final value = <String>[
      if (keyboard.isControlPressed || keyboard.isMetaPressed) 'CTRL',
      if (keyboard.isAltPressed) 'ALT',
      if (keyboard.isShiftPressed) 'SHIFT',
      keyLabel,
    ].join('+');
    setState(() {
      widget.controller.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = widget.platform == 'web';
    return Focus(
      onKeyEvent: (_, event) => _record(event),
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        enabled: widget.enabled,
        readOnly: !_manualEntry,
        textDirection: TextDirection.ltr,
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(
          labelText: widget.compact
              ? 'میانبر'
              : 'کلید میانبر ${isWeb ? 'وب' : 'ویندوز'}',
          hintText: _manualEntry
              ? (isWeb ? 'مثلاً Alt+1' : 'مثلاً F12 یا Alt+R')
              : 'اینجا کلیک کنید و کلیدها را فشار دهید',
          border: const OutlineInputBorder(),
          prefixIcon: Icon(
            isWeb ? Icons.language_outlined : Icons.keyboard_outlined,
          ),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.controller.text.isNotEmpty)
                IconButton(
                  tooltip: 'پاک‌کردن میانبر',
                  onPressed: widget.enabled
                      ? () => setState(widget.controller.clear)
                      : null,
                  icon: const Icon(Icons.clear),
                ),
              TextButton(
                onPressed: widget.enabled
                    ? () {
                        setState(() => _manualEntry = !_manualEntry);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _focusNode.requestFocus();
                        });
                      }
                    : null,
                child: Text(_manualEntry ? 'ضبط کلید' : 'ورود دستی'),
              ),
            ],
          ),
        ),
        onChanged: (_) => setState(() {}),
        onTap: () {
          if (!_manualEntry) {
            widget.controller.selection = TextSelection(
              baseOffset: 0,
              extentOffset: widget.controller.text.length,
            );
          }
        },
      ),
    );
  }
}
