import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../utils/responsive_helper.dart';
import 'new_business_shared.dart';

/// Shared create / backup / legacy path chooser used by intent screen and empty hub.
class NewBusinessPathsPanel extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onCreateManually;
  final VoidCallback onImportBackup;
  final VoidCallback onImportLegacy;
  final String title;
  final String subtitle;
  final bool compactSecondary;
  final bool emphasizeCreate;

  const NewBusinessPathsPanel({
    super.key,
    required this.isLoading,
    required this.onCreateManually,
    required this.onImportBackup,
    required this.onImportLegacy,
    required this.title,
    required this.subtitle,
    this.compactSecondary = true,
    this.emphasizeCreate = true,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDesktop = ResponsiveHelper.isDesktop(context);
    final gap = ResponsiveHelper.responsiveValue(
      context,
      mobile: 28,
      tablet: 32,
      desktop: 36,
    );

    final createCard = NewBusinessChoiceCard(
      icon: Icons.add_business_rounded,
      title: t.newBusinessCreateManuallyTitle,
      subtitle: t.newBusinessCreateManuallySubtitle,
      onTap: isLoading ? null : onCreateManually,
      selected: emphasizeCreate,
      accent: cs.primary,
    );
    final backupCard = NewBusinessChoiceCard(
      icon: Icons.upload_file_rounded,
      title: t.newBusinessImportBackupTitle,
      subtitle: t.newBusinessImportBackupSubtitle,
      onTap: isLoading ? null : onImportBackup,
      compact: compactSecondary,
    );
    final legacyCard = NewBusinessChoiceCard(
      icon: Icons.cloud_sync_rounded,
      title: t.newBusinessImportLegacyTitle,
      subtitle: t.newBusinessImportLegacySubtitle,
      onTap: isLoading ? null : onImportLegacy,
      compact: compactSecondary,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NewBusinessAccentBar(),
        SizedBox(height: gap),
        Text(
          title,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: cs.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        SizedBox(height: gap),
        if (isDesktop)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 6,
                child: _StaggeredFade(delay: Duration.zero, child: createCard),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 5,
                child: Column(
                  children: [
                    _StaggeredFade(
                      delay: const Duration(milliseconds: 70),
                      child: backupCard,
                    ),
                    const SizedBox(height: 12),
                    _StaggeredFade(
                      delay: const Duration(milliseconds: 140),
                      child: legacyCard,
                    ),
                  ],
                ),
              ),
            ],
          )
        else ...[
          _StaggeredFade(delay: Duration.zero, child: createCard),
          const SizedBox(height: 14),
          _StaggeredFade(
            delay: const Duration(milliseconds: 70),
            child: NewBusinessChoiceCard(
              icon: Icons.upload_file_rounded,
              title: t.newBusinessImportBackupTitle,
              subtitle: t.newBusinessImportBackupSubtitle,
              onTap: isLoading ? null : onImportBackup,
            ),
          ),
          const SizedBox(height: 14),
          _StaggeredFade(
            delay: const Duration(milliseconds: 140),
            child: NewBusinessChoiceCard(
              icon: Icons.cloud_sync_rounded,
              title: t.newBusinessImportLegacyTitle,
              subtitle: t.newBusinessImportLegacySubtitle,
              onTap: isLoading ? null : onImportLegacy,
            ),
          ),
        ],
      ],
    );
  }
}

class NewBusinessAccentBar extends StatelessWidget {
  const NewBusinessAccentBar({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 4,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(
          colors: [
            cs.primary.withValues(alpha: 0.15),
            cs.primary,
            cs.tertiary.withValues(alpha: 0.75),
          ],
        ),
      ),
    );
  }
}

class NewBusinessAmbientBackground extends StatelessWidget {
  final Widget child;

  const NewBusinessAmbientBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      cs.surface,
                      Color.alphaBlend(
                        cs.primary.withValues(alpha: 0.08),
                        cs.surface,
                      ),
                      cs.surface,
                    ]
                  : [
                      cs.surface,
                      Color.alphaBlend(
                        cs.primary.withValues(alpha: 0.05),
                        cs.surface,
                      ),
                      Color.alphaBlend(
                        cs.tertiary.withValues(alpha: 0.04),
                        cs.surface,
                      ),
                    ],
            ),
          ),
        ),
        Positioned(
          top: -80,
          right: -40,
          child: IgnorePointer(
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.primary.withValues(alpha: isDark ? 0.08 : 0.06),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -60,
          left: -30,
          child: IgnorePointer(
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.tertiary.withValues(alpha: isDark ? 0.07 : 0.05),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _StaggeredFade extends StatefulWidget {
  final Widget child;
  final Duration delay;

  const _StaggeredFade({required this.child, required this.delay});

  @override
  State<_StaggeredFade> createState() => _StaggeredFadeState();
}

class _StaggeredFadeState extends State<_StaggeredFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    Future<void>.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}
