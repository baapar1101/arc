import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/telephony/telephony_api.dart';
import '../../services/telephony/telephony_session_controller.dart';

Future<void> showTelephonyDialerSheet(
  BuildContext context, {
  required int businessId,
  required TelephonySessionController session,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      final screen = MediaQuery.sizeOf(ctx);
      return Dialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: screen.width < 480 ? 16 : 24,
          vertical: screen.height < 640 ? 12 : 24,
        ),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 420,
            maxHeight: screen.height * 0.88,
          ),
          child: TelephonyDialerSheet(businessId: businessId, session: session),
        ),
      );
    },
  );
}

class TelephonyDialerSheet extends StatefulWidget {
  final int businessId;
  final TelephonySessionController session;

  const TelephonyDialerSheet({super.key, required this.businessId, required this.session});

  @override
  State<TelephonyDialerSheet> createState() => _TelephonyDialerSheetState();
}

class _TelephonyDialerSheetState extends State<TelephonyDialerSheet> {
  static const _digits = <String, String>{
    '1': '',
    '2': 'ABC',
    '3': 'DEF',
    '4': 'GHI',
    '5': 'JKL',
    '6': 'MNO',
    '7': 'PQRS',
    '8': 'TUV',
    '9': 'WXYZ',
    '*': '',
    '0': '+',
    '#': '',
  };

  final _ctrl = TextEditingController();
  final _api = TelephonyApi();
  List<Map<String, dynamic>> _suggestions = [];
  bool _calling = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () async {
      if (v.trim().length < 3) {
        if (mounted) setState(() => _suggestions = []);
        return;
      }
      try {
        final res = await _api.lookupNumber(widget.businessId, v.trim());
        final persons = (res['persons'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        if (mounted) setState(() => _suggestions = persons);
      } catch (_) {}
    });
    setState(() {});
  }

  Future<void> _call({int? personId}) async {
    final number = _ctrl.text.trim();
    if (number.isEmpty) return;
    setState(() => _calling = true);
    try {
      await widget.session.clickToCall(destination: number, personId: personId);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('در حال برقراری تماس…')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _calling = false);
    }
  }

  void _tapDigit(String d) {
    _ctrl.text = '${_ctrl.text}$d';
    _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    _onChanged(_ctrl.text);
    HapticFeedback.selectionClick();
  }

  String _displayNumber(Object? value) => value?.toString() ?? '';

  Widget _buildKey(String digit) {
    final letters = _digits[digit] ?? '';
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _tapDigit(digit),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              digit,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
            ),
            if (letters.isNotEmpty)
              Text(
                letters,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.4,
                      color: scheme.onSurfaceVariant,
                      height: 1.2,
                    ),
              )
            else
              const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
            child: Row(
              children: [
                const SizedBox(width: 40),
                Expanded(
                  child: Text(
                    'شماره‌گیر',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'بستن',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: TextField(
                      controller: _ctrl,
                      keyboardType: TextInputType.phone,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                      decoration: InputDecoration(
                        hintText: 'شماره را وارد کنید',
                        hintTextDirection: TextDirection.rtl,
                        filled: true,
                        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: _onChanged,
                    ),
                  ),
                  if (_suggestions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ..._suggestions.take(4).map(
                      (p) {
                        final number = _displayNumber(p['mobile'] ?? p['phone']);
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.person_outline),
                          title: Text('${p['name']}'),
                          subtitle: Directionality(
                            textDirection: TextDirection.ltr,
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(number),
                            ),
                          ),
                          onTap: () {
                            _ctrl.text = number;
                            _call(personId: p['id'] is int ? p['id'] as int : int.tryParse('${p['id']}'));
                          },
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 3,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.25,
                      children: [
                        for (final d in ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'])
                          _buildKey(d),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _calling ? null : () => _call(),
                        icon: _calling
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.phone_rounded),
                        label: const Text('تماس'),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 52,
                      width: 52,
                      child: IconButton.filledTonal(
                        tooltip: 'پاک کردن',
                        onPressed: () {
                          if (_ctrl.text.isEmpty) return;
                          _ctrl.text = _ctrl.text.substring(0, _ctrl.text.length - 1);
                          _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
                          _onChanged(_ctrl.text);
                        },
                        icon: const Icon(Icons.backspace_outlined),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
