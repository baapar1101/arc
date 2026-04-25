import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/services/crm_chat_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/permission/permission_widgets.dart';

/// تنظیمات CRM سطح کسب‌وکار (مثلاً ارسال فایل در چت وب).
class BusinessCrmSettingsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final ApiClient apiClient;

  const BusinessCrmSettingsPage({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.apiClient,
  });

  @override
  State<BusinessCrmSettingsPage> createState() => _BusinessCrmSettingsPageState();
}

class _BusinessCrmSettingsPageState extends State<BusinessCrmSettingsPage> {
  late final CrmChatService _svc;
  bool _loading = true;
  bool _allowFiles = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _svc = CrmChatService(apiClient: widget.apiClient);
    _load();
  }

  Future<void> _load() async {
    if (!widget.authStore.canReadSection('crm')) return;
    setState(() => _loading = true);
    try {
      final d = await _svc.getCrmSettings(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _allowFiles = d['allow_web_chat_file_upload'] == true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.show(
        context,
        message: 'خطا: ${ErrorExtractor.forContext(e, context)}',
        isError: true,
      );
    }
  }

  Future<void> _save(bool v) async {
    if (!widget.authStore.canWriteSection('crm')) {
      SnackBarHelper.show(context, message: 'مجوز نوشتن CRM ندارید', isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await _svc.updateCrmSettings(businessId: widget.businessId, allowWebChatFileUpload: v);
      if (!mounted) return;
      setState(() {
        _allowFiles = v;
        _saving = false;
      });
      SnackBarHelper.show(context, message: 'ذخیره شد');
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        SnackBarHelper.show(
        context,
        message: 'خطا: ${ErrorExtractor.forContext(e, context)}',
        isError: true,
      );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.authStore.canReadSection('crm')) {
      return const AccessDeniedPage(message: 'شما دسترسی لازم برای مشاهده CRM را ندارید');
    }

    final canWrite = widget.authStore.canWriteSection('crm');

    return Scaffold(
      appBar: AppBar(
        title: const Text('تنظیمات CRM'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/business/${widget.businessId}/settings'),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: SwitchListTile(
                    title: const Text('ارسال فایل در چت وب'),
                    subtitle: const Text(
                      'اگر فعال باشد، بازدیدکنندگان ویجت چت روی سایت شما می‌توانند فایل بفرستند. '
                      'نیاز به پلن فضای ذخیره‌سازی فعال و ظرفیت کافی دارد؛ در غیر این صورت برای بازدیدکننده خطا نمایش داده می‌شود و به مالک کسب‌وکار اطلاع داده می‌شود.',
                    ),
                    value: _allowFiles,
                    onChanged: (!canWrite || _saving)
                        ? null
                        : (v) {
                            setState(() => _allowFiles = v);
                            _save(v);
                          },
                  ),
                ),
              ],
            ),
    );
  }
}
