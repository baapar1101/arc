import 'dart:typed_data';

import 'package:dio/dio.dart' as dio;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
class UserSignaturePage extends StatefulWidget {
  const UserSignaturePage({super.key});

  @override
  State<UserSignaturePage> createState() => _UserSignaturePageState();
}

class _UserSignaturePageState extends State<UserSignaturePage> {
  final ApiClient _apiClient = ApiClient();
  Uint8List? _signatureBytes;
  bool _loading = true;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSignature();
  }

  Future<void> _loadSignature() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _apiClient.get<List<int>>(
        '/api/v1/users/me/signature',
        options: dio.Options(responseType: dio.ResponseType.bytes),
      );
      final data = res.data;
      if (data != null && data.isNotEmpty) {
        _signatureBytes = Uint8List.fromList(data);
      } else {
        _signatureBytes = null;
      }
    } catch (e) {
      // اگر 404 باشد یعنی هنوز امضایی ثبت نشده است؛ سایر خطاها را نمایش می‌دهیم
      _signatureBytes = null;
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _pickAndUploadSignature() async {
    if (_uploading) return;
    setState(() {
      _uploading = true;
    });
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      final f = res?.files.isNotEmpty == true ? res!.files.first : null;
      if (f == null || f.bytes == null) return;
      final bytes = f.bytes!;

      final formData = dio.FormData.fromMap({
        'file': dio.MultipartFile.fromBytes(bytes, filename: f.name),
      });
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/users/me/signature',
        data: formData,
        options: dio.Options(contentType: 'multipart/form-data'),
      );
      if (response.data != null && response.data!['success'] == true) {
        _signatureBytes = Uint8List.fromList(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('امضا با موفقیت ذخیره شد')));
        }
      } else {
        throw Exception(response.data?['message'] ?? 'خطا در آپلود امضا');
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
        context,
        message: 'خطا در آپلود امضا: ${ErrorExtractor.forContext(e, context)}',
      );
      }
    } finally {
      if (!mounted) return;
      setState(() {
        _uploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(child: Text(_error!));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('امضا و تصویر کاربر'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'امضای شخصی شما',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'در این بخش می‌توانید تصویر امضای خود را بارگذاری کنید تا در فاکتورها و اسناد استفاده شود.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height: 160,
                    decoration: BoxDecoration(
                      border: Border.all(color: cs.outlineVariant),
                      borderRadius: BorderRadius.circular(8),
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.2),
                    ),
                    alignment: Alignment.center,
                    child: _signatureBytes != null
                        ? Image.memory(
                            _signatureBytes!,
                            fit: BoxFit.contain,
                          )
                        : Text(
                            'هیچ امضایی ثبت نشده است',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _uploading ? null : _pickAndUploadSignature,
                        icon: _uploading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.upload_file),
                        label: const Text('انتخاب و آپلود امضا'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


