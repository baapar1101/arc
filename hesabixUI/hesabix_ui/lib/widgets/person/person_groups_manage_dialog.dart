import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../models/person_group_model.dart';
import '../../services/person_group_service.dart';
import '../../utils/error_extractor.dart';
import 'person_group_form_dialog.dart';

/// لیست و مدیریت گروه‌های اشخاص
class PersonGroupsManageDialog extends StatefulWidget {
  final int businessId;

  const PersonGroupsManageDialog({super.key, required this.businessId});

  @override
  State<PersonGroupsManageDialog> createState() => _PersonGroupsManageDialogState();
}

class _PersonGroupsManageDialogState extends State<PersonGroupsManageDialog> {
  final _service = PersonGroupService();
  List<PersonGroup> _items = [];
  bool _loading = true;
  String? _error;

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
      final list = await _service.listGroups(
        businessId: widget.businessId,
        activeOnly: false,
        rootOnly: true,
      );
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
    }
  }

  Future<void> _openForm({PersonGroup? group}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => PersonGroupFormDialog(
        businessId: widget.businessId,
        group: group,
      ),
    );
    if (ok == true) await _load();
  }

  Future<void> _confirmDelete(PersonGroup g) async {
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.delete),
        content: Text('حذف گروه «${g.name}»؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.delete)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.deleteGroup(widget.businessId, g.id);
      if (mounted) await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorExtractor.forContext(e, context))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(t.personGroupsManage, style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!))
                      : _items.isEmpty
                          ? Center(child: Text(t.noDataFound))
                          : ListView.separated(
                              padding: const EdgeInsets.all(8),
                              itemCount: _items.length,
                              separatorBuilder: (context, index) => const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final g = _items[i];
                                return ListTile(
                                  title: Text(g.name),
                                  subtitle: Text(
                                    [
                                      if (g.code != null) '${t.personCode}: ${g.code}',
                                      if (!g.isActive) 'غیرفعال',
                                    ].where((s) => s.isNotEmpty).join(' · '),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined),
                                        onPressed: () => _openForm(group: g),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () => _confirmDelete(g),
                                      ),
                                    ],
                                  ),
                                  onTap: () => _openForm(group: g),
                                );
                              },
                            ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                onPressed: () => _openForm(),
                icon: const Icon(Icons.add),
                label: const Text('گروه جدید'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
