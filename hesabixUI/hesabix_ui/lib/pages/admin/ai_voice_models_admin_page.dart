import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/ai_voice_models.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';

class AIVoiceModelsAdminPage extends StatefulWidget {
  const AIVoiceModelsAdminPage({super.key});

  @override
  State<AIVoiceModelsAdminPage> createState() => _AIVoiceModelsAdminPageState();
}

class _AIVoiceModelsAdminPageState extends State<AIVoiceModelsAdminPage> {
  late final AIService _aiService;
  bool _loading = true;
  String? _error;
  List<AIVoiceModelItem> _models = [];
  bool _allowCloud = false;

  @override
  void initState() {
    super.initState();
    _aiService = AIService(ApiClient());
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _aiService.listAdminVoiceModels(),
        _aiService.getAdminVoicePolicy(),
      ]);
      if (!mounted) return;
      setState(() {
        _models = results[0] as List<AIVoiceModelItem>;
        final policy = results[1] as Map<String, dynamic>;
        _allowCloud = policy['allow_cloud_audio'] == true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.userMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _seed() async {
    try {
      final result = await _aiService.seedAdminVoiceModels();
      if (!mounted) return;
      final created = result['created'] ?? 0;
      SnackBarHelper.show(context, message: '$created مدل ایجاد شد');
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _toggleCloud(bool value) async {
    try {
      await _aiService.updateAdminVoicePolicy({'allow_cloud_audio': value});
      if (!mounted) return;
      setState(() => _allowCloud = value);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _showEditor({AIVoiceModelItem? model}) async {
    final isEdit = model != null;
    final formKey = GlobalKey<FormState>();
    final codeCtrl = TextEditingController(text: model?.code ?? '');
    final nameCtrl = TextEditingController(text: model?.displayName ?? '');
    final modelIdCtrl = TextEditingController(text: model?.modelId ?? '');
    final voiceCtrl = TextEditingController(text: model?.voiceId ?? '');
    final descCtrl = TextEditingController(text: model?.description ?? '');
    String kind = model?.kind ?? 'stt';
    String provider = model?.provider ?? 'local';
    bool isActive = model?.isActive ?? true;
    bool isDefault = model?.isDefault ?? false;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final l10n = AppLocalizations.of(context);
          return AlertDialog(
            title: Text(isEdit ? l10n.aiVoiceAdminEdit : l10n.aiVoiceAdminNew),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: codeCtrl,
                        enabled: !isEdit,
                        decoration: InputDecoration(labelText: l10n.aiVoiceAdminCode),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? l10n.aiVoiceAdminRequired : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: nameCtrl,
                        decoration: InputDecoration(labelText: l10n.aiVoiceAdminName),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? l10n.aiVoiceAdminRequired : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: kind,
                        decoration: InputDecoration(labelText: l10n.aiVoiceAdminKind),
                        items: [
                          DropdownMenuItem(value: 'stt', child: Text(l10n.aiVoiceKindStt)),
                          DropdownMenuItem(value: 'tts', child: Text(l10n.aiVoiceKindTts)),
                        ],
                        onChanged: isEdit
                            ? null
                            : (v) => setDialogState(() => kind = v!),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: provider,
                        decoration: InputDecoration(labelText: l10n.aiVoiceAdminProvider),
                        items: const [
                          DropdownMenuItem(value: 'local', child: Text('Local')),
                          DropdownMenuItem(value: 'openai', child: Text('OpenAI')),
                          DropdownMenuItem(value: 'dummy', child: Text('Dummy')),
                          DropdownMenuItem(value: 'custom', child: Text('Custom')),
                        ],
                        onChanged: (v) => setDialogState(() => provider = v!),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: modelIdCtrl,
                        decoration: InputDecoration(labelText: l10n.aiVoiceAdminModelId),
                      ),
                      const SizedBox(height: 12),
                      if (kind == 'tts')
                        TextFormField(
                          controller: voiceCtrl,
                          decoration: InputDecoration(labelText: l10n.aiVoiceAdminVoiceId),
                        ),
                      if (kind == 'tts') const SizedBox(height: 12),
                      TextFormField(
                        controller: descCtrl,
                        maxLines: 2,
                        decoration: InputDecoration(labelText: l10n.aiVoiceAdminDescription),
                      ),
                      SwitchListTile(
                        title: Text(l10n.aiVoiceAdminDefault),
                        value: isDefault,
                        onChanged: (v) => setDialogState(() => isDefault = v),
                      ),
                      SwitchListTile(
                        title: Text(l10n.aiVoiceAdminActive),
                        value: isActive,
                        onChanged: (v) => setDialogState(() => isActive = v),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.aiVoiceAdminCancel),
              ),
              FilledButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  final payload = <String, dynamic>{
                    'code': codeCtrl.text.trim(),
                    'display_name': nameCtrl.text.trim(),
                    'kind': kind,
                    'provider': provider,
                    'model_id': modelIdCtrl.text.trim(),
                    'voice_id': voiceCtrl.text.trim().isEmpty ? null : voiceCtrl.text.trim(),
                    'description': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                    'is_active': isActive,
                    'is_default': isDefault,
                    'language': 'fa',
                  };
                  try {
                    if (isEdit && model.id != null) {
                      await _aiService.updateAdminVoiceModel(model.id!, payload);
                    } else {
                      await _aiService.createAdminVoiceModel(payload);
                    }
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    _load();
                  } catch (e) {
                    if (!context.mounted) return;
                    SnackBarHelper.showError(
                      context,
                      message: ErrorExtractor.forContext(e, context),
                    );
                  }
                },
                child: Text(isEdit ? l10n.aiVoiceAdminSave : l10n.aiVoiceAdminCreate),
              ),
            ],
          );
        },
      ),
    );
    codeCtrl.dispose();
    nameCtrl.dispose();
    modelIdCtrl.dispose();
    voiceCtrl.dispose();
    descCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsAIVoiceModels),
        actions: [
          IconButton(
            tooltip: l10n.aiVoiceAdminSeed,
            icon: const Icon(Icons.auto_fix_high),
            onPressed: _seed,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showEditor(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    SwitchListTile(
                      title: Text(l10n.aiVoiceAdminAllowCloud),
                      subtitle: Text(l10n.aiVoiceAdminAllowCloudHint),
                      value: _allowCloud,
                      onChanged: _toggleCloud,
                    ),
                    const SizedBox(height: 8),
                    if (_models.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(child: Text(l10n.aiVoiceAdminEmpty)),
                      )
                    else
                      ..._models.map((m) {
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: m.isActive
                                  ? theme.colorScheme.primaryContainer
                                  : theme.colorScheme.surfaceContainerHighest,
                              child: Icon(
                                m.kind == 'tts' ? Icons.graphic_eq : Icons.mic_none,
                              ),
                            ),
                            title: Text(m.displayName),
                            subtitle: Text(
                              '${m.kind} · ${m.code} · ${m.provider} · ${m.modelId}'
                              '${m.isCloud ? ' · cloud' : ''}'
                              '${m.isDefault ? ' · default' : ''}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (m.id != null)
                                  IconButton(
                                    tooltip: l10n.aiVoiceAdminTest,
                                    icon: const Icon(Icons.science_outlined),
                                    onPressed: () async {
                                      try {
                                        await _aiService.testAdminVoiceModel(m.id!);
                                        if (!context.mounted) return;
                                        SnackBarHelper.show(
                                          context,
                                          message: l10n.aiVoiceAdminTestOk,
                                        );
                                      } catch (e) {
                                        if (!context.mounted) return;
                                        SnackBarHelper.showError(
                                          context,
                                          message: ErrorExtractor.forContext(e, context),
                                        );
                                      }
                                    },
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _showEditor(model: m),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: m.id == null
                                      ? null
                                      : () async {
                                          try {
                                            await _aiService.deleteAdminVoiceModel(m.id!);
                                            _load();
                                          } catch (e) {
                                            if (!mounted) return;
                                            SnackBarHelper.showError(
                                              context,
                                              message: ErrorExtractor.forContext(e, context),
                                            );
                                          }
                                        },
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                  ],
                ),
    );
  }
}
