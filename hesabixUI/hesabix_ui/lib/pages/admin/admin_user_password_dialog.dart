import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/config/app_config.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'admin_compact_scaffold.dart';

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

/// الویت: `reset_link` از بک‌اند → ساخت از `token` (یا در نهایت نمایش توکن خام)
String? _resolvePasswordResetDisplayUrl(Map<String, dynamic>? data) {
  if (data == null) return null;
  final link = data['reset_link'] as String?;
  if (link != null && link.isNotEmpty) return link;
  final token = data['token'] as String?;
  if (token == null || token.isEmpty) return null;
  return AppConfig.buildPasswordResetUrl(token) ?? token;
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
    return adminTx(context, 'کاربر', 'User');
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

  String _err(Object e) => ErrorExtractor.userMessage(e);

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
        if (!mounted) return;
        final displayUrl = _resolvePasswordResetDisplayUrl(data);
        if (displayUrl != null && displayUrl.isNotEmpty) {
          if (!context.mounted) return;
          await _showResultDialog(
            context,
            title: adminTx(context, 'لینک بازیابی رمز', 'Password reset link'),
            body: displayUrl,
            hint: adminTx(
              context,
              'این لینک را کپی کنید و برای کاربر بفرستید. با باز کردن آن، صفحهٔ تعیین رمز جدید باز می‌شود.',
              'Copy this link and send it to the user. Opening it shows the page for choosing a new password.',
            ),
          );
        } else {
          if (!mounted) return;
          _msg(
            _sendNotification
                ? adminTx(context, 'توکن ثبت شد و در صورت فعال بودن اعلان برای کاربر ارسال می‌شود. لینک در پاسخ ساخته نشد.', 'The token was saved. If notifications are on, it is sent to the user. A link could not be built from this response.')
                : adminTx(context, 'توکن بازیابی ثبت شد. برای نمایش لینک، آدرس عمومی برنامه را پیکربندی کنید.', 'The reset token was saved. Configure the public app address to show a link.'),
          );
        }
        if (!mounted) return;
        widget.onSuccess?.call();
        if (!context.mounted) return;
        Navigator.of(context).pop();
        return;
      }
    } catch (e) {
      _msg('${adminTx(context, 'خطا', 'Error')}: ${_err(e)}', err: true);
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
        _msg(adminTx(context, 'رمز عبور ثبت شد.', 'Password saved.'));
        _pass1.clear();
        _pass2.clear();
        if (!context.mounted) return;
        Navigator.of(context).pop();
        return;
      }
    } catch (e) {
      _msg('${adminTx(context, 'خطا', 'Error')}: ${_err(e)}', err: true);
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
        title: Text(adminTx(context, 'تولید رمز تصادفی', 'Generate a random password')),
        content: Text(adminTx(
          context,
          'یک رمز قوی ساخته و روی حساب کاربر ثبت می‌شود. رمز فقط یک‌بار نمایش داده می‌شود.',
          'A strong password is created and saved on the account. It is shown only once.',
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(adminTx(context, 'انصراف', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(adminTx(context, 'تأیید', 'Confirm'))),
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
            title: adminTx(context, 'رمز یک‌بار مصرف', 'One-time password'),
            body: plain,
          );
        } else {
          if (!mounted) return;
          _msg(adminTx(context, 'رمز تولید شد، ولی در پاسخ نمایش داده نشد.', 'A password was generated, but it was not included in the response.'));
        }
        if (!mounted) return;
        widget.onSuccess?.call();
        if (!context.mounted) return;
        Navigator.of(context).pop();
        return;
      }
    } catch (e) {
      _msg('${adminTx(context, 'خطا', 'Error')}: ${_err(e)}', err: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('${adminTx(context, 'مدیریت رمز', 'Password')}: $_displayName'),
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
                tabs: [
                  Tab(text: adminTx(context, 'بازیابی', 'Reset link')),
                  Tab(text: adminTx(context, 'انتخابی', 'Chosen')),
                  Tab(text: adminTx(context, 'تصادفی', 'Random')),
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
          child: Text(adminTx(context, 'بستن', 'Close')),
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
        Text(
          adminTx(
            context,
            'توکن در سرور ثبت می‌شود. لینک برای کپی در پاسخ می‌آید و اگر اعلان روشن باشد برای کاربر هم فرستاده می‌شود.',
            'The token is saved on the server. The copyable link is shown in the response, and a notification is sent if that option is on.',
          ),
          style: const TextStyle(fontSize: 12),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: sendNotification,
          onChanged: loading ? null : onChanged,
          title: Text(adminTx(context, 'ارسال اعلان به کاربر', 'Notify the user'), style: const TextStyle(fontSize: 13)),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: loading ? null : onSubmit,
          child: loading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(adminTx(context, 'ایجاد توکن بازنشانی', 'Create reset token')),
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
          decoration: InputDecoration(
            isDense: true,
            labelText: adminTx(context, 'رمز جدید', 'New password'),
            border: const OutlineInputBorder(),
          ),
          validator: (v) {
            if (v == null || v.length < 8) {
              return adminTx(context, 'حداقل ۸ نویسه', 'At least 8 characters');
            }
            return null;
          },
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: pass2,
          obscureText: true,
          decoration: InputDecoration(
            isDense: true,
            labelText: adminTx(context, 'تکرار رمز', 'Repeat password'),
            border: const OutlineInputBorder(),
          ),
          validator: (v) {
            if (v != pass1.text) {
              return adminTx(context, 'تکرار رمز مطابقت ندارد', 'The passwords do not match');
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
              : Text(adminTx(context, 'ثبت رمز', 'Save password')),
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
          adminTx(
            context,
            'یک رمز امن ساخته و همان لحظه روی حساب ثبت می‌شود. فقط یک‌بار نشان داده می‌شود؛ آن را برای کاربر بفرستید.',
            'A secure password is created and saved immediately. It is shown only once; send it to the user.',
          ),
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
              : Text(adminTx(context, 'تولید و ثبت رمز تصادفی', 'Generate and save a random password')),
        ),
      ],
    );
  }
}

Future<void> _showResultDialog(
  BuildContext context, {
  required String title,
  required String body,
  String? hint,
}) async {
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hint != null) ...[
              Text(hint, style: Theme.of(c).textTheme.bodySmall),
              const SizedBox(height: 12),
            ],
            SelectableText(
              body,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            final messenger = ScaffoldMessenger.maybeOf(context);
            Clipboard.setData(ClipboardData(text: body));
            Navigator.pop(c);
            messenger?.showSnackBar(
              SnackBar(content: Text(adminTx(context, 'در حافظه کپی شد', 'Copied'))),
            );
          },
          child: Text(adminTx(context, 'کپی', 'Copy')),
        ),
        TextButton(onPressed: () => Navigator.pop(c), child: Text(adminTx(context, 'بستن', 'Close'))),
      ],
    ),
  );
}

