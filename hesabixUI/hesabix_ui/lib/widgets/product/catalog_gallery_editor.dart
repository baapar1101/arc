import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../core/api_client.dart';
import '../../services/business_storage_service.dart';
import '../../utils/snackbar_helper.dart';

class CatalogGalleryEditor extends StatefulWidget {
  final int businessId;
  final List<String> fileIds;
  final ValueChanged<List<String>> onChanged;
  final int maxImages;

  const CatalogGalleryEditor({
    super.key,
    required this.businessId,
    required this.fileIds,
    required this.onChanged,
    this.maxImages = 12,
  });

  @override
  State<CatalogGalleryEditor> createState() => _CatalogGalleryEditorState();
}

class _CatalogGalleryEditorState extends State<CatalogGalleryEditor> {
  final _storage = BusinessStorageService(ApiClient());
  bool _uploading = false;

  String _thumbUrl(String fileId) {
    final base = AppConfig.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    return '$base/api/v1/business/${widget.businessId}/storage/files/$fileId/thumbnail?size=small';
  }

  Future<void> _pickAndUpload() async {
    if (widget.fileIds.length >= widget.maxImages) {
      SnackBarHelper.showError(context, message: 'حداکثر ${widget.maxImages} تصویر مجاز است');
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    setState(() => _uploading = true);
    try {
      final ids = List<String>.from(widget.fileIds);
      for (final f in result.files) {
        if (ids.length >= widget.maxImages) break;
        final bytes = f.bytes;
        if (bytes == null || bytes.isEmpty) continue;
        final uploaded = await _storage.uploadFile(
          businessId: widget.businessId,
          fileBytes: bytes,
          filename: f.name,
          moduleContext: 'products',
        );
        final id = uploaded['id']?.toString() ?? uploaded['file_id']?.toString();
        if (id != null && id.isNotEmpty && !ids.contains(id)) {
          ids.add(id);
        }
      }
      widget.onChanged(ids);
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: e.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _removeAt(int index) {
    final ids = List<String>.from(widget.fileIds);
    ids.removeAt(index);
    widget.onChanged(ids);
  }

  void _move(int from, int to) {
    if (to < 0 || to >= widget.fileIds.length) return;
    final ids = List<String>.from(widget.fileIds);
    final item = ids.removeAt(from);
    ids.insert(to, item);
    widget.onChanged(ids);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('گالری تصاویر', style: theme.textTheme.titleSmall),
            const Spacer(),
            Text('${widget.fileIds.length}/${widget.maxImages}', style: theme.textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'تصاویر تکمیلی برای صفحهٔ جزئیات کاتالوگ. تصویر اصلی کالا از تب «اطلاعات عمومی» است.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...widget.fileIds.asMap().entries.map((entry) {
              final index = entry.key;
              final id = entry.value;
              return _GalleryTile(
                imageUrl: _thumbUrl(id),
                onRemove: () => _removeAt(index),
                onMoveLeft: index > 0 ? () => _move(index, index - 1) : null,
                onMoveRight: index < widget.fileIds.length - 1 ? () => _move(index, index + 1) : null,
              );
            }),
            OutlinedButton.icon(
              onPressed: _uploading ? null : _pickAndUpload,
              icon: _uploading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('افزودن تصویر'),
            ),
          ],
        ),
      ],
    );
  }
}

class _GalleryTile extends StatelessWidget {
  final String imageUrl;
  final VoidCallback onRemove;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;

  const _GalleryTile({
    required this.imageUrl,
    required this.onRemove,
    this.onMoveLeft,
    this.onMoveRight,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            imageUrl,
            width: 96,
            height: 96,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 96,
              height: 96,
              color: Colors.grey.shade200,
              child: const Icon(Icons.broken_image_outlined),
            ),
          ),
        ),
        Positioned(
          top: 2,
          left: 2,
          child: IconButton.filledTonal(
            style: IconButton.styleFrom(
              minimumSize: const Size(28, 28),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 16),
          ),
        ),
        if (onMoveLeft != null || onMoveRight != null)
          Positioned(
            bottom: 2,
            right: 2,
            left: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (onMoveLeft != null)
                  IconButton.filledTonal(
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    onPressed: onMoveLeft,
                    icon: const Icon(Icons.chevron_right),
                  ),
                if (onMoveRight != null)
                  IconButton.filledTonal(
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    onPressed: onMoveRight,
                    icon: const Icon(Icons.chevron_left),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
