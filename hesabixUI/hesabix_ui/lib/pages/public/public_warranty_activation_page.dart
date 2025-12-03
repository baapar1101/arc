import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../services/warranty_service.dart';
import '../../models/warranty_models.dart';
import '../../core/api_client.dart';
import '../../utils/snackbar_helper.dart';

class PublicWarrantyActivationPage extends StatefulWidget {
  final int businessId;

  const PublicWarrantyActivationPage({
    super.key,
    required this.businessId,
  });

  @override
  State<PublicWarrantyActivationPage> createState() => _PublicWarrantyActivationPageState();
}

class _PublicWarrantyActivationPageState extends State<PublicWarrantyActivationPage> {
  final WarrantyService _warrantyService = WarrantyService();
  final ApiClient _apiClient = ApiClient();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _loadingBusinessInfo = true;
  bool _success = false;
  String? _trackingLinkCode;
  Map<String, dynamic>? _businessInfo;

  final _warrantyCodeController = TextEditingController();
  final _warrantySerialController = TextEditingController();
  final _productSerialController = TextEditingController();
  final _customerNameController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _customerEmailController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadBusinessInfo();
  }

  @override
  void dispose() {
    _warrantyCodeController.dispose();
    _warrantySerialController.dispose();
    _productSerialController.dispose();
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _customerEmailController.dispose();
    super.dispose();
  }

  Future<void> _loadBusinessInfo() async {
    setState(() => _loadingBusinessInfo = true);
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/warranty/public/business/${widget.businessId}/info',
      );
      if (mounted) {
        setState(() {
          _businessInfo = response.data?['data'];
          _loadingBusinessInfo = false;
        });
      }
    } on DioException catch (e) {
      if (mounted) {
        // اگر کسب و کار یافت نشد (404)، به صفحه 404 هدایت شود
        if (e.response?.statusCode == 404) {
          context.go('/404');
          return;
        }
        setState(() => _loadingBusinessInfo = false);
        SnackBarHelper.showError(context, message: 'خطا در بارگذاری اطلاعات کسب و کار');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingBusinessInfo = false);
        SnackBarHelper.showError(context, message: 'خطا در بارگذاری اطلاعات کسب و کار');
      }
    }
  }

  Future<void> _activateWarranty() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final result = await _warrantyService.activateWarranty(
        widget.businessId,
        _warrantyCodeController.text.trim(),
        _warrantySerialController.text.trim(),
        _customerNameController.text.trim(),
        _customerPhoneController.text.trim(),
        customerEmail: _customerEmailController.text.trim().isEmpty
            ? null
            : _customerEmailController.text.trim(),
        productSerial: _productSerialController.text.trim().isEmpty
            ? null
            : _productSerialController.text.trim(),
      );

      if (mounted) {
        setState(() {
          _success = true;
          _loading = false;
          _trackingLinkCode = result.trackingLinkCode;
        });
        SnackBarHelper.showSuccess(context, message: 'گارانتی با موفقیت فعال شد');
      }
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      if (mounted) {
        setState(() => _loading = false);
        SnackBarHelper.showError(context, message: message);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        SnackBarHelper.showError(context, message: 'خطا در فعال‌سازی گارانتی: $e');
      }
    }
  }

  String _extractErrorMessage(DioException e) {
    if (e.response?.data is Map) {
      final data = e.response!.data as Map;
      if (data.containsKey('message')) {
        return data['message'].toString();
      }
      if (data.containsKey('detail')) {
        return data['detail'].toString();
      }
    }
    return e.message ?? 'خطای نامشخص';
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_loadingBusinessInfo) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(t.warrantyActivation),
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_businessInfo != null) _buildBusinessHeader(context, theme, colorScheme),
                  const SizedBox(height: 24),
                  _success
                      ? _buildSuccessView(context, theme, colorScheme)
                      : _buildForm(context, theme, colorScheme, t),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBusinessHeader(BuildContext context, ThemeData theme, ColorScheme colorScheme) {
    final businessName = _businessInfo?['name'] ?? 'کسب و کار';
    final logoUrl = _businessInfo?['logo_url'];
    final description = _businessInfo?['description'];

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            if (logoUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  logoUrl,
                  height: 80,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.business,
                    size: 60,
                    color: colorScheme.primary,
                  ),
                ),
              )
            else
              Icon(
                Icons.business,
                size: 60,
                color: colorScheme.primary,
              ),
            const SizedBox(height: 12),
            Text(
              businessName,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            if (description != null) ...[
              const SizedBox(height: 8),
              Text(
                description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessView(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.check_circle,
          size: 80,
          color: Colors.green,
        ),
        const SizedBox(height: 24),
        Text(
          'گارانتی با موفقیت فعال شد',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'کد گارانتی شما: ${_warrantyCodeController.text}',
          style: theme.textTheme.bodyLarge,
        ),
        if (_trackingLinkCode != null) ...[
          const SizedBox(height: 16),
          Text(
            'کد رهگیری: $_trackingLinkCode',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'می‌توانید با استفاده از این کد، وضعیت گارانتی خود را رهگیری کنید',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: () {
            setState(() {
              _success = false;
              _trackingLinkCode = null;
              _warrantyCodeController.clear();
              _warrantySerialController.clear();
              _productSerialController.clear();
              _customerNameController.clear();
              _customerPhoneController.clear();
              _customerEmailController.clear();
            });
          },
          child: const Text('فعال‌سازی گارانتی دیگر'),
        ),
      ],
    );
  }

  Widget _buildForm(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    AppLocalizations t,
  ) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.verified_user, color: colorScheme.primary),
                      const SizedBox(width: 12),
                      Text(
                        t.warrantyActivation,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'لطفاً اطلاعات گارانتی خود را وارد کنید',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _warrantyCodeController,
                    decoration: InputDecoration(
                      labelText: t.warrantyCode,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.qr_code),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'کد گارانتی الزامی است';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _warrantySerialController,
                    decoration: InputDecoration(
                      labelText: t.warrantySerial,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.tag),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'سریال گارانتی الزامی است';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _productSerialController,
                    decoration: InputDecoration(
                      labelText: t.warrantyProductSerial,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.inventory),
                      helperText: 'در صورت وجود سریال کالا، وارد کنید',
                    ),
                  ),
                  const SizedBox(height: 24),
                  Divider(),
                  const SizedBox(height: 16),
                  Text(
                    'اطلاعات مشتری',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _customerNameController,
                    decoration: InputDecoration(
                      labelText: t.warrantyCustomerName,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.person),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'نام مشتری الزامی است';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _customerPhoneController,
                    decoration: InputDecoration(
                      labelText: t.warrantyCustomerPhone,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.phone),
                    ),
                    keyboardType: TextInputType.phone,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'شماره تماس الزامی است';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _customerEmailController,
                    decoration: InputDecoration(
                      labelText: t.warrantyCustomerEmail,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.email),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _activateWarranty,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(t.activateWarranty),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
