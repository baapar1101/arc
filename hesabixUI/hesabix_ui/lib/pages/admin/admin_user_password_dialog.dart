import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/core/api_client.dart';

/// دیالوگ سه‌حالته: توکن بازیابی، رمز انتخابی مدیر، رمز تصادفی.
Future<void> showAdminUserPasswordDialog(
  BuildContext context, {
  required Map<String, dynamic> user,
  VoidCallback? onSuccess,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => _AdminUserPasswordDialog(user: user, onSuccess: onSuccess),
  );
}

int? _parseUserId(Map<String, dynamic> u) {
  final v = u['id'];
  if (v is int) return v;
  if (v is num) return v.toInt();
  return null;
}

class _AdminUserPasswordDialog extends StatefulWidget {
  const _AdminUserPasswordDialog({required this.user, this.onSuccess});

  final Map<String, dynamic> user;
  final VoidCallback? onSuccess;

  @override
  State<_AdminUserPasswordDialog> createState() => _AdminUserPasswordDialogState();
}

class _AdminUserPasswordDialogState extends State<_AdminUserPasswordDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _api = ApiClient();
  final _pass1 = TextEditingController();
  final _pass2 = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _sendNotification = true;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pass1.dispose();
    _pass2.dispose();
    super.dispose();
  }

  String get _displayName {
    final map = widget.user;
    final name = (map['full_name'] as String?) ??
        '${map['first_name'] ?? ''} ${map['last_name'] ?? ''}'.trim();
    if (name.isNotEmpty) return name;
    return 'کاربر';
  }

  void _msg(String m, {bool err = false}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        backgroundColor: err ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  String _err(dynamic e) {
    if (e is Exception) {
      return e.toString();
    }
    return e.toString();
  }

  Future<void> _resetToken() async {
    final id = _parseUserId(widget.user);
    if (id == null) return;
    setState(() => _loading = true);
    try {
      final res = await _api.post<Map<String, dynamic>>(
        '/api/v1/users/$id/reset-password',
        query: {'send_notification': _sendNotification},
      );
      if (res.statusCode == 200) {
        final data = res.data?['data'] as Map<String, dynamic>?;
        final token = data?['token'] as String?;
        if (!mounted) return;
        if (token != null && token.isNotEmpty) {
          if (!context.mounted) return;
          await _showResultDialog(
            context,
            title: 'توکن بازنشانی (فقط محیط توسعه)',
            body: token,
          );
        } else {
          if (!mounted) return;
          _msg(
            _sendNotification
                ? 'توکن ایجاد شد. در صورت فعال بودن کانال‌ها، اعلان برای کاربر ارسال می‌شود.'
                : 'توکن بازیابی ایجاد شد.',
          );
        }
        if (!mounted) return;
        widget.onSuccess?.call();
        if (!context.mounted) return;
        Navigator.of(context).pop();
        return;
      }
    } catch (e) {
      _msg('خطا: ${_err(e)}', err: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setDirect() async {
    if (!_formKey.currentState!.validate()) return;
    final id = _parseUserId(widget.user);
    if (id == null) return;
    setState(() => _loading = true);
    try {
      final res = await _api.post<Map<String, dynamic>>(
        '/api/v1/users/$id/set-password',
        data: {
          'mode': 'direct',
          'new_password': _pass1.text,
          'confirm_password': _pass2.text,
        },
      );
      if (res.statusCode == 200) {
        if (!mounted) return;
        widget.onSuccess?.call();
        if (!mounted) return;
        _msg('رمز عبور توسط شما ثبت شد.');
        _pass1.clear();
        _pass2.clear();
        if (!context.mounted) return;
        Navigator.of(context).pop();
        return;
      }
    } catch (e) {
      _msg('خطا: ${_err(e)}', err: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setRandom() async {
    final id = _parseUserId(widget.user);
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تولید رمز تصادفی'),
        content: const Text(
            'یک رمز قوی تولید و روی حساب کاربر ثبت می‌شود. رمز فقط در مرحلهٔ بعد نمایش داده می‌شود. ادامه می‌دهید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('تأیید')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _loading = true);
    try {
      final res = await _api.post<Map<String, dynamic>>(
        '/api/v1/users/$id/set-password',
        data: {'mode': 'random'},
      );
      if (res.statusCode == 200) {
        final data = res.data?['data'] as Map<String, dynamic>?;
        final plain = data?['plain_password'] as String?;
        if (!mounted) return;
        if (plain != null && plain.isNotEmpty) {
          if (!context.mounted) return;
          await _showResultDialog(
            context,
            title: 'رمز یک‌بار مصرف',
            body: plain,
          );
        } else {
          if (!mounted) return;
          _msg('رمز تولید شد (پاسخ بدون نمایش رمز).', err: false);
        }
        if (!mounted) return;
        widget.onSuccess?.call();
        if (!context.mounted) return;
        Navigator.of(context).pop();
        return;
      }
    } catch (e) {
      _msg('خطا: ${_err(e)}', err: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('مدیریت رمز: $_displayName'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TabBar(
                controller: _tabController,
                labelStyle: const TextStyle(fontSize: 12),
                tabs: const [
                  Tab(text: 'بازیابی (توکن)'),
                  Tab(text: 'انتخابی'),
                  Tab(text: 'تصادفی'),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 220,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _TokenTab(
                      sendNotification: _sendNotification,
                      onChanged: (v) => setState(() => _sendNotification = v),
                      loading: _loading,
                      onSubmit: _resetToken,
                    ),
                    _DirectTab(
                      pass1: _pass1,
                      pass2: _pass2,
                      loading: _loading,
                      onSubmit: _setDirect,
                    ),
                    _RandomTab(loading: _loading, onSubmit: _setRandom, theme: theme),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('بستن'),
        ),
      ],
    );
  }
}

class _TokenTab extends StatelessWidget {
  const _TokenTab({
    required this.sendNotification,
    required this.onChanged,
    required this.loading,
    required this.onSubmit,
  });
  final bool sendNotification;
  final ValueChanged<bool> onChanged;
  final bool loading;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const Text(
          'توکن بازنشانی در پایگاه داده ثبت می‌شود. با فعال بودن اعلان، مثل فراموشی رمز، پیام ارسال می‌گردد.',
          style: TextStyle(fontSize: 12),
        ),
        SwitchListTile(
          value: sendNotification,
          onChanged: loading ? null : onChanged,
          title: const Text('ارسال اعلان به کاربر', style: TextStyle(fontSize: 13)),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: loading ? null : onSubmit,
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('ایجاد توکن بازنشانی'),
        ),
      ],
    );
  }
}

class _DirectTab extends StatelessWidget {
  const _DirectTab({
    required this.pass1,
    required this.pass2,
    required this.loading,
    required this.onSubmit,
  });
  final TextEditingController pass1;
  final TextEditingController pass2;
  final bool loading;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        TextFormField(
          controller: pass1,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'رمز جدید',
            border: OutlineInputBorder(),
          ),
          validator: (v) {
            if (v == null || v.length < 8) {
              return 'حداقل ۸ نویسه';
            }
            return null;
          },
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: pass2,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'تکرار رمز',
            border: OutlineInputBorder(),
          ),
          validator: (v) {
            if (v != pass1.text) {
              return 'تکرار رمز مطابقت ندارد';
            }
            return null;
          },
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: loading ? null : onSubmit,
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('ثبت رمز'),
        ),
      ],
    );
  }
}

class _RandomTab extends StatelessWidget {
  const _RandomTab({
    required this.loading,
    required this.onSubmit,
    required this.theme,
  });
  final bool loading;
  final VoidCallback onSubmit;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Text(
          'یک رمز امن تولید و بلافاصله روی حساب ثبت می‌شود. فقط در گام بعد یک‌بار نمایش داده می‌شود؛ آن را برای کاربر ارسال کنید.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        FilledButton.tonal(
          onPressed: loading ? null : onSubmit,
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('تولید و ثبت رمز تصادفی'),
        ),
      ],
    );
  }
}

Future<void> _showResultDialog(
  BuildContext context, {
  required String title,
  required String body,
}) async {
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: SelectableText(
        body,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
      ),
      actions: [
        TextButton(
          onPressed: () {
            final messenger = ScaffoldMessenger.maybeOf(context);
            Clipboard.setData(ClipboardData(text: body));
            Navigator.pop(c);
            messenger?.showSnackBar(
              const SnackBar(content: Text('در حافظه کپی شد')),
            );
          },
          child: const Text('کپی و بستن'),
        ),
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('بستن')),
      ],
    ),
  );
}

