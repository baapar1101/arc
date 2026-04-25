import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/public_storage_file_share_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';

/// نمایش عمومی فایل از طریق لینک اشتراک (بدون ورود به Hesabix).
class PublicStorageFileSharePage extends StatefulWidget {
  final String token;

  const PublicStorageFileSharePage({super.key, required this.token});

  @override
  State<PublicStorageFileSharePage> createState() => _PublicStorageFileSharePageState();
}

class _PublicStorageFileSharePageState extends State<PublicStorageFileSharePage> {
  final _service = PublicStorageFileShareService();
  final _passwordController = TextEditingController();

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _info;
  String? _accessToken;
  bool _unlocking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.fetchInfo(widget.token);
      if (!mounted) return;
      setState(() {
        _info = data;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.userMessage(e);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.userMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _unlock() async {
    setState(() => _unlocking = true);
    try {
      final data = await _service.unlock(widget.token, _passwordController.text);
      if (!mounted) return;
      final at = data['access_token'] as String?;
      setState(() {
        _accessToken = at;
        _unlocking = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      if (mounted) setState(() => _unlocking = false);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      if (mounted) setState(() => _unlocking = false);
    }
  }

  Future<void> _openFileExternally() async {
    final url = _service.buildFileUrl(widget.token, accessToken: _accessToken);
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        SnackBarHelper.showError(context, message: 'امکان باز کردن لینک وجود ندارد');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('اشتراک فایل'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _buildBody(theme),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('در حال بارگذاری...'),
        ],
      );
    }
    if (_error != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 56, color: theme.colorScheme.error),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: _load, child: const Text('تلاش مجدد')),
        ],
      );
    }

    final info = _info!;
    final name = info['original_name'] as String? ?? 'فایل';
    final mime = (info['mime_type'] as String?) ?? '';
    final requiresPassword = info['requires_password'] == true;
    final fileSize = info['file_size'];

    final needUnlock = requiresPassword && (_accessToken == null || _accessToken!.isEmpty);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (fileSize != null) Text('حجم: $fileSize بایت', style: theme.textTheme.bodySmall),
          const SizedBox(height: 24),
          if (needUnlock) ...[
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'رمز لینک',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _unlock(),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _unlocking ? null : _unlock,
              child: _unlocking
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('تأیید رمز'),
            ),
            const SizedBox(height: 24),
          ],
          if (!needUnlock) ...[
            if (mime.startsWith('image/'))
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  _service.buildFileUrl(widget.token, accessToken: _accessToken),
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  },
                  errorBuilder: (context, error, stack) => const Icon(Icons.broken_image, size: 64),
                ),
              )
            else if (mime.startsWith('video/'))
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Icon(Icons.video_file, size: 64),
                      const SizedBox(height: 12),
                      const Text('برای پخش ویدئو آن را در مرورگر باز کنید.'),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _openFileExternally,
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('باز کردن ویدئو'),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              const Text('برای دانلود یا پیش‌نمایش (مثلاً PDF) فایل را در تب جدید باز کنید.'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _openFileExternally,
                icon: const Icon(Icons.download),
                label: const Text('باز کردن / دانلود'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
