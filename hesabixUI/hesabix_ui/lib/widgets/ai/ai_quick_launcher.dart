import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import 'ai_chat_design.dart';
import 'ai_chat_enter_to_send.dart';

/// لانچر شناور دستیار هوشمند — باز شدن از بالا با انیمیشن، شبیه دستیارهای موبایل.
class AiQuickLauncher extends StatefulWidget {
  const AiQuickLauncher({super.key});

  static bool _showing = false;

  /// آیا لانچر هم‌اکنون روی صفحه است.
  static bool get isShowing => _showing;

  /// نمایش لانچر؛ در صورت ارسال، متن prompt برمی‌گردد.
  static Future<String?> show(BuildContext context) {
    if (_showing) return Future<String?>.value(null);
    _showing = true;
    return showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 520),
      pageBuilder: (context, animation, secondaryAnimation) {
        return const AiQuickLauncher();
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        final slide = Tween<Offset>(
          begin: const Offset(0, -0.22),
          end: Offset.zero,
        ).animate(curved);
        final scale = Tween<double>(begin: 0.92, end: 1).animate(curved);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: slide,
            child: ScaleTransition(
              scale: scale,
              alignment: Alignment.topCenter,
              child: child,
            ),
          ),
        );
      },
    ).whenComplete(() {
      _showing = false;
    });
  }

  @override
  State<AiQuickLauncher> createState() => _AiQuickLauncherState();
}

class _AiQuickLauncherState extends State<AiQuickLauncher>
    with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late final AnimationController _glowController;
  late final AnimationController _iconController;
  late final AnimationController _shimmerController;
  late final AnimationController _exitController;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _iconController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _glowController.dispose();
    _iconController.dispose();
    _shimmerController.dispose();
    _exitController.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (_submitting) return;
    Navigator.of(context).pop();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    HapticFeedback.lightImpact();
    await _exitController.forward();
    if (!mounted) return;
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final topPad = MediaQuery.paddingOf(context).top;
    final canSend = _controller.text.trim().isNotEmpty && !_submitting;

    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.escape): const DismissIntent(),
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              _dismiss();
              return null;
            },
          ),
        },
        child: Material(
          type: MaterialType.transparency,
          child: AnimatedBuilder(
            animation: _exitController,
            builder: (context, child) {
              final t = Curves.easeInCubic.transform(_exitController.value);
              return Opacity(
                opacity: 1 - t * 0.35,
                child: Transform.translate(
                  offset: Offset(0, -28 * t),
                  child: Transform.scale(
                    scale: 1 - t * 0.04,
                    alignment: Alignment.topCenter,
                    child: child,
                  ),
                ),
              );
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  onTap: _dismiss,
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedBuilder(
                    animation: _glowController,
                    builder: (context, _) {
                      final t = _glowController.value;
                      return BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: 12 + t * 3,
                          sigmaY: 12 + t * 3,
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                scheme.scrim.withValues(
                                  alpha: isDark ? 0.58 : 0.40,
                                ),
                                scheme.scrim.withValues(
                                  alpha: isDark ? 0.22 : 0.12,
                                ),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.55, 1.0],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, topPad + 12, 16, 16),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: AnimatedBuilder(
                          animation: Listenable.merge([
                            _glowController,
                            _iconController,
                            _shimmerController,
                          ]),
                          builder: (context, _) {
                            final glowT = _glowController.value;
                            final iconT = Curves.easeOutBack.transform(
                              _iconController.value.clamp(0.0, 1.0),
                            );
                            final shimmerT = _shimmerController.value;
                            return AIChatEnterToSend(
                              focusNode: _focusNode,
                              onSend: _submit,
                              enabled: canSend,
                              child: _LauncherPanel(
                                theme: theme,
                                isDark: isDark,
                                glowT: glowT,
                                iconScale: iconT,
                                shimmerT: shimmerT,
                                title: l10n.aiQuickLauncherTitle,
                                subtitle: l10n.aiQuickLauncherSubtitle,
                                hint: l10n.aiQuickLauncherHint,
                                keyboardHint: l10n.aiQuickLauncherKeyboardHint,
                                sendTooltip: l10n.aiChatSendMessage,
                                controller: _controller,
                                focusNode: _focusNode,
                                canSend: canSend,
                                submitting: _submitting,
                                onChanged: (_) => setState(() {}),
                                onSubmit: _submit,
                                onSend: _submit,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
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

class _LauncherPanel extends StatelessWidget {
  final ThemeData theme;
  final bool isDark;
  final double glowT;
  final double iconScale;
  final double shimmerT;
  final String title;
  final String subtitle;
  final String hint;
  final String keyboardHint;
  final String sendTooltip;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool canSend;
  final bool submitting;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;
  final VoidCallback onSend;

  const _LauncherPanel({
    required this.theme,
    required this.isDark,
    required this.glowT,
    required this.iconScale,
    required this.shimmerT,
    required this.title,
    required this.subtitle,
    required this.hint,
    required this.keyboardHint,
    required this.sendTooltip,
    required this.controller,
    required this.focusNode,
    required this.canSend,
    required this.submitting,
    required this.onChanged,
    required this.onSubmit,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;
    final primary = scheme.primary;
    final shimmerAlign = Alignment(-1.2 + shimmerT * 2.4, -0.6);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.18 + glowT * 0.14),
            blurRadius: 40 + glowT * 18,
            spreadRadius: -4,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: scheme.tertiary.withValues(alpha: 0.08 + glowT * 0.06),
            blurRadius: 28,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: scheme.shadow.withValues(alpha: isDark ? 0.45 : 0.14),
            blurRadius: 32,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: scheme.outlineVariant.withValues(
                  alpha: isDark ? 0.35 : 0.55,
                ),
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  (isDark ? scheme.surfaceContainerHigh : scheme.surface)
                      .withValues(alpha: isDark ? 0.94 : 0.96),
                  (isDark
                          ? scheme.surfaceContainerHighest
                          : scheme.surfaceContainerLowest)
                      .withValues(alpha: isDark ? 0.90 : 0.92),
                ],
              ),
            ),
            child: Stack(
              children: [
                // Soft diagonal shimmer sweep
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: shimmerAlign,
                          end: Alignment(
                            shimmerAlign.x + 0.55,
                            shimmerAlign.y + 1.1,
                          ),
                          colors: [
                            Colors.transparent,
                            primary.withValues(alpha: isDark ? 0.07 : 0.05),
                            scheme.tertiary.withValues(
                              alpha: isDark ? 0.05 : 0.035,
                            ),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.35, 0.55, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Transform.scale(
                            scale: iconScale,
                            child: Transform.rotate(
                              angle: (1 - iconScale) * -0.35,
                              child: Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: SweepGradient(
                                    transform: GradientRotation(
                                      glowT * math.pi * 2,
                                    ),
                                    colors: [
                                      primary.withValues(alpha: 0.95),
                                      scheme.tertiary.withValues(alpha: 0.88),
                                      primary.withValues(alpha: 0.55),
                                      primary.withValues(alpha: 0.95),
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: primary.withValues(
                                        alpha: 0.30 + glowT * 0.22,
                                      ),
                                      blurRadius: 18 + glowT * 12,
                                    ),
                                  ],
                                ),
                                child: Container(
                                  margin: const EdgeInsets.all(2.5),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isDark
                                        ? scheme.surfaceContainerHighest
                                        : scheme.surface,
                                  ),
                                  child: Icon(
                                    Icons.auto_awesome_rounded,
                                    size: 22,
                                    color: primary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  subtitle,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: MaterialLocalizations.of(context)
                                .closeButtonTooltip,
                            onPressed: submitting
                                ? null
                                : () => Navigator.of(context).maybePop(),
                            icon: const Icon(Icons.close_rounded, size: 20),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      DecoratedBox(
                        decoration: AIChatDesign.composerDecoration(
                          theme,
                          focused: focusNode.hasFocus,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: controller,
                                  focusNode: focusNode,
                                  minLines: 1,
                                  maxLines: 5,
                                  textInputAction: TextInputAction.send,
                                  onChanged: onChanged,
                                  onSubmitted: (_) => onSubmit(),
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    height: 1.45,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: hint,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 2, left: 2),
                                child: AnimatedScale(
                                  scale: canSend ? 1 : 0.92,
                                  duration: const Duration(milliseconds: 180),
                                  curve: Curves.easeOut,
                                  child: AnimatedOpacity(
                                    opacity: canSend ? 1 : 0.45,
                                    duration: const Duration(milliseconds: 180),
                                    child: IconButton.filled(
                                      tooltip: sendTooltip,
                                      onPressed: canSend ? onSend : null,
                                      style: IconButton.styleFrom(
                                        backgroundColor: canSend
                                            ? primary
                                            : scheme.surfaceContainerHighest,
                                        foregroundColor: canSend
                                            ? scheme.onPrimary
                                            : scheme.onSurfaceVariant,
                                        disabledBackgroundColor:
                                            scheme.surfaceContainerHighest,
                                        disabledForegroundColor: scheme
                                            .onSurfaceVariant
                                            .withValues(alpha: 0.5),
                                      ),
                                      icon: submitting
                                          ? SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: scheme.onPrimary,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.arrow_upward_rounded,
                                              size: 20,
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        keyboardHint,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color:
                              scheme.onSurfaceVariant.withValues(alpha: 0.75),
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
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
