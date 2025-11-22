import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/models/ai_models.dart';

class AIPlansAdminPage extends StatefulWidget {
  const AIPlansAdminPage({super.key});

  @override
  State<AIPlansAdminPage> createState() => _AIPlansAdminPageState();
}

class _AIPlansAdminPageState extends State<AIPlansAdminPage> {
  late final AIService _aiService;
  bool _loading = true;
  String? _error;
  List<AIPlan> _plans = [];

  @override
  void initState() {
    super.initState();
    final api = ApiClient();
    _aiService = AIService(api);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final plans = await _aiService.listAIPlans();
      setState(() {
        _plans = plans;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _showPlanFormDialog({AIPlan? plan}) async {
    final isEdit = plan != null;
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: plan?.name ?? '');
    final codeController = TextEditingController(text: plan?.code ?? '');
    final descriptionController = TextEditingController(text: plan?.description ?? '');
    final tokensLimitController = TextEditingController(text: plan?.tokensLimit?.toString() ?? '');
    final monthlyTokensLimitController = TextEditingController(
      text: plan?.monthlyTokensLimit?.toString() ?? '',
    );
    
    AIPlanType selectedPlanType = plan?.planType ?? AIPlanType.free;
    bool isActive = plan?.isActive ?? true;
    bool autoRenew = plan?.autoRenew ?? false;
    
    Map<String, dynamic> pricingConfig = Map<String, dynamic>.from(
      plan?.pricingConfig ?? {},
    );

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.9,
              constraints: const BoxConstraints(maxWidth: 800, maxHeight: 700),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        isEdit ? 'ویرایش پلن' : 'ایجاد پلن جدید',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        color: Theme.of(context).colorScheme.onPrimary,
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: nameController,
                              decoration: const InputDecoration(labelText: 'نام پلن'),
                              validator: (v) => v?.isEmpty ?? true ? 'الزامی است' : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: codeController,
                              decoration: const InputDecoration(labelText: 'کد پلن'),
                              enabled: !isEdit,
                              validator: (v) => v?.isEmpty ?? true ? 'الزامی است' : null,
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<AIPlanType>(
                              value: selectedPlanType,
                              decoration: const InputDecoration(labelText: 'نوع پلن'),
                              items: AIPlanType.values.map((type) {
                                String label;
                                switch (type) {
                                  case AIPlanType.free:
                                    label = 'رایگان';
                                    break;
                                  case AIPlanType.subscription:
                                    label = 'اشتراک';
                                    break;
                                  case AIPlanType.payAsGo:
                                    label = 'پرداخت به ازای استفاده';
                                    break;
                                  case AIPlanType.hybrid:
                                    label = 'ترکیبی';
                                    break;
                                }
                                return DropdownMenuItem(value: type, child: Text(label));
                              }).toList(),
                              onChanged: (v) => setDialogState(() => selectedPlanType = v!),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: tokensLimitController,
                              decoration: const InputDecoration(labelText: 'محدودیت توکن'),
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: monthlyTokensLimitController,
                              decoration: const InputDecoration(labelText: 'محدودیت ماهانه توکن'),
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: descriptionController,
                              decoration: const InputDecoration(labelText: 'توضیحات'),
                              maxLines: 3,
                            ),
                            const SizedBox(height: 16),
                            SwitchListTile(
                              title: const Text('فعال'),
                              value: isActive,
                              onChanged: (v) => setDialogState(() => isActive = v),
                            ),
                            SwitchListTile(
                              title: const Text('تمدید خودکار'),
                              value: autoRenew,
                              onChanged: (v) => setDialogState(() => autoRenew = v),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('لغو'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: () async {
                            if (!formKey.currentState!.validate()) return;
                            try {
                              final data = {
                                'name': nameController.text.trim(),
                                'code': codeController.text.trim(),
                                'plan_type': selectedPlanType.value,
                                'pricing_config': pricingConfig,
                                if (tokensLimitController.text.isNotEmpty)
                                  'tokens_limit': int.parse(tokensLimitController.text),
                                if (monthlyTokensLimitController.text.isNotEmpty)
                                  'monthly_tokens_limit':
                                      int.parse(monthlyTokensLimitController.text),
                                'description': descriptionController.text.trim(),
                                'is_active': isActive,
                                'auto_renew': autoRenew,
                              };
                              if (isEdit) {
                                await _aiService.updateAIPlan(plan.id!, data);
                              } else {
                                await _aiService.createAIPlan(data);
                              }
                              if (!context.mounted) return;
                              Navigator.pop(context);
                              _load();
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('خطا: $e')),
                              );
                            }
                          },
                          child: Text(isEdit ? 'ذخیره' : 'ایجاد'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('پلن‌های AI')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null && _plans.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('پلن‌های AI')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('خطا: $_error'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _load,
                child: const Text('تلاش مجدد'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('پلن‌های AI'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showPlanFormDialog(),
            tooltip: 'ایجاد پلن جدید',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _plans.isEmpty
            ? const Center(child: Text('پلنی وجود ندارد'))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _plans.length,
                itemBuilder: (context, index) {
                  final plan = _plans[index];
                  String planTypeLabel;
                  switch (plan.planType) {
                    case AIPlanType.free:
                      planTypeLabel = 'رایگان';
                      break;
                    case AIPlanType.subscription:
                      planTypeLabel = 'اشتراک';
                      break;
                    case AIPlanType.payAsGo:
                      planTypeLabel = 'پرداخت به ازای استفاده';
                      break;
                    case AIPlanType.hybrid:
                      planTypeLabel = 'ترکیبی';
                      break;
                  }
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      title: Text(plan.name),
                      subtitle: Text('$planTypeLabel • ${plan.code}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (plan.isActive)
                            const Icon(Icons.check_circle, color: Colors.green)
                          else
                            const Icon(Icons.cancel, color: Colors.grey),
                          const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(Icons.edit),
                                      onPressed: () => _showPlanFormDialog(plan: plan),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete),
                                      onPressed: () async {
                                        if (await showDialog<bool>(
                                              context: context,
                                              builder: (context) => AlertDialog(
                                                title: const Text('حذف پلن'),
                                                content: const Text('آیا از حذف این پلن اطمینان دارید؟'),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(context, false),
                                                    child: const Text('لغو'),
                                                  ),
                                                  FilledButton(
                                                    onPressed: () => Navigator.pop(context, true),
                                                    child: const Text('حذف'),
                                                  ),
                                                ],
                                              ),
                                            ) ??
                                            false) {
                                          try {
                                            if (plan.id != null) {
                                              await _aiService.deleteAIPlan(plan.id!);
                                              _load();
                                            }
                                          } catch (e) {
                                            if (mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text('خطا: $e')),
                                              );
                                            }
                                          }
                                        }
                                      },
                                    ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

