import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/business_storage_service.dart';
import 'package:hesabix_ui/utils/web/web_utils.dart' as web_utils;
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/snackbar_helper.dart';

/// صفحه فایل منیجر برای مدیریت فایل‌های کسب‌وکار
class StorageFileManagerPage extends StatefulWidget {
  final int businessId;

  const StorageFileManagerPage({
    super.key,
    required this.businessId,
  });

  @override
  State<StorageFileManagerPage> createState() => _StorageFileManagerPageState();
}

class _StorageFileManagerPageState extends State<StorageFileManagerPage> {
  late final BusinessStorageService _storageService;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _allFiles = const <Map<String, dynamic>>[];
  String? _currentModuleContext; // null = ریشه، مقدار = پوشه فعلی
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _storageService = BusinessStorageService(ApiClient());
    _load();
    _checkAndShowHelp();
  }

  Future<void> _checkAndShowHelp() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'file_manager_help_shown_${widget.businessId}';
    final helpShown = prefs.getBool(key) ?? false;
    
    if (!helpShown && mounted) {
      // کمی تاخیر برای اینکه صفحه کاملاً لود شود
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        _showHelpDialog();
      }
    }
  }

  Future<void> _showHelpDialog() async {
    final theme = Theme.of(context);
    bool dontShowAgain = false;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.help_outline, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('راهنمای فایل منیجر'),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHelpItem(
                  icon: Icons.folder,
                  title: 'ورود به پوشه',
                  description: 'برای مشاهده فایل‌های یک بخش، روی پوشه مورد نظر کلیک کنید.',
                  theme: theme,
                ),
                const SizedBox(height: 16),
                _buildHelpItem(
                  icon: Icons.edit,
                  title: 'تغییر نام فایل',
                  description: 'برای تغییر نام فایل، روی فایل کلیک راست کنید (یا long press) و گزینه "تغییر نام" را انتخاب کنید.\nنکته: فرمت فایل (مثل .pdf) قابل تغییر نیست.',
                  theme: theme,
                ),
                const SizedBox(height: 16),
                _buildHelpItem(
                  icon: Icons.download,
                  title: 'دانلود فایل',
                  description: 'برای دانلود فایل، روی فایل کلیک راست کنید (یا long press) و گزینه "دانلود" را انتخاب کنید.',
                  theme: theme,
                ),
                const SizedBox(height: 16),
                _buildHelpItem(
                  icon: Icons.delete,
                  title: 'حذف فایل',
                  description: 'برای حذف فایل، روی فایل کلیک راست کنید (یا long press) و گزینه "حذف" را انتخاب کنید.',
                  theme: theme,
                ),
                const SizedBox(height: 16),
                _buildHelpItem(
                  icon: Icons.image,
                  title: 'پیش‌نمایش عکس',
                  description: 'برای مشاهده پیش‌نمایش عکس‌ها، روی فایل عکس کلیک کنید.',
                  theme: theme,
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  value: dontShowAgain,
                  onChanged: (value) {
                    setDialogState(() {
                      dontShowAgain = value ?? false;
                    });
                  },
                  title: const Text('دیگر نشان نده'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                if (dontShowAgain) {
                  final prefs = await SharedPreferences.getInstance();
                  final key = 'file_manager_help_shown_${widget.businessId}';
                  await prefs.setBool(key, true);
                }
                Navigator.pop(context);
              },
              child: const Text('متوجه شدم'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpItem({
    required IconData icon,
    required String title,
    required String description,
    required ThemeData theme,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: theme.colorScheme.primary,
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // دریافت همه فایل‌ها با pagination
      final allFiles = <Map<String, dynamic>>[];
      int page = 1;
      const limit = 100; // حداکثر مقدار مجاز توسط API
      bool hasMore = true;

      while (hasMore) {
        final files = await _storageService.listFiles(
          businessId: widget.businessId,
          page: page,
          limit: limit,
        );
        
        allFiles.addAll(files);
        
        // اگر تعداد فایل‌های دریافت شده کمتر از limit باشد، یعنی آخرین صفحه است
        if (files.length < limit) {
          hasMore = false;
        } else {
          page++;
        }
      }

      setState(() {
        _allFiles = allFiles;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _uploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.bytes == null) return;

      setState(() => _uploading = true);

      try {
        await _storageService.uploadFile(
          businessId: widget.businessId,
          fileBytes: file.bytes!,
          filename: file.name,
          moduleContext: _currentModuleContext ?? 'accounting',
        );

        if (mounted) {
          SnackBarHelper.showSuccess(context, message: 'فایل با موفقیت آپلود شد');
          _load();
        }
      } catch (e) {
        if (mounted) {
          SnackBarHelper.showError(context, message: 'خطا در آپلود فایل: $e');
        }
      } finally {
        if (mounted) {
          setState(() => _uploading = false);
        }
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: 'خطا: $e');
        setState(() => _uploading = false);
      }
    }
  }

  Future<void> _deleteFile(Map<String, dynamic> file) async {
    final confirmed = await _showDeleteConfirmation(file);
    if (confirmed != true) return;

    final fileId = file['id'] as String;

    try {
      await _storageService.deleteFile(
        businessId: widget.businessId,
        fileId: fileId,
      );
      if (mounted) {
        _load();
        SnackBarHelper.showSuccess(context, message: 'فایل با موفقیت حذف شد');
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: 'خطا: $e');
      }
    }
  }

  Future<bool?> _showDeleteConfirmation(Map<String, dynamic> file) async {
    List<Map<String, dynamic>> dependencies = <Map<String, dynamic>>[];
    String? usageError;
    try {
      final usage = await _storageService.getFileUsage(
        businessId: widget.businessId,
        fileId: file['id'] as String,
      );
      dependencies = (usage['dependencies'] as List?)
              ?.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          <Map<String, dynamic>>[];
    } catch (e) {
      usageError = '$e';
    }

    if (!mounted) return false;

    final theme = Theme.of(context);

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف فایل'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'آیا از حذف "${file['original_name'] ?? ''}" اطمینان دارید؟',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            if (usageError != null)
              Text(
                'خطا در دریافت وابستگی‌ها: $usageError',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.red),
              )
            else if (dependencies.isEmpty)
              Text(
                'این فایل در هیچ بخشی استفاده نشده است.',
                style: theme.textTheme.bodySmall,
              )
            else ...[
              Text(
                'این فایل در بخش‌های زیر استفاده شده است:',
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 150,
                child: ListView.builder(
                  itemCount: dependencies.length,
                  itemBuilder: (context, index) {
                    final dep = dependencies[index];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.link, color: theme.colorScheme.primary, size: 20),
                      title: Text(dep['description'] as String? ?? '-', style: theme.textTheme.bodyMedium),
                      subtitle: Text(
                        '${dep['module'] ?? ''} • ${dep['entity_type'] ?? ''} • ${dep['entity_id'] ?? ''}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'با حذف فایل، لینک‌های بالا به صورت خودکار پاک می‌شوند.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('لغو'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }

  Future<void> _renameFile(Map<String, dynamic> file) async {
    final currentName = file['original_name'] as String? ?? '';
    final fileId = file['id'] as String;

    // استخراج extension از نام فعلی
    final extension = _getFileExtension(currentName);
    final nameWithoutExtension = _removeFileExtension(currentName);

    final newNameController = TextEditingController(text: nameWithoutExtension);
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تغییر نام فایل'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: newNameController,
              decoration: InputDecoration(
                labelText: 'نام جدید',
                hintText: 'نام فایل (بدون فرمت)',
                border: const OutlineInputBorder(),
                suffixText: extension.isNotEmpty ? extension : null,
              ),
              autofocus: true,
            ),
            if (extension.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'فرمت فایل: $extension',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('لغو'),
          ),
          FilledButton(
            onPressed: () {
              final newName = newNameController.text.trim();
              if (newName.isNotEmpty) {
                // اضافه کردن extension به نام جدید
                final finalName = extension.isNotEmpty 
                    ? '$newName$extension'
                    : newName;
                Navigator.pop(context, finalName);
              }
            },
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty || result == currentName) return;

    // اطمینان از اینکه extension تغییر نکرده است
    final finalName = _ensureCorrectExtension(result, extension);

    try {
      await _storageService.renameFile(
        businessId: widget.businessId,
        fileId: fileId,
        newName: finalName,
      );
      if (mounted) {
        _load();
        SnackBarHelper.showSuccess(context, message: 'نام فایل با موفقیت تغییر یافت');
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: 'خطا در تغییر نام: $e');
      }
    }
  }

  String _getFileExtension(String filename) {
    final lastDot = filename.lastIndexOf('.');
    if (lastDot == -1 || lastDot == filename.length - 1) {
      return '';
    }
    return filename.substring(lastDot);
  }

  String _removeFileExtension(String filename) {
    final lastDot = filename.lastIndexOf('.');
    if (lastDot == -1) {
      return filename;
    }
    return filename.substring(0, lastDot);
  }

  String _ensureCorrectExtension(String filename, String originalExtension) {
    if (originalExtension.isEmpty) {
      return filename;
    }
    
    final currentExtension = _getFileExtension(filename);
    if (currentExtension.toLowerCase() != originalExtension.toLowerCase()) {
      // اگر extension تغییر کرده، آن را با extension اصلی جایگزین می‌کنیم
      final nameWithoutExtension = _removeFileExtension(filename);
      return '$nameWithoutExtension$originalExtension';
    }
    
    return filename;
  }

  Future<void> _downloadFile(Map<String, dynamic> file) async {
    final fileId = file['id'] as String;
    final fileName = file['original_name'] as String? ?? 'file';
    final mimeType = file['mime_type'] as String? ?? 'application/octet-stream';
    
    try {
      final bytes = await _storageService.downloadFile(
        businessId: widget.businessId,
        fileId: fileId,
      );

      if (bytes.isEmpty) {
        throw Exception('فایل خالی است');
      }

      if (kIsWeb) {
        await web_utils.saveBytesAsFileWeb(bytes, fileName, mimeType: mimeType);
      } else {
        final uint8Bytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
        final extension = _getFileExtension(fileName).replaceFirst('.', '');
        final safeExt = extension.isEmpty ? 'bin' : extension;
        await FileSaver.instance.saveFile(
          name: fileName,
          bytes: uint8Bytes,
          ext: safeExt,
        );
        if (mounted) {
          SnackBarHelper.showSuccess(context, message: 'فایل با موفقیت ذخیره شد');
        }
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: 'خطا در دانلود فایل: $e');
      }
    }
  }

  void _enterFolder(String? moduleContext) {
    setState(() {
      _currentModuleContext = moduleContext;
    });
  }

  void _goBack() {
    setState(() {
      _currentModuleContext = null;
    });
  }

  List<Map<String, dynamic>> _getFolders() {
    final folders = <String, Map<String, dynamic>>{};
    for (final file in _allFiles) {
      final context = file['module_context'] as String?;
      if (context != null && context.isNotEmpty) {
        if (!folders.containsKey(context)) {
          folders[context] = {
            'module_context': context,
            'name': _getFolderName(context),
            'count': 0,
          };
        }
        folders[context]!['count'] = (folders[context]!['count'] as int) + 1;
      }
    }
    return folders.values.toList();
  }

  String _getFolderName(String moduleContext) {
    switch (moduleContext) {
      case 'accounting':
        return 'حسابداری';
      case 'tickets':
        return 'تیکت‌ها';
      case 'business_logo':
        return 'لوگو کسب‌وکار';
      default:
        return moduleContext;
    }
  }

  List<Map<String, dynamic>> _getCurrentFiles() {
    if (_currentModuleContext == null) {
      // در ریشه: فقط فایل‌های بدون module_context
      return _allFiles.where((f) => 
        f['module_context'] == null || 
        (f['module_context'] as String?)?.isEmpty == true
      ).toList();
    } else {
      // در پوشه: فایل‌های با module_context مشخص
      return _allFiles.where((f) => 
        f['module_context'] == _currentModuleContext
      ).toList();
    }
  }

  bool _isImage(String? mimeType) {
    return mimeType != null && mimeType.startsWith('image/');
  }

  IconData _getFileIconData(String? mimeType) {
    if (mimeType == null) return Icons.insert_drive_file;
    if (mimeType.startsWith('image/')) return Icons.image;
    if (mimeType.startsWith('video/')) return Icons.video_file;
    if (mimeType.contains('pdf')) return Icons.picture_as_pdf;
    if (mimeType.contains('word') || mimeType.contains('document')) return Icons.description;
    if (mimeType.contains('excel') || mimeType.contains('spreadsheet')) return Icons.table_chart;
    return Icons.insert_drive_file;
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _getBreadcrumbText() {
    if (_currentModuleContext == null) {
      return 'همه فایل‌ها';
    } else {
      return 'همه فایل‌ها > ${_getFolderName(_currentModuleContext!)}';
    }
  }

  void _showImagePreview(String fileId, String fileName) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Stack(
          children: [
            Center(
              child: FutureBuilder<List<int>>(
                future: _storageService.downloadFile(
                  businessId: widget.businessId,
                  fileId: fileId,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const CircularProgressIndicator(color: Colors.white);
                  }
                  if (snapshot.hasError || !snapshot.hasData) {
                    return const Icon(Icons.error, color: Colors.white, size: 64);
                  }
                  // برای وب، باید از URL استفاده کنیم
                  return Image.memory(
                    Uint8List.fromList(snapshot.data!),
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(Icons.error, color: Colors.white, size: 64);
                    },
                  );
                },
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('فایل منیجر'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/business/${widget.businessId}/storage-files'),
        ),
        actions: [
          IconButton(
            onPressed: _showBusinessSharesSheet,
            icon: const Icon(Icons.link),
            tooltip: 'مدیریت لینک‌های اشتراک',
          ),
          IconButton(
            onPressed: _showHelpDialog,
            icon: const Icon(Icons.help_outline),
            tooltip: 'راهنما',
          ),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'بروزرسانی',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _load,
                        child: const Text('تلاش مجدد'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // نوار آدرس و دکمه بازگشت
                    _buildToolbar(theme),
                    // محتوای فایل‌ها و پوشه‌ها
                    Expanded(
                      child: _buildContent(theme),
                    ),
                  ],
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploading ? null : _uploadFile,
        icon: _uploading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.upload_file),
        label: Text(_uploading ? 'در حال آپلود...' : 'آپلود فایل'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
    );
  }

  Widget _buildToolbar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          if (_currentModuleContext != null)
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _goBack,
              tooltip: 'بازگشت',
            ),
          Expanded(
            child: Text(
              _getBreadcrumbText(),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    final folders = _currentModuleContext == null ? _getFolders() : <Map<String, dynamic>>[];
    final files = _getCurrentFiles();

    if (folders.isEmpty && files.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_outlined,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'هیچ فایلی یافت نشد',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'برای آپلود فایل روی دکمه + کلیک کنید',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          // نمایش پوشه‌ها
          ...folders.map((folder) => _buildFolderCard(folder, theme)),
          // نمایش فایل‌ها
          ...files.map((file) => _buildFileCard(file, theme)),
        ],
      ),
    );
  }

  Widget _buildFolderCard(Map<String, dynamic> folder, ThemeData theme) {
    final name = folder['name'] as String;
    final count = folder['count'] as int;
    final moduleContext = folder['module_context'] as String;

    return InkWell(
      onTap: () => _enterFolder(moduleContext),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 150,
        height: 150,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder,
              size: 64,
              color: Colors.amber[700],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                name,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$count فایل',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileCard(Map<String, dynamic> file, ThemeData theme) {
    final fileName = file['original_name'] as String? ?? '-';
    final fileSize = file['file_size'] as int? ?? 0;
    final mimeType = file['mime_type'] as String?;
    final fileId = file['id'] as String;
    final isImage = _isImage(mimeType);

    return InkWell(
      onTap: isImage ? () => _showImagePreview(fileId, fileName) : null,
      onLongPress: () => _showFileMenu(file, theme),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 150,
        height: 150,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                ),
                child: isImage
                    ? _buildImageThumbnail(fileId, theme)
                    : Center(
                        child: Icon(
                          _getFileIconData(mimeType),
                          size: 48,
                          color: theme.colorScheme.primary,
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  Text(
                    fileName,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatFileSize(fileSize),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageThumbnail(String fileId, ThemeData theme) {
    return FutureBuilder<List<int>>(
      future: _storageService.downloadFile(
        businessId: widget.businessId,
        fileId: fileId,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(
            child: Icon(
              Icons.broken_image,
              color: theme.colorScheme.outline,
              size: 32,
            ),
          );
        }
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(12),
          ),
          child: Image.memory(
            Uint8List.fromList(snapshot.data!),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (context, error, stackTrace) {
              return Center(
                child: Icon(
                  Icons.broken_image,
                  color: theme.colorScheme.outline,
                  size: 32,
                ),
              );
            },
          ),
        );
      },
    );
  }

  String _publicFileSharePageUrl(String token) {
    final origin = Uri.base.origin;
    return '$origin/public/storage-file/${Uri.encodeComponent(token)}';
  }

  Future<void> _showCreateShareDialog(Map<String, dynamic> file) async {
    final fileId = file['id'] as String;
    final pwdController = TextEditingController();
    var expiryDays = 30;

    final created = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('لینک اشتراک فایل'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  file['original_name'] as String? ?? '',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: pwdController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'رمز لینک (اختیاری)',
                    border: OutlineInputBorder(),
                    helperText: 'در صورت خالی بودن، هر کسی با لینک دسترسی دارد',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: ValueKey(expiryDays),
                  initialValue: expiryDays,
                  decoration: const InputDecoration(
                    labelText: 'مدت اعتبار لینک',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 7, child: Text('۷ روز')),
                    DropdownMenuItem(value: 30, child: Text('۳۰ روز')),
                    DropdownMenuItem(value: 90, child: Text('۹۰ روز')),
                    DropdownMenuItem(value: 365, child: Text('یک سال')),
                    DropdownMenuItem(value: 0, child: Text('بدون انقضا')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => expiryDays = v);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('لغو')),
            FilledButton(
              onPressed: () async {
                try {
                  final data = await _storageService.createFileShare(
                    businessId: widget.businessId,
                    fileId: fileId,
                    password: pwdController.text.trim().isEmpty ? null : pwdController.text.trim(),
                    expiresInDays: expiryDays == 0 ? null : expiryDays,
                    unlimitedExpiry: expiryDays == 0,
                  );
                  if (context.mounted) Navigator.pop(context, data);
                } catch (e) {
                  if (context.mounted) {
                    SnackBarHelper.showError(context, message: 'خطا: $e');
                  }
                }
              },
              child: const Text('ایجاد لینک'),
            ),
          ],
        ),
      ),
    );

    pwdController.dispose();

    if (!mounted || created == null) return;

    final token = created['token'] as String?;
    final publicUrl = (created['public_url'] as String?)?.trim();
    final pageUrl = token != null ? _publicFileSharePageUrl(token) : '';

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('لینک آماده است'),
        content: SelectableText(
          (publicUrl != null && publicUrl.isNotEmpty) ? publicUrl : pageUrl,
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final text = (publicUrl != null && publicUrl.isNotEmpty) ? publicUrl : pageUrl;
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                Navigator.pop(context);
                SnackBarHelper.showSuccess(context, message: 'در حافظه کپی شد');
              }
            },
            child: const Text('کپی لینک'),
          ),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('بستن')),
        ],
      ),
    );
  }

  Future<void> _showBusinessSharesSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        builder: (ctx, scrollCtrl) {
          return _BusinessSharesSheet(
            businessId: widget.businessId,
            storageService: _storageService,
            scrollController: scrollCtrl,
          );
        },
      ),
    );
  }

  void _showFileMenu(Map<String, dynamic> file, ThemeData theme) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('تغییر نام'),
              onTap: () {
                Navigator.pop(context);
                _renameFile(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('دانلود'),
              onTap: () {
                Navigator.pop(context);
                _downloadFile(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('اشتراک‌گذاری (لینک عمومی)'),
              onTap: () {
                Navigator.pop(context);
                _showCreateShareDialog(file);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('حذف', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _deleteFile(file);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BusinessSharesSheet extends StatefulWidget {
  final int businessId;
  final BusinessStorageService storageService;
  final ScrollController scrollController;

  const _BusinessSharesSheet({
    required this.businessId,
    required this.storageService,
    required this.scrollController,
  });

  @override
  State<_BusinessSharesSheet> createState() => _BusinessSharesSheetState();
}

class _BusinessSharesSheetState extends State<_BusinessSharesSheet> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.storageService.listBusinessShares(
        businessId: widget.businessId,
        page: 1,
        limit: 100,
        onlyActive: false,
      );
      final raw = data['items'];
      final items = raw is List
          ? raw.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList()
          : <Map<String, dynamic>>[];
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'لینک‌های اشتراک فایل',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'تازه‌سازی'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: FilledButton.tonal(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('لغو همه لینک‌ها'),
                    content: const Text(
                      'تمام لینک‌های اشتراک فعال این کسب‌وکار غیرفعال می‌شوند. ادامه می‌دهید؟',
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('خیر')),
                      FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('بله')),
                    ],
                  ),
                );
                if (!context.mounted) return;
                if (ok != true) return;
                try {
                  final n = await widget.storageService.revokeAllFileShares(businessId: widget.businessId);
                  if (!context.mounted) return;
                  SnackBarHelper.showSuccess(context, message: '$n لینک لغو شد');
                  _load();
                } catch (e) {
                  if (!context.mounted) return;
                  SnackBarHelper.showError(context, message: '$e');
                }
              },
              child: const Text('لغو همه دسترسی‌های اشتراکی'),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!)))
                    : _items.isEmpty
                        ? const Center(child: Text('لینک اشتراکی ثبت نشده است'))
                        : ListView.builder(
                            controller: widget.scrollController,
                            itemCount: _items.length,
                            itemBuilder: (context, i) {
                              final row = _items[i];
                              final active = row['is_active'] == true;
                              final sid = (row['id'] as num?)?.toInt();
                              return ListTile(
                                title: Text(row['file_name'] as String? ?? '-'),
                                subtitle: Text(
                                  'شناسه لینک: $sid • ${active ? 'فعال' : 'غیرفعال'}',
                                  style: theme.textTheme.bodySmall,
                                ),
                                trailing: active && sid != null
                                    ? IconButton(
                                        icon: const Icon(Icons.link_off),
                                        tooltip: 'لغو این لینک',
                                        onPressed: () async {
                                          try {
                                            await widget.storageService.revokeFileShare(
                                              businessId: widget.businessId,
                                              shareId: sid,
                                            );
                                            if (!context.mounted) return;
                                            SnackBarHelper.showSuccess(context, message: 'لینک لغو شد');
                                            _load();
                                          } catch (e) {
                                            if (!context.mounted) return;
                                            SnackBarHelper.showError(context, message: '$e');
                                          }
                                        },
                                      )
                                    : null,
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
