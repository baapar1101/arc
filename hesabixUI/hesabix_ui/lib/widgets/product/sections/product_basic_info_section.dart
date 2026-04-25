import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../category/category_picker_field.dart';
import '../../../models/product_form_data.dart';
import '../../../utils/number_normalizer.dart';
import '../../../utils/product_form_validator.dart';
import '../../../controllers/product_form_controller.dart';
import '../../../config/app_config.dart';
import '../../../core/auth_store.dart';
import '../../../utils/image_cache.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../utils/responsive_helper.dart';


class ProductBasicInfoSection extends StatefulWidget {
  final int businessId;
  final ProductFormData formData;
  final ValueChanged<ProductFormData> onChanged;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> attributes;
  final ProductFormController? controller;
  final AuthStore? authStore;
  
  const ProductBasicInfoSection({
    super.key,
    required this.businessId,
    required this.formData,
    required this.onChanged,
    required this.categories,
    required this.attributes,
    this.controller,
    this.authStore,
  });

  @override
  State<ProductBasicInfoSection> createState() => _ProductBasicInfoSectionState();
}

class _ProductBasicInfoSectionState extends State<ProductBasicInfoSection> {
  final ProductImageCache _imageCache = GlobalImageCache.instance;
  late final TextEditingController _codeController;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(
      text: widget.formData.autoGenerateCode ? '' : (widget.formData.code ?? ''),
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ProductBasicInfoSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.formData.autoGenerateCode) {
      if (_codeController.text.isNotEmpty) {
        _codeController.clear();
      }
      return;
    }
    final next = widget.formData.code ?? '';
    if (next != _codeController.text) {
      _codeController.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
    }
  }

  /// دانلود تصویر با استفاده از Dio (با headerهای authentication)
  Future<Uint8List?> _loadImageWithAuth(String url) async {
    // استفاده از cache برای جلوگیری از دانلود مجدد
    final cached = _imageCache.get(url);
    if (cached != null) {
      return cached;
    }
    
    try {
      // تشخیص اینکه آیا URL کامل است یا نسبی
      final isFullUrl = url.startsWith('http://') || url.startsWith('https://');
      
      // ساخت Dio instance
      final dio = Dio(BaseOptions(
        baseUrl: isFullUrl ? '' : AppConfig.apiBaseUrl.replaceAll(RegExp(r'/+$'), ''),
        headers: {
          'Content-Type': 'application/json',
        },
      ));
      
      // اضافه کردن interceptor برای headerهای authentication
      // استفاده از ApiClient که قبلاً AuthStore را bind کرده است
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) async {
          // استفاده از ApiClient برای دریافت headerهای authentication
          // ApiClient به صورت خودکار headerها را اضافه می‌کند
          // اما برای Dio instance جدید باید دستی اضافه کنیم
          final authStore = AuthStore();
          await authStore.load();
          
          final apiKey = authStore.apiKey;
          if (apiKey != null && apiKey.isNotEmpty) {
            options.headers['Authorization'] = 'ApiKey $apiKey';
          }
          final deviceId = authStore.deviceId;
          if (deviceId.isNotEmpty) {
            options.headers['X-Device-Id'] = deviceId;
          }
          final currentBusiness = authStore.currentBusiness;
          if (currentBusiness != null) {
            options.headers['X-Business-ID'] = currentBusiness.id.toString();
          } else {
            // اضافه کردن business_id از widget
            options.headers['X-Business-ID'] = widget.businessId.toString();
          }
          // اضافه کردن business_id از URL اگر موجود باشد
          final urlToCheck = isFullUrl ? url : (options.baseUrl + url);
          if (urlToCheck.contains('/business/')) {
            final match = RegExp(r'/business/(\d+)').firstMatch(urlToCheck);
            if (match != null) {
              options.headers['X-Business-ID'] = match.group(1);
            }
          }
          handler.next(options);
        },
      ));
      
      final response = await dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
        ),
      );
      
      final imageData = Uint8List.fromList(response.data ?? []);
      if (imageData.isNotEmpty) {
        _imageCache.put(url, imageData);
      }
      return imageData;
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isMobile = ResponsiveHelper.isMobile(context);
    final isDesktop = ResponsiveHelper.isDesktop(context);
    final spacing = ResponsiveHelper.getGridSpacing(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isDesktop) ...[
          // دو ستون برای صفحه‌های بزرگ
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    _buildItemTypeSelector(context),
                    SizedBox(height: spacing),
                    _buildProductCodeBlock(context, spacing),
                    SizedBox(height: spacing),
                    
                    TextFormField(
                      initialValue: widget.formData.name,
                      decoration: InputDecoration(labelText: t.title),
                      validator: ProductFormValidator.validateName,
                      onChanged: (value) => _updateFormData(widget.formData.copyWith(name: value)),
                    ),
                    SizedBox(height: spacing),
                    _buildUnitsSection(context),
                  ],
                ),
              ),
              SizedBox(width: spacing),
              Expanded(
                child: Column(
                  children: [
                    _buildImagePicker(context),
                    SizedBox(height: spacing),
                    TextFormField(
                      initialValue: widget.formData.description,
                      decoration: InputDecoration(labelText: t.description),
                      onChanged: (value) => _updateFormData(widget.formData.copyWith(description: value.trim().isEmpty ? null : value)),
                      maxLines: 4,
                    ),
                    SizedBox(height: spacing),
                    
                    CategoryPickerField(
                      businessId: widget.businessId,
                      categoriesTree: widget.categories,
                      initialValue: widget.formData.categoryId,
                      label: t.categories,
                      authStore: widget.authStore,
                      onChanged: (value) => _updateFormData(widget.formData.copyWith(categoryId: value)),
                      onCategoriesUpdated: (updatedCategories) {
                        widget.controller?.refreshCategories();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ] else ...[
          // یک ستون برای موبایل و تبلت
          _buildItemTypeSelector(context),
          SizedBox(height: spacing),
          _buildProductCodeBlock(context, spacing),
          SizedBox(height: spacing),
          
          TextFormField(
            initialValue: widget.formData.name,
            decoration: InputDecoration(labelText: t.title),
            validator: ProductFormValidator.validateName,
            onChanged: (value) => _updateFormData(widget.formData.copyWith(name: value)),
          ),
          SizedBox(height: spacing),
          
          _buildImagePicker(context),
          SizedBox(height: spacing),
          
          TextFormField(
            initialValue: widget.formData.description,
            decoration: InputDecoration(labelText: t.description),
            onChanged: (value) => _updateFormData(widget.formData.copyWith(description: value.trim().isEmpty ? null : value)),
            maxLines: 3,
          ),
          SizedBox(height: spacing),
          
          CategoryPickerField(
            businessId: widget.businessId,
            categoriesTree: widget.categories,
            initialValue: widget.formData.categoryId,
            label: t.categories,
            authStore: widget.authStore,
            onChanged: (value) => _updateFormData(widget.formData.copyWith(categoryId: value)),
            onCategoriesUpdated: (updatedCategories) {
              widget.controller?.refreshCategories();
            },
          ),
          SizedBox(height: spacing),
          _buildUnitsSection(context),
        ],
        
        if (widget.attributes.isNotEmpty) ...[
          SizedBox(height: spacing * 2),
          Text(t.productAttributes, style: Theme.of(context).textTheme.titleSmall),
          SizedBox(height: spacing),
          Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: widget.attributes.map((attr) {
              final id = (attr['id'] as num).toInt();
              final title = (attr['title'] ?? 'ویژگی ${attr['id']}').toString();
              final selected = widget.formData.selectedAttributeIds.contains(id);
              return FilterChip(
                label: Text(title),
                selected: selected,
                onSelected: (value) {
                  final newIds = Set<int>.from(widget.formData.selectedAttributeIds);
                  if (value) {
                    newIds.add(id);
                  } else {
                    newIds.remove(id);
                  }
                  _updateFormData(widget.formData.copyWith(selectedAttributeIds: newIds));
                },
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  void _updateFormData(ProductFormData newData) {
    widget.onChanged(newData);
  }

  Widget _buildProductCodeBlock(BuildContext context, double spacing) {
    final t = AppLocalizations.of(context);
    final editing = widget.controller?.isEditingProduct == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!editing) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: widget.formData.autoGenerateCode,
            onChanged: (v) {
              if (v) {
                _updateFormData(widget.formData.copyWith(
                  autoGenerateCode: true,
                  code: null,
                ));
              } else {
                _updateFormData(widget.formData.copyWith(autoGenerateCode: false));
              }
            },
            title: const Text('تولید خودکار کد'),
            subtitle: const Text('کد کالا توسط سیستم به‌صورت یکتا تولید می‌شود'),
          ),
          SizedBox(height: spacing),
        ],
        TextFormField(
          controller: _codeController,
          enabled: !widget.formData.autoGenerateCode,
          decoration: InputDecoration(
            labelText: '${t.code} (اختیاری)',
            hintText: widget.formData.autoGenerateCode ? 'کد پس از ثبت به‌صورت خودکار تولید می‌شود' : null,
            filled: widget.formData.autoGenerateCode,
          ),
          validator: (value) {
            if (widget.formData.autoGenerateCode) return null;
            return ProductFormValidator.validateCode(value);
          },
          onChanged: (value) {
            if (widget.formData.autoGenerateCode) return;
            final trimmed = value.trim();
            _updateFormData(widget.formData.copyWith(
              code: trimmed.isEmpty ? null : trimmed,
            ));
          },
        ),
      ],
    );
  }

  Widget _buildUnitsSection(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isMobile = ResponsiveHelper.isMobile(context);
    final spacing = ResponsiveHelper.getGridSpacing(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.unitsTitle, style: Theme.of(context).textTheme.titleSmall),
        SizedBox(height: spacing),
        if (isMobile)
          Column(
            children: [
              TextFormField(
                initialValue: widget.formData.mainUnit ?? '',
                decoration: InputDecoration(labelText: t.mainUnit),
                validator: (v) => (v == null || v.trim().isEmpty) ? t.required : null,
                onChanged: (text) {
                  _updateFormData(widget.formData.copyWith(
                    mainUnit: text.trim().isEmpty ? null : text.trim(),
                  ));
                },
              ),
              SizedBox(height: spacing),
              TextFormField(
                initialValue: widget.formData.secondaryUnit ?? '',
                decoration: InputDecoration(labelText: t.secondaryUnit),
                onChanged: (text) {
                  _updateFormData(widget.formData.copyWith(
                    secondaryUnit: text.trim().isEmpty ? null : text.trim(),
                  ));
                },
              ),
              SizedBox(height: spacing),
              TextFormField(
                initialValue: widget.formData.unitConversionFactor.toString(),
                decoration: InputDecoration(labelText: t.unitConversionFactor),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  const EnglishDigitsFormatter(),
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9\.]')),
                ],
                validator: (value) {
                  final hasSecondary = widget.formData.secondaryUnit?.trim().isNotEmpty == true;
                  if (hasSecondary && (value == null || value.trim().isEmpty)) {
                    return t.required;
                  }
                  return ProductFormValidator.validateConversionFactor(value);
                },
                onChanged: (value) => _updateFormData(widget.formData.copyWith(unitConversionFactor: num.tryParse(value))),
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: widget.formData.mainUnit ?? '',
                  decoration: InputDecoration(labelText: t.mainUnit),
                  validator: (v) => (v == null || v.trim().isEmpty) ? t.required : null,
                  onChanged: (text) {
                    _updateFormData(widget.formData.copyWith(
                      mainUnit: text.trim().isEmpty ? null : text.trim(),
                    ));
                  },
                ),
              ),
              SizedBox(width: spacing),
              Expanded(
                child: TextFormField(
                  initialValue: widget.formData.secondaryUnit ?? '',
                  decoration: InputDecoration(labelText: t.secondaryUnit),
                  onChanged: (text) {
                    _updateFormData(widget.formData.copyWith(
                      secondaryUnit: text.trim().isEmpty ? null : text.trim(),
                    ));
                  },
                ),
              ),
              SizedBox(width: spacing),
              Expanded(
                child: TextFormField(
                  initialValue: widget.formData.unitConversionFactor.toString(),
                  decoration: InputDecoration(labelText: t.unitConversionFactor),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    const EnglishDigitsFormatter(),
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9\.]')),
                  ],
                  validator: (value) {
                    final hasSecondary = widget.formData.secondaryUnit?.trim().isNotEmpty == true;
                    if (hasSecondary && (value == null || value.trim().isEmpty)) {
                      return t.required;
                    }
                    return ProductFormValidator.validateConversionFactor(value);
                  },
                  onChanged: (value) => _updateFormData(widget.formData.copyWith(unitConversionFactor: num.tryParse(value))),
                ),
              ),
            ],
          ),
      ],
    );
  }


  Widget _buildItemTypeSelector(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isMobile = ResponsiveHelper.isMobile(context);
    final spacing = ResponsiveHelper.getGridSpacing(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.itemType,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: spacing),
        Row(
          children: [
            Expanded(
              child: _buildItemTypeCard(
                context: context,
                title: 'کالا',
                subtitle: t.productPhysicalDesc,
                icon: Icons.inventory_2_outlined,
                value: 'کالا',
                isSelected: widget.formData.itemType == 'کالا',
              ),
            ),
            SizedBox(width: spacing),
            Expanded(
              child: _buildItemTypeCard(
                context: context,
                title: t.services,
                subtitle: t.serviceDesc,
                icon: Icons.handyman_outlined,
                value: 'خدمت',
                isSelected: widget.formData.itemType == 'خدمت',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildItemTypeCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required String value,
    required bool isSelected,
  }) {
    return InkWell(
      onTap: () {
        // اگر نوع کالا به "خدمت" تغییر کرد، کنترل موجودی را غیرفعال کن
        final newData = widget.formData.copyWith(
          itemType: value,
          trackInventory: value == 'خدمت' ? false : widget.formData.trackInventory,
          defaultWarehouseId: value == 'خدمت' ? null : widget.formData.defaultWarehouseId,
        );
        _updateFormData(newData);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected 
                ? Theme.of(context).primaryColor 
                : Theme.of(context).dividerColor,
            width: isSelected ? 2 : 1,
          ),
          color: isSelected 
              ? Theme.of(context).primaryColor.withValues(alpha: 0.05)
              : Theme.of(context).cardColor,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: isSelected 
                  ? Theme.of(context).primaryColor 
                  : Theme.of(context).iconTheme.color,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: isSelected 
                    ? Theme.of(context).primaryColor 
                    : null,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildImagePicker(BuildContext context) {
    final hasImage = widget.controller?.hasSelectedImage == true || widget.formData.imageUrl != null;
    Uint8List? imageBytes;
    
    if (widget.controller?.hasSelectedImage == true && widget.controller?.selectedImageBytes != null) {
      imageBytes = Uint8List.fromList(widget.controller!.selectedImageBytes!);
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'عکس کالا',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          height: ResponsiveHelper.isMobile(context) ? 150 : 200,
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(8),
            color: Theme.of(context).cardColor,
          ),
          child: hasImage
              ? Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: imageBytes != null
                          ? Image.memory(
                              imageBytes,
                              width: double.infinity,
                              height: 200,
                              fit: BoxFit.cover,
                            )
                          : widget.formData.imageUrl != null
                              ? FutureBuilder<Uint8List?>(
                                  future: _loadImageWithAuth(_getImageUrl(widget.formData.imageUrl!)),
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState == ConnectionState.waiting) {
                                      return const Center(
                                        child: CircularProgressIndicator(),
                                      );
                                    }
                                    if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
                                      return const Center(
                                        child: Icon(Icons.broken_image, size: 48),
                                      );
                                    }
                                    return Image.memory(
                                      snapshot.data!,
                                      width: double.infinity,
                                      height: 200,
                                      fit: BoxFit.cover,
                                    );
                                  },
                                )
                              : const Center(
                                  child: Icon(Icons.image, size: 48),
                                ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, size: 20),
                            onPressed: () => _pickImage(context),
                            tooltip: 'تغییر عکس',
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white.withValues(alpha: 0.8),
                              padding: const EdgeInsets.all(8),
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                            onPressed: () {
                              widget.controller?.clearProductImage();
                            },
                            tooltip: 'حذف عکس',
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white.withValues(alpha: 0.8),
                              padding: const EdgeInsets.all(8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_photo_alternate,
                        size: 48,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => _pickImage(context),
                        icon: const Icon(Icons.upload_file),
                        label: const Text('انتخاب عکس'),
                      ),
                    ],
                  ),
                ),
        ),
        if (hasImage && widget.controller?.selectedImageFilename != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              widget.controller!.selectedImageFilename!,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
  
  String _getImageUrl(String imageUrl) {
    // اگر URL نسبی است، باید base URL را اضافه کنیم
    if (!imageUrl.startsWith('http://') && !imageUrl.startsWith('https://')) {
      final baseUrl = AppConfig.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
      return '$baseUrl${imageUrl.startsWith('/') ? imageUrl : '/$imageUrl'}';
    }
    return imageUrl;
  }
  
  Future<void> _pickImage(BuildContext context) async {
    if (widget.controller == null) {
      if (context.mounted) {
        SnackBarHelper.show(context, message: 'خطا: کنترلر فرم در دسترس نیست');
      }
      return;
    }
    
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
        // حذف allowedExtensions چون FileType.image خودش فیلتر می‌کند
        // و در برخی پلتفرم‌ها (مخصوصاً وب) مشکل ایجاد می‌کند
      );
      
      if (result == null || result.files.isEmpty) {
        // کاربر فایل را انتخاب نکرده یا انتخاب را لغو کرده
        return;
      }
      
      final file = result.files.first;
      
      // بررسی وجود bytes
      if (file.bytes == null || file.bytes!.isEmpty) {
        if (context.mounted) {
          SnackBarHelper.show(context, message: 'خطا: فایل انتخاب شده خالی است');
        }
        return;
      }
      
      // بررسی فرمت فایل
      final fileName = file.name.toLowerCase();
      final allowedExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'];
      final hasValidExtension = allowedExtensions.any((ext) => fileName.endsWith(ext));
      
      if (!hasValidExtension) {
        if (context.mounted) {
          SnackBarHelper.show(context, message: 'فرمت فایل معتبر نیست. لطفاً یک فایل تصویری انتخاب کنید (JPG, PNG, GIF, WebP, BMP)');
        }
        return;
      }
      
      // تنظیم عکس در controller
      widget.controller!.setProductImage(file.bytes!, file.name);
      
    } on PlatformException catch (e) {
      // خطای خاص پلتفرم (مثلاً دسترسی رد شده)
      if (context.mounted) {
        SnackBarHelper.show(context, message: 'خطا در دسترسی به فایل: ${e.message ?? "خطای نامشخص"}');
      }
    } catch (e) {
      // خطای عمومی
      if (context.mounted) {
        SnackBarHelper.showError(
          context,
          message: 'خطا در انتخاب فایل: ${ErrorExtractor.forContext(e, context)}',
        );
      }
    }
  }
}
