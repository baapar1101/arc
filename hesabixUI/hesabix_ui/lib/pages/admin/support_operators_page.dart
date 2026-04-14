import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/admin_users_service.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

class SupportOperatorsPage extends StatefulWidget {
  const SupportOperatorsPage({super.key});

  @override
  State<SupportOperatorsPage> createState() => _SupportOperatorsPageState();
}

class _SupportOperatorsPageState extends State<SupportOperatorsPage> {
  final _service = AdminUsersService(ApiClient());
  bool _isLoading = true;
  List<Map<String, dynamic>> _operators = [];

  @override
  void initState() {
    super.initState();
    _loadOperators();
  }

  Future<void> _loadOperators() async {
    setState(() => _isLoading = true);
    
    try {
      final operators = await _service.listSupportOperators();
      setState(() {
        _operators = operators;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        final t = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${t.errorLoadingSettings}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _removeOperator(int userId, String email) async {
    final t = AppLocalizations.of(context);
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف اپراتور'),
        content: Text('آیا مطمئن هستید که می‌خواهید دسترسی اپراتور را از $email لغو کنید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(t.delete),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _service.removeSupportOperator(userId);
        await _loadOperators();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('دسترسی اپراتور با موفقیت لغو شد'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${t.errorSavingSettings}: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('اپراتورهای پشتیبانی'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadOperators,
            tooltip: t.refresh,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _operators.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.support_agent_outlined,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'هیچ اپراتور پشتیبانی یافت نشد',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'برای افزودن اپراتور، از صفحه مدیریت کاربران استفاده کنید',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _operators.length,
                  itemBuilder: (context, index) {
                    final operator = _operators[index];
                    final fullName = operator['full_name'] as String?;
                    final email = operator['email'] as String;
                    final telegramId = operator['telegram_chat_id'] as String?;
                    final isActive = operator['is_active'] as bool? ?? false;
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isActive
                              ? Colors.green
                              : Colors.grey,
                          child: const Icon(
                            Icons.support_agent,
                            color: Colors.white,
                          ),
                        ),
                        title: Text(fullName ?? email),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (fullName != null) Text(email),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  telegramId != null
                                      ? Icons.telegram
                                      : Icons.telegram_outlined,
                                  size: 16,
                                  color: telegramId != null
                                      ? Colors.blue
                                      : Colors.grey,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  telegramId != null
                                      ? 'متصل به تلگرام'
                                      : 'متصل نیست',
                                  style: TextStyle(
                                    color: telegramId != null
                                        ? Colors.blue
                                        : Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            if (!isActive)
                              const Padding(
                                padding: EdgeInsets.only(top: 4),
                                child: Text(
                                  'غیرفعال',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _removeOperator(
                            operator['id'] as int,
                            email,
                          ),
                          tooltip: t.delete,
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
    );
  }
}



