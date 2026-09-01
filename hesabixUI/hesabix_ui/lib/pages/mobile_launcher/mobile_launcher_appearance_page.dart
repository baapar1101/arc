import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/auth_store.dart';
import '../../core/mobile_launcher_prefs.dart';
import '../../utils/snackbar_helper.dart';

/// تنظیمات ظاهر لانچر موبایل (رنگ پس‌زمینه و تراکم کاشی‌ها).
class MobileLauncherAppearancePage extends StatefulWidget {
  const MobileLauncherAppearancePage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  final int businessId;
  final AuthStore authStore;

  static const List<int> presetArgb = [
    0xFF0F4C81, // classic blue
    0xFF00A8BD, // turquoise sea
    0xFF0F766E, // emerald forest
    0xFFB45309, // warm copper
    0xFF1565C0,
    0xFF283593,
    0xFF2E7D32,
    0xFFC62828,
    0xFF37474F,
    0xFF263238,
    0xFFFFFFFF,
    0xFFECEFF1,
    0xFFFF6F00,
  ];

  @override
  State<MobileLauncherAppearancePage> createState() =>
      _MobileLauncherAppearancePageState();
}

class _MobileLauncherAppearancePageState
    extends State<MobileLauncherAppearancePage> {
  late Future<void> _loadFuture;
  int _selectedArgb = MobileLauncherPrefs.defaultBackgroundArgb;
  int _selectedColumns = MobileLauncherPrefs.defaultGridColumns;

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
  }

  Future<void> _load() async {
    final uid = widget.authStore.currentUserId;
    final bg = await MobileLauncherPrefs.backgroundColorArgb(uid);
    final cols = await MobileLauncherPrefs.gridColumns(uid);
    if (!mounted) return;
    setState(() {
      _selectedArgb = bg;
      _selectedColumns = cols.clamp(2, 3);
    });
  }

  Future<void> _save() async {
    final uid = widget.authStore.currentUserId;
    await MobileLauncherPrefs.setBackgroundColorArgb(uid, _selectedArgb);
    await MobileLauncherPrefs.setGridLayout(
      uid,
      columns: _selectedColumns,
      rows: MobileLauncherPrefs.defaultGridRows,
    );
    if (!mounted) return;
    SnackBarHelper.show(
      context,
      message: AppLocalizations.of(context).mobileLauncherColorsSaved,
    );
    context.pop();
  }

  static bool _isLight(Color c) => c.computeLuminance() > 0.55;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final bg = Color(_selectedArgb);
    final light = _isLight(bg);
    final onBg = light ? Colors.black87 : Colors.white;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.mobileLauncherAppearancePageTitle),
      ),
      body: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Text(
                t.mobileLauncherLivePreview,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 10),
              _LauncherLookPreview(
                background: bg,
                columns: _selectedColumns,
                onBg: onBg,
                light: light,
              ),
              const SizedBox(height: 28),
              Text(
                t.mobileLauncherBackgroundColorSection,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
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
              const SizedBox(height: 28),
              Text(
                t.mobileLauncherTileDensitySection,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                t.mobileLauncherTileDensityHint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<int>(
                segments: [
                  ButtonSegment(
                    value: 2,
                    label: Text(t.mobileLauncherDensityComfortable),
                    icon: const Icon(Icons.grid_view_rounded, size: 18),
                  ),
                  ButtonSegment(
                    value: 3,
                    label: Text(t.mobileLauncherDensityCompact),
                    icon: const Icon(Icons.apps_rounded, size: 18),
                  ),
                ],
                selected: {_selectedColumns},
                onSelectionChanged: (s) {
                  setState(() => _selectedColumns = s.first);
                },
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.check_rounded),
                label: Text(t.mobileLauncherSaveColors),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LauncherLookPreview extends StatelessWidget {
  const _LauncherLookPreview({
    required this.background,
    required this.columns,
    required this.onBg,
    required this.light,
  });

  final Color background;
  final int columns;
  final Color onBg;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accents = const [
      Color(0xFF00897B),
      Color(0xFF1976D2),
      Color(0xFF5E35B1),
      Color(0xFFEF6C00),
      Color(0xFF43A047),
      Color(0xFF6A1B9A),
    ];
    final tileCount = columns * 2;

    return Container(
      height: 168,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: light
                        ? Colors.white.withValues(alpha: 0.9)
                        : Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: onBg.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns.clamp(2, 3),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.05,
                ),
                itemCount: tileCount,
                itemBuilder: (context, index) {
                  final accent = accents[index % accents.length];
                  return Container(
                    decoration: BoxDecoration(
                      color: light
                          ? Colors.white.withValues(alpha: 0.92)
                          : Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Icon(
                          Icons.apps_rounded,
                          size: 14,
                          color: accent,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
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
    final isLight = Color(argb).computeLuminance() > 0.85;
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
              width: selected ? 3 : (isLight ? 1.5 : 1),
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : outline.withValues(alpha: isLight ? 0.55 : 0.35),
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.28),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: selected
              ? Icon(
                  Icons.check_rounded,
                  size: 20,
                  color: Color(argb).computeLuminance() > 0.55
                      ? Colors.black87
                      : Colors.white,
                )
              : null,
        ),
      ),
    );
  }
}
