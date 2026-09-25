import 'package:flutter/material.dart';

import '../../../utils/responsive_helper.dart';

class NewBusinessFormShell extends StatelessWidget {
  final Widget child;
  final double? maxWidth;

  const NewBusinessFormShell({super.key, required this.child, this.maxWidth});

  @override
  Widget build(BuildContext context) {
    final padding = ResponsiveHelper.getPadding(context);
    final width =
        maxWidth ??
        (ResponsiveHelper.isDesktop(context)
            ? 640.0
            : ResponsiveHelper.getCardMaxWidth(context));

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            padding * 1.5,
            padding,
            padding * 1.5,
            padding * 2,
          ),
          child: child,
        ),
      ),
    );
  }
}

class NewBusinessSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const NewBusinessSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  height: 1.2,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }
}

class NewBusinessSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const NewBusinessSurface({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final radius = ResponsiveHelper.responsiveValue(
      context,
      mobile: 16,
      tablet: 18,
      desktop: 20,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding:
            padding ??
            EdgeInsets.all(
              ResponsiveHelper.responsiveValue(
                context,
                mobile: 16,
                tablet: 18,
                desktop: 20,
              ),
            ),
        child: child,
      ),
    );
  }
}

InputDecoration newBusinessInputDecoration(
  BuildContext context, {
  required String labelText,
  String? hintText,
  String? helperText,
  String? errorText,
  Widget? prefixIcon,
  bool required = false,
}) {
  final cs = Theme.of(context).colorScheme;
  final label = required ? '$labelText *' : labelText;
  return InputDecoration(
    labelText: label,
    hintText: hintText,
    helperText: helperText,
    errorText: errorText,
    prefixIcon: prefixIcon,
    filled: true,
    fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.35),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.35)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.35)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: cs.primary, width: 1.6),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: cs.error),
    ),
  );
}

class NewBusinessChoiceCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool selected;
  final bool compact;
  final Color? accent;

  const NewBusinessChoiceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.selected = false,
    this.compact = false,
    this.accent,
  });

  @override
  State<NewBusinessChoiceCard> createState() => _NewBusinessChoiceCardState();
}

class _NewBusinessChoiceCardState extends State<NewBusinessChoiceCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = widget.accent ?? cs.primary;
    final selected = widget.selected;
    final highlight = selected || _hovered;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(
          0,
          highlight && !selected ? -2 : 0,
          0,
        ),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.10) : cs.surface,
          borderRadius: BorderRadius.circular(widget.compact ? 14 : 18),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.85)
                : cs.outlineVariant.withValues(alpha: highlight ? 0.9 : 0.55),
            width: selected ? 1.6 : 1,
          ),
          boxShadow: highlight
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: selected ? 0.14 : 0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(widget.compact ? 14 : 18),
            child: Padding(
              padding: EdgeInsets.all(widget.compact ? 14 : 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: widget.compact ? 42 : 48,
                    height: widget.compact ? 42 : 48,
                    decoration: BoxDecoration(
                      color: selected
                          ? accent.withValues(alpha: 0.18)
                          : cs.surfaceContainerHighest.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      widget.icon,
                      color: selected ? accent : cs.onSurfaceVariant,
                      size: widget.compact ? 22 : 24,
                    ),
                  ),
                  SizedBox(width: widget.compact ? 12 : 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.arrow_forward_ios_rounded,
                    size: selected ? 22 : 16,
                    color: selected
                        ? accent
                        : cs.onSurfaceVariant.withValues(alpha: 0.55),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NewBusinessSelectTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const NewBusinessSelectTile({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: selected ? cs.primary.withValues(alpha: 0.12) : cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected
              ? cs.primary
              : cs.outlineVariant.withValues(alpha: 0.65),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: selected ? cs.primary : cs.onSurfaceVariant,
                  size: 26,
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? cs.primary : cs.onSurface,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NewBusinessFieldChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const NewBusinessFieldChip({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FilterChip(
      selected: selected,
      showCheckmark: false,
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onSelected: (_) => onTap(),
      selectedColor: cs.primary.withValues(alpha: 0.16),
      side: BorderSide(
        color: selected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.7),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    );
  }
}
