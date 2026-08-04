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
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (ctx) => TelephonyDialerSheet(businessId: businessId, session: session),
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('شماره‌گیر', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            keyboardType: TextInputType.phone,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(letterSpacing: 1.2, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: 'شماره را وارد کنید',
              filled: true,
              fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
            onChanged: _onChanged,
          ),
          if (_suggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            ..._suggestions.take(4).map(
              (p) => ListTile(
                dense: true,
                leading: const Icon(Icons.person_outline),
                title: Text('${p['name']}'),
                subtitle: Text('${p['mobile'] ?? p['phone'] ?? ''}'),
                onTap: () {
                  _ctrl.text = '${p['mobile'] ?? p['phone'] ?? ''}';
                  _call(personId: p['id'] is int ? p['id'] as int : int.tryParse('${p['id']}'));
                },
              ),
            ),
          ],
          const SizedBox(height: 12),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.55,
            children: [
              for (final d in ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'])
                FilledButton.tonal(
                  onPressed: () => _tapDigit(d),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(d, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _calling ? null : () => _call(),
                    icon: _calling
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
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
        ],
      ),
    );
  }
}
