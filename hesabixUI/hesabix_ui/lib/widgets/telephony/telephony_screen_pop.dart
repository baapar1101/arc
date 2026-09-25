import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth_store.dart';
import '../../core/business_nav.dart';
import '../../services/telephony/telephony_api.dart';
import '../../services/telephony/telephony_session_controller.dart';

class TelephonyScreenPopOverlay extends StatefulWidget {
  final int businessId;
  final TelephonySessionController session;
  final AuthStore authStore;

  const TelephonyScreenPopOverlay({
    super.key,
    required this.businessId,
    required this.session,
    required this.authStore,
  });

  @override
  State<TelephonyScreenPopOverlay> createState() => _TelephonyScreenPopOverlayState();
}

class _TelephonyScreenPopOverlayState extends State<TelephonyScreenPopOverlay> {
  final _noteCtrl = TextEditingController();
  final _api = TelephonyApi();
  bool _busy = false;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _ctx => widget.session.screenPop ?? const {};
  Map<String, dynamic>? get _call =>
      _ctx['call'] is Map ? Map<String, dynamic>.from(_ctx['call'] as Map) : null;
  Map<String, dynamic>? get _person =>
      _ctx['person'] is Map ? Map<String, dynamic>.from(_ctx['person'] as Map) : null;
  Map<String, dynamic>? get _lead =>
      _ctx['lead'] is Map ? Map<String, dynamic>.from(_ctx['lead'] as Map) : null;
  Map<String, dynamic>? get _balance =>
      _ctx['balance'] is Map ? Map<String, dynamic>.from(_ctx['balance'] as Map) : null;

  Future<void> _createLead() async {
    final callId = _call?['id'];
    if (callId == null) return;
    setState(() => _busy = true);
    try {
      await _api.createLeadFromCall(widget.businessId, int.parse('$callId'));
      await widget.session.unawaitedOpenPop(int.parse('$callId'));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('سرنخ ایجاد شد')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createPerson() async {
    final callId = _call?['id'];
    if (callId == null) return;
    setState(() => _busy = true);
    try {
      await _api.createPersonFromCall(widget.businessId, int.parse('$callId'));
      await widget.session.unawaitedOpenPop(int.parse('$callId'));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('مخاطب ایجاد شد')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveNote() async {
    final callId = _call?['id'];
    if (callId == null) return;
    setState(() => _busy = true);
    try {
      await widget.session.saveCallNote(callId: int.parse('$callId'), note: _noteCtrl.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('یادداشت ذخیره شد')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _hangup() async {
    setState(() => _busy = true);
    try {
      await widget.session.hangupActiveCall();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('دستور قطع تماس ارسال شد')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _headerTitle(String status) {
    switch (status) {
      case 'ringing':
        return 'تماس ورودی';
      case 'answered':
        return 'در مکالمه';
      case 'completed':
        return 'تماس پایان یافت';
      case 'missed':
        return 'تماس از دست‌رفته';
      default:
        return 'تماس فعال';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 900;
    final status = '${_call?['status'] ?? ''}';
    final number =
        '${_call?['from_number_normalized'] ?? _call?['from_number_raw'] ?? _call?['to_number_normalized'] ?? ''}';
    final title = _person?['name']?.toString() ?? _lead?['name']?.toString() ?? 'شماره ناشناس';
    final anonymous = _person == null && _lead == null;
    final inProgress = status == 'ringing' || status == 'answered';
    final headerColor = status == 'ringing'
        ? const Color(0xFFD97706)
        : status == 'missed'
            ? scheme.error
            : scheme.primary;

    final panel = Material(
      elevation: 12,
      shadowColor: scheme.shadow.withValues(alpha: 0.28),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      color: scheme.surface,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isWide ? 420 : width,
          maxHeight: MediaQuery.sizeOf(context).height * (isWide ? 0.78 : 0.72),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    headerColor,
                    headerColor.withValues(alpha: 0.82),
                  ],
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    status == 'ringing'
                        ? Icons.ring_volume_rounded
                        : status == 'missed'
                            ? Icons.call_missed_rounded
                            : Icons.phone_in_talk_rounded,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _headerTitle(status),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        Text(
                          number,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: widget.session.closeScreenPop,
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  if (_person?['company_name'] != null) ...[
                    const SizedBox(height: 4),
                    Text('${_person!['company_name']}', style: TextStyle(color: scheme.onSurfaceVariant)),
                  ],
                  if (_balance != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.account_balance_wallet_outlined, color: scheme.onSecondaryContainer, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'مانده: ${_balance!['amount']} · ${_balance!['status']}',
                              style: TextStyle(color: scheme.onSecondaryContainer, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if ((_ctx['overdue_checks'] as List?)?.isNotEmpty == true) ...[
                    const SizedBox(height: 12),
                    Text('چک‌های سررسید/معوق', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    ...((_ctx['overdue_checks'] as List).take(3)).map((c) {
                      final m = Map<String, dynamic>.from(c as Map);
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.money_outlined, color: scheme.error, size: 20),
                        title: Text('چک ${m['check_number']}'),
                        subtitle: Text('${m['amount']} · ${m['status'] ?? ''}'),
                      );
                    }),
                  ],
                  if ((_ctx['open_deals'] as List?)?.isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    Text('معاملات باز', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    ...((_ctx['open_deals'] as List).take(3)).map((d) {
                      final m = Map<String, dynamic>.from(d as Map);
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.handshake_outlined, size: 20),
                        title: Text('${m['title'] ?? m['code'] ?? ''}'),
                        subtitle: Text('${m['amount'] ?? ''}'),
                      );
                    }),
                  ],
                  const SizedBox(height: 14),
                  if ((_ctx['recent_documents'] as List?)?.isNotEmpty == true) ...[
                    Text('آخرین اسناد', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    ...((_ctx['recent_documents'] as List).take(3)).map((d) {
                      final m = Map<String, dynamic>.from(d as Map);
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.receipt_long_outlined, size: 20),
                        title: Text('${m['code'] ?? ''}'),
                        subtitle: Text('${m['document_type'] ?? ''}'),
                      );
                    }),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: _noteCtrl,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: 'یادداشت سریع',
                      filled: true,
                      fillColor: scheme.surfaceContainerLowest,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (anonymous) ...[
                    FilledButton.tonal(
                      onPressed: _busy ? null : _createLead,
                      child: const Text('ایجاد سرنخ'),
                    ),
                    OutlinedButton(
                      onPressed: _busy ? null : _createPerson,
                      child: const Text('ایجاد مخاطب'),
                    ),
                  ] else if (_person != null)
                    FilledButton.tonal(
                      onPressed: () {
                        context.go(
                          context.businessPanelUrl(widget.businessId, 'crm/customer-360/${_person!['id']}'),
                        );
                      },
                      child: const Text('پرونده مشتری'),
                    ),
                  FilledButton(
                    onPressed: _busy ? null : _saveNote,
                    child: const Text('ذخیره یادداشت'),
                  ),
                  if (inProgress)
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: scheme.error,
                        foregroundColor: scheme.onError,
                      ),
                      onPressed: _busy ? null : _hangup,
                      child: const Text('قطع تماس'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (isWide) {
      return Align(
        alignment: AlignmentDirectional.topEnd,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: panel,
        ),
      );
    }

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
        child: panel,
      ),
    );
  }
}
