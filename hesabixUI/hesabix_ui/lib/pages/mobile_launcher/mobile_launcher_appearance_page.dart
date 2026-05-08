import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/auth_store.dart';
import '../../core/mobile_launcher_prefs.dart';
import '../../utils/snackbar_helper.dart';

/// پیش‌تنظیم‌های رنگ پس‌زمینهٔ لانچر (بدون وابستگی به پکیج خارجی).
class MobileLauncherAppearancePage extends StatefulWidget {
  const MobileLauncherAppearancePage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  final int businessId;
  final AuthStore authStore;

  static const List<int> presetArgb = [
    0xFF1565C0,
    0xFF283593,
    0xFF00695C,
    0xFF2E7D32,
    0xFF6A1B9A,
    0xFF4527A0,
    0xFFC62828,
    0xFF37474F,
    0xFF263238,
    0xFFFFFFFF,
    0xFFECEFF1,
    0xFFFF6F00,
  ];

  @override
  State<MobileLauncherAppearancePage> createState() => _MobileLauncherAppearancePageState();
}

class _MobileLauncherAppearancePageState extends State<MobileLauncherAppearancePage> {
  late Future<int> _initialArgb;
  int _selectedArgb = MobileLauncherPrefs.defaultBackgroundArgb;
  int _selectedColumns = MobileLauncherPrefs.defaultGridColumns;
  int _selectedRows = MobileLauncherPrefs.defaultGridRows;
  static const List<(int, int)> _quickLayouts = [
    (2, 3),
    (3, 4),
    (4, 3),
    (4, 4),
  ];

  @override
  void initState() {
    super.initState();
    _initialArgb = MobileLauncherPrefs.backgroundColorArgb(
      widget.authStore.currentUserId,
    );
    _initialArgb.then((v) {
      if (mounted) setState(() => _selectedArgb = v);
    });
    MobileLauncherPrefs.gridColumns(widget.authStore.currentUserId).then((v) {
      if (mounted) setState(() => _selectedColumns = v);
    });
    MobileLauncherPrefs.gridRows(widget.authStore.currentUserId).then((v) {
      if (mounted) setState(() => _selectedRows = v);
    });
  }

  Future<void> _save() async {
    await MobileLauncherPrefs.setBackgroundColorArgb(
      widget.authStore.currentUserId,
      _selectedArgb,
    );
    await MobileLauncherPrefs.setGridLayout(
      widget.authStore.currentUserId,
      columns: _selectedColumns,
      rows: _selectedRows,
    );
    if (!mounted) return;
    SnackBarHelper.show(context, message: AppLocalizations.of(context).mobileLauncherColorsSaved);
    context.pop();
  }

  static bool _isLight(Color c) => c.computeLuminance() > 0.55;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.mobileLauncherAppearancePageTitle),
      ),
      body: FutureBuilder<int>(
        future: _initialArgb,
        builder: (context, snap) {
          if (!snap.hasData && snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                t.mobileLauncherBackgroundColorSection,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final argb in MobileLauncherAppearancePage.presetArgb)
                    _ColorDot(
                      argb: argb,
                      selected: _selectedArgb == argb,
                      onTap: () => setState(() => _selectedArgb = argb),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                t.mobileLauncherGridLayoutSection,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final layout in _quickLayouts)
                    ChoiceChip(
                      label: Text('${layout.$1}×${layout.$2}'),
                      selected: _selectedColumns == layout.$1 && _selectedRows == layout.$2,
                      onSelected: (_) {
                        setState(() {
                          _selectedColumns = layout.$1;
                          _selectedRows = layout.$2;
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _CountPicker(
                title: t.mobileLauncherGridColumns,
                value: _selectedColumns,
                min: 2,
                max: 6,
                onChanged: (v) => setState(() => _selectedColumns = v),
              ),
              const SizedBox(height: 8),
              _CountPicker(
                title: t.mobileLauncherGridRows,
                value: _selectedRows,
                min: 2,
                max: 6,
                onChanged: (v) => setState(() => _selectedRows = v),
              ),
              const SizedBox(height: 8),
              Text(
                '${t.mobileLauncherGridPreview}: $_selectedColumns × $_selectedRows',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(t.mobileLauncherSaveColors),
              ),
              const SizedBox(height: 8),
              Container(
                height: 120,
                decoration: BoxDecoration(
                  color: Color(_selectedArgb),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.touch_app_outlined,
                  size: 48,
                  color: _isLight(Color(_selectedArgb))
                      ? Colors.black87
                      : Colors.white,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CountPicker extends StatelessWidget {
  const _CountPicker({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String title;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
        IconButton(
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Text(
          '$value',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        IconButton(
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.argb,
    required this.selected,
    required this.onTap,
  });

  final int argb;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color(argb),
            border: Border.all(
              width: selected ? 3 : 1,
              color: selected ? Theme.of(context).colorScheme.primary : outline,
            ),
          ),
        ),
      ),
    );
  }
}
