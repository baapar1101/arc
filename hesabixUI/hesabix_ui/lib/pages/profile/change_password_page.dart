import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/api_client.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  bool _isLoading = false;
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final apiClient = ApiClient();
      final response = await apiClient.changePassword(
        currentPassword: _currentPasswordController.text,
        newPassword: _newPasswordController.text,
        confirmPassword: _confirmPasswordController.text,
      );

      if (response.statusCode == 200 && response.data?['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).changePasswordSuccess),
              backgroundColor: Colors.green,
            ),
          );
          _clearForm();
        }
      } else {
        // نمایش پیام خطای دقیق از سرور
        final errorData = response.data?['error'];
        final errorMessage = errorData?['message'] ?? 'خطا در تغییر کلمه عبور';
        _showError(errorMessage);
      }
    } catch (e) {
      if (mounted) {
        _showError(AppLocalizations.of(context).changePasswordFailed);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5), // نمایش طولانی‌تر برای خواندن
        ),
      );
    }
  }

  void _clearForm() {
    _currentPasswordController.clear();
    _newPasswordController.clear();
    _confirmPasswordController.clear();
  }

  String? _validateCurrentPassword(String? value) {
    final t = AppLocalizations.of(context);
    if (value == null || value.isEmpty) {
      return '${t.currentPassword} ${t.requiredField}';
    }
    if (value.length < 8) {
      return t.passwordMinLength;
    }
    return null;
  }

  String? _validateNewPassword(String? value) {
    final t = AppLocalizations.of(context);
    if (value == null || value.isEmpty) {
      return '${t.newPassword} ${t.requiredField}';
    }
    if (value.length < 8) {
      return t.passwordMinLength;
    }
    if (value == _currentPasswordController.text) {
      return t.samePassword;
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    final t = AppLocalizations.of(context);
    if (value == null || value.isEmpty) {
      return '${t.confirmPassword} ${t.requiredField}';
    }
    if (value != _newPasswordController.text) {
      return t.passwordsDoNotMatch;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    
    return LayoutBuilder(
      builder: (context, constraints) {
        // تعیین عرض مناسب بر اساس اندازه صفحه
        double maxWidth;
        if (constraints.maxWidth > 1200) {
          maxWidth = 600; // دسکتاپ بزرگ
        } else if (constraints.maxWidth > 800) {
          maxWidth = 500; // دسکتاپ کوچک یا تبلت
        } else {
          maxWidth = double.infinity; // موبایل
        }
        
        return Center(
          child: Container(
            width: maxWidth,
            padding: EdgeInsets.all(
              constraints.maxWidth > 800 ? 24.0 : 16.0, // padding بیشتر در دسکتاپ
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Section
                  Text(
                    t.changePassword,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t.changePasswordDescription,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Form Fields Grid
                  _buildFormGrid(context, t, constraints),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFormGrid(BuildContext context, AppLocalizations t, BoxConstraints constraints) {
    // تعیین تعداد ستون‌ها بر اساس عرض صفحه
    int columns;
    if (constraints.maxWidth > 1200) {
      columns = 2; // دسکتاپ بزرگ: 2 ستون
    } else if (constraints.maxWidth > 800) {
      columns = 1; // دسکتاپ کوچک: 1 ستون
    } else {
      columns = 1; // موبایل: 1 ستون
    }

    if (columns == 1) {
      // Layout تک ستونه
      return Column(
        children: [
          _buildPasswordField(
            context: context,
            t: t,
            controller: _currentPasswordController,
            label: t.currentPassword,
            obscureText: _obscureCurrentPassword,
            onToggleVisibility: () => setState(() => _obscureCurrentPassword = !_obscureCurrentPassword),
            validator: _validateCurrentPassword,
            isLoading: _isLoading,
            icon: Icons.lock_outline,
          ),
          const SizedBox(height: 16),
          _buildPasswordField(
            context: context,
            t: t,
            controller: _newPasswordController,
            label: t.newPassword,
            obscureText: _obscureNewPassword,
            onToggleVisibility: () => setState(() => _obscureNewPassword = !_obscureNewPassword),
            validator: _validateNewPassword,
            isLoading: _isLoading,
            icon: Icons.lock,
          ),
          const SizedBox(height: 16),
          _buildPasswordField(
            context: context,
            t: t,
            controller: _confirmPasswordController,
            label: t.confirmPassword,
            obscureText: _obscureConfirmPassword,
            onToggleVisibility: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
            validator: _validateConfirmPassword,
            isLoading: _isLoading,
            icon: Icons.lock,
          ),
          const SizedBox(height: 24),
          Center(child: _buildSubmitButton(context, t, constraints)),
        ],
      );
    } else {
      // Layout دو ستونه
      return Column(
        children: [
          Row(
            children: [
              Flexible(
                flex: 1,
                child: _buildPasswordField(
                  context: context,
                  t: t,
                  controller: _currentPasswordController,
                  label: t.currentPassword,
                  obscureText: _obscureCurrentPassword,
                  onToggleVisibility: () => setState(() => _obscureCurrentPassword = !_obscureCurrentPassword),
                  validator: _validateCurrentPassword,
                  isLoading: _isLoading,
                  icon: Icons.lock_outline,
                ),
              ),
              const SizedBox(width: 16),
              Flexible(
                flex: 1,
                child: _buildPasswordField(
                  context: context,
                  t: t,
                  controller: _newPasswordController,
                  label: t.newPassword,
                  obscureText: _obscureNewPassword,
                  onToggleVisibility: () => setState(() => _obscureNewPassword = !_obscureNewPassword),
                  validator: _validateNewPassword,
                  isLoading: _isLoading,
                  icon: Icons.lock,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildPasswordField(
            context: context,
            t: t,
            controller: _confirmPasswordController,
            label: t.confirmPassword,
            obscureText: _obscureConfirmPassword,
            onToggleVisibility: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
            validator: _validateConfirmPassword,
            isLoading: _isLoading,
            icon: Icons.lock,
          ),
          const SizedBox(height: 24),
          Center(child: _buildSubmitButton(context, t, constraints)),
        ],
      );
    }
  }

  Widget _buildPasswordField({
    required BuildContext context,
    required AppLocalizations t,
    required TextEditingController controller,
    required String label,
    required bool obscureText,
    required VoidCallback onToggleVisibility,
    required String? Function(String?) validator,
    required bool isLoading,
    required IconData icon,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: IconButton(
          icon: Icon(
            obscureText ? Icons.visibility : Icons.visibility_off,
          ),
          onPressed: onToggleVisibility,
        ),
        border: const OutlineInputBorder(),
      ),
      validator: validator,
      enabled: !isLoading,
    );
  }

  Widget _buildSubmitButton(BuildContext context, AppLocalizations t, BoxConstraints constraints) {
    return SizedBox(
      width: constraints.maxWidth > 800 ? 200 : 150, // عرض ثابت
      child: ElevatedButton(
        onPressed: _isLoading ? null : _changePassword,
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.symmetric(
            vertical: constraints.maxWidth > 800 ? 18.0 : 16.0,
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(t.changePasswordButton),
      ),
    );
  }
}


