import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../utils/responsive_helper.dart';

class NewBusinessWizardProgress extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final List<String> stepTitles;
  final ValueChanged<int>? onStepTap;

  const NewBusinessWizardProgress({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    required this.stepTitles,
    this.onStepTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isMobile = ResponsiveHelper.isMobile(context);
    final padding = ResponsiveHelper.getPadding(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(padding * 1.5, padding, padding * 1.5, 0),
      child: Column(
        children: [
          Row(
            children: List.generate(totalSteps, (index) {
              final active = index <= currentStep;
              final current = index == currentStep;
              return Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  height: current ? 5 : 4,
                  decoration: BoxDecoration(
                    color: active
                        ? cs.primary
                        : cs.outlineVariant.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(99),
                    boxShadow: current
                        ? [
                            BoxShadow(
                              color: cs.primary.withValues(alpha: 0.28),
                              blurRadius: 6,
                            ),
                          ]
                        : null,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          Text(
            '${t.step} ${currentStep + 1} ${t.ofText} $totalSteps',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
          if (!isMobile) ...[
            const SizedBox(height: 14),
            Row(
              children: List.generate(totalSteps, (index) {
                final reached = index <= currentStep;
                final current = index == currentStep;
                final title = stepTitles[index];
                return Expanded(
                  child: InkWell(
                    onTap: onStepTap == null ? null : () => onStepTap!(index),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 4,
                      ),
                      child: Column(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: current
                                  ? cs.primary
                                  : reached
                                  ? cs.primary.withValues(alpha: 0.16)
                                  : cs.surfaceContainerHighest,
                              border: Border.all(
                                color: reached ? cs.primary : cs.outlineVariant,
                              ),
                            ),
                            child: Center(
                              child: reached && !current
                                  ? Icon(
                                      Icons.check,
                                      size: 14,
                                      color: cs.primary,
                                    )
                                  : Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: current
                                            ? cs.onPrimary
                                            : cs.onSurfaceVariant,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: current
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: current
                                  ? cs.onSurface
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${currentStep + 1}',
                        style: TextStyle(
                          color: cs.onPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      stepTitles[currentStep],
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class NewBusinessWizardNavBar extends StatelessWidget {
  final int currentStep;
  final int lastStep;
  final bool canGoNext;
  final bool isLoading;
  final bool showBackToOptions;
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final VoidCallback? onSubmit;
  final VoidCallback? onBackToOptions;

  const NewBusinessWizardNavBar({
    super.key,
    required this.currentStep,
    required this.lastStep,
    required this.canGoNext,
    required this.isLoading,
    this.showBackToOptions = false,
    this.onBack,
    this.onNext,
    this.onSubmit,
    this.onBackToOptions,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isMobile = ResponsiveHelper.isMobile(context);
    final padding = ResponsiveHelper.getPadding(context);
    final isLast = currentStep >= lastStep;

    final primary = FilledButton.icon(
      onPressed: isLoading
          ? null
          : (isLast ? onSubmit : (canGoNext ? onNext : null)),
      icon: isLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(isLast ? Icons.check_rounded : Icons.arrow_forward_rounded),
      label: Text(isLast ? t.createBusiness : t.next),
      style: FilledButton.styleFrom(
        minimumSize: Size(isMobile ? double.infinity : 148, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );

    final secondary = OutlinedButton.icon(
      onPressed: currentStep > 0
          ? onBack
          : (showBackToOptions ? onBackToOptions : null),
      icon: const Icon(Icons.arrow_back_rounded),
      label: Text(currentStep > 0 ? t.previous : t.newBusinessBackToOptions),
      style: OutlinedButton.styleFrom(
        minimumSize: Size(isMobile ? double.infinity : 148, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );

    return Material(
      elevation: 6,
      shadowColor: theme.shadowColor.withValues(alpha: 0.12),
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(padding * 1.5, 12, padding * 1.5, 12),
          child: isMobile
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    primary,
                    if (currentStep > 0 || showBackToOptions) ...[
                      const SizedBox(height: 10),
                      secondary,
                    ],
                  ],
                )
              : Row(
                  children: [
                    if (currentStep > 0 || showBackToOptions)
                      secondary
                    else
                      const SizedBox.shrink(),
                    const Spacer(),
                    primary,
                  ],
                ),
        ),
      ),
    );
  }
}
