import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../theme/theme_controller.dart';
import '../theme/tokens/theme_catalog.dart';

/// انتخابگر پالت رنگی سراسری.
class ThemePaletteSwitcher extends StatelessWidget {
  final ThemeController controller;
  final bool toolbarCompact;

  const ThemePaletteSwitcher({
    super.key,
    required this.controller,
    this.toolbarCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final current = controller.themeDefinition;

    return PopupMenuButton<String>(
      tooltip: t.colorTheme,
      onSelected: controller.setThemeId,
      itemBuilder: (context) => [
        for (final theme in kAppThemeCatalog)
          PopupMenuItem<String>(
            value: theme.id,
            child: Row(
              children: [
                _ThemeSwatch(primary: theme.primary, secondary: theme.secondary, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(theme.labelFor(locale))),
                if (theme.id == current.id)
                  Icon(Icons.check, size: 16, color: Theme.of(context).colorScheme.primary),
              ],
            ),
          ),
      ],
      child: CircleAvatar(
        radius: toolbarCompact ? 12 : 14,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: _ThemeSwatch(
          primary: current.primary,
          secondary: current.secondary,
          size: toolbarCompact ? 12 : 14,
        ),
      ),
    );
  }
}

/// کارت‌های انتخاب تم برای صفحه تنظیمات ظاهر.
class ThemePalettePicker extends StatelessWidget {
  final ThemeController controller;

  const ThemePalettePicker({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final selectedId = controller.themeId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.colorTheme, style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          t.colorThemeDescription,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final def in kAppThemeCatalog)
              _ThemeChoiceCard(
                definition: def,
                label: def.labelFor(locale),
                selected: def.id == selectedId,
                onTap: () => controller.setThemeId(def.id),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(t.themeModeLabel, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<ThemeMode>(
          segments: [
            ButtonSegment(value: ThemeMode.system, label: Text(t.system), icon: const Icon(Icons.brightness_auto, size: 16)),
            ButtonSegment(value: ThemeMode.light, label: Text(t.light), icon: const Icon(Icons.light_mode, size: 16)),
            ButtonSegment(value: ThemeMode.dark, label: Text(t.dark), icon: const Icon(Icons.dark_mode, size: 16)),
          ],
          selected: {controller.mode},
          onSelectionChanged: (set) {
            if (set.isNotEmpty) controller.setMode(set.first);
          },
        ),
      ],
    );
  }
}

class _ThemeChoiceCard extends StatelessWidget {
  final AppThemeDefinition definition;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeChoiceCard({
    required this.definition,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 168,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _ThemeSwatch(primary: definition.primary, secondary: definition.secondary, size: 28),
                  const Spacer(),
                  if (selected) Icon(Icons.check_circle, size: 18, color: theme.colorScheme.primary),
                ],
              ),
              const SizedBox(height: 10),
              Text(label, style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Row(
                children: [
                  _Dot(definition.primary),
                  _Dot(definition.secondary),
                  _Dot(definition.positive),
                  _Dot(definition.warning),
                  _Dot(definition.negative),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  final Color primary;
  final Color secondary;
  final double size;

  const _ThemeSwatch({
    required this.primary,
    required this.secondary,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(colors: [primary, secondary, primary]),
        border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 1),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot(this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      margin: const EdgeInsetsDirectional.only(end: 4),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
    );
  }
}
