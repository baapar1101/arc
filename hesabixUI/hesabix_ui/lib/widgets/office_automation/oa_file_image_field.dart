import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/api_client.dart';
import '../../services/business_storage_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';

class OaFileImageField extends StatefulWidget {
  final int businessId;
  final String label;
  final String? fileId;
  final ValueChanged<String?> onChanged;
  final String helperText;

  const OaFileImageField({
    super.key,
    required this.businessId,
    required this.label,
    required this.fileId,
    required this.onChanged,
    this.helperText = '',
  });

  @override
  State<OaFileImageField> createState() => _OaFileImageFieldState();
}

class _OaFileImageFieldState extends State<OaFileImageField> {
  final _storage = BusinessStorageService(ApiClient());
  bool _uploading = false;
  MemoryImage? _preview;

  @override
  void initState() {
    super.initState();
    _loadPreview(widget.fileId);
  }

  @override
  void didUpdateWidget(covariant OaFileImageField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fileId != widget.fileId) {
      _loadPreview(widget.fileId);
    }
  }

  Future<void> _loadPreview(String? id) async {
    if (id == null || id.isEmpty) {
      setState(() => _preview = null);
      return;
    }
    try {
      final bytes = await _storage.downloadFile(businessId: widget.businessId, fileId: id);
      if (!mounted) return;
      final u8 = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
      setState(() => _preview = u8.isEmpty ? null : MemoryImage(u8));
    } catch (_) {
      if (mounted) setState(() => _preview = null);
    }
  }

  Future<void> _pick() async {
    final pick = await FilePicker.platform.pickFiles(withData: true, type: FileType.image);
    if (pick == null || pick.files.isEmpty || pick.files.first.bytes == null) return;
    final file = pick.files.first;
    setState(() => _uploading = true);
    try {
      final uploaded = await _storage.uploadFile(
        businessId: widget.businessId,
        fileBytes: file.bytes!,
        filename: file.name,
        moduleContext: 'office_automation',
      );
      final id = (uploaded['id'] ?? uploaded['file_id'] ?? '').toString();
      if (id.isEmpty) return;
      widget.onChanged(id);
      await _loadPreview(id);
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.label, style: Theme.of(context).textTheme.titleSmall),
        if (widget.helperText.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(widget.helperText, style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: 16 / 5,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(12),
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              image: _preview == null ? null : DecorationImage(image: _preview!, fit: BoxFit.contain),
            ),
            child: _uploading ? const Center(child: CircularProgressIndicator()) : const SizedBox.expand(),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: _uploading ? null : _pick,
              icon: const Icon(Icons.upload_file),
              label: Text(t.oaUploadImage),
            ),
            if ((widget.fileId ?? '').isNotEmpty)
              TextButton.icon(
                onPressed: () {
                  widget.onChanged(null);
                  setState(() => _preview = null);
                },
                icon: const Icon(Icons.delete_outline),
                label: Text(t.delete),
              ),
          ],
        ),
      ],
    );
  }
}
