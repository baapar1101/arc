import 'package:flutter/material.dart';
import 'package:hesabix_ui/config/brand_config.dart';
import 'package:hesabix_ui/core/app_init_progress.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/theme/brand_logo.dart';

/// Splash با پیشرفت determinate بر اساس مراحل واقعی init (سناریو B).
class ProgressSplashScreen extends StatefulWidget {
  final String? message;
  final bool showLogo;
  final Color? backgroundColor;
  final Color? primaryColor;

  /// ۰ تا ۱ — null یعنی مرحله نامشخص (فقط اسپینر).
  final double? progress;
  final int currentStep;
  final int totalSteps;

  const ProgressSplashScreen({
    super.key,
    this.message,
    this.showLogo = true,
    this.backgroundColor,
    this.primaryColor,
    this.progress,
    this.currentStep = 1,
    this.totalSteps = AppInitPhase.totalSteps,
  });

  @override
  State<ProgressSplashScreen> createState() => _ProgressSplashScreenState();
}

class _ProgressSplashScreenState extends State<ProgressSplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _entranceController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  double _displayedProgress = 0;

  @override
  void initState() {
    super.initState();
    _displayedProgress = widget.progress ?? 0;

    _entranceController = AnimationController(
      duration: const Duration(milliseconds: 550),
      vsync: this,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutCubic,
    );

    _scaleAnimation = Tween<double>(begin: 0.92, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Curves.easeOutCubic,
      ),
    );

    _entranceController.forward();
  }

  @override
  void didUpdateWidget(ProgressSplashScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.progress != null && oldWidget.progress != widget.progress) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  String _stepLabel(AppLocalizations t) {
    return t.loadingStepOfTotal(widget.currentStep, widget.totalSteps);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final t = AppLocalizations.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final bgColor = widget.backgroundColor ?? colorScheme.surface;
    final primary = widget.primaryColor ?? colorScheme.primary;
    final targetProgress = (widget.progress ?? 0).clamp(0.0, 1.0);
    final isDeterminate = widget.progress != null;
    final percentLabel = '${(targetProgress * 100).round()}%';

    return Scaffold(
      backgroundColor: bgColor,
      body: Semantics(
        label: widget.message ?? t.loading,
        value: isDeterminate ? percentLabel : null,
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? [bgColor, bgColor.withValues(alpha: 0.95)]
                  : [bgColor, bgColor.withValues(alpha: 0.98)],
            ),
          ),
          child: AnimatedBuilder(
            animation: _entranceController,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: Opacity(
                  opacity: _fadeAnimation.value,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      children: [
                        const Spacer(flex: 2),
                        if (widget.showLogo) ...[
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: primary.withValues(alpha: 0.18),
                                  blurRadius: 20,
                                  spreadRadius: 1,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: BrandLogo(
                                width: 100,
                                height: 100,
                                primaryOverride: primary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                        ],
                        Text(
                          BrandConfig.appTitle(t),
                          style: theme.textTheme.headlineLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          t.businessManagementPlatform,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 48),
                        _buildProgressSection(
                          theme: theme,
                          colorScheme: colorScheme,
                          primary: primary,
                          targetProgress: targetProgress,
                          isDeterminate: isDeterminate,
                          percentLabel: percentLabel,
                          stepLabel: _stepLabel(t),
                          statusMessage: widget.message ?? t.loading,
                          reduceMotion: reduceMotion,
                        ),
                        const Spacer(flex: 3),
                        Text(
                          t.version,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.55),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildProgressSection({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required Color primary,
    required double targetProgress,
    required bool isDeterminate,
    required String percentLabel,
    required String stepLabel,
    required String statusMessage,
    required bool reduceMotion,
  }) {
    if (!isDeterminate) {
      return Column(
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(primary),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            statusMessage,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }

    return TweenAnimationBuilder<double>(
      key: ValueKey(targetProgress),
      tween: Tween(begin: _displayedProgress, end: targetProgress),
      duration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      onEnd: () => _displayedProgress = targetProgress,
      builder: (context, value, child) {
        return Column(
          children: [
            SizedBox(
              width: 260,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    stepLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.85),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    percentLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: primary,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 4,
                backgroundColor: colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(primary),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              statusMessage,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );
      },
    );
  }
}
