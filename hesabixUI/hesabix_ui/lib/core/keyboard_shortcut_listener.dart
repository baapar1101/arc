import 'package:hesabix_ui/theme/glass.dart';
import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart' show navigatorKey;
import '../l10n/app_localizations.dart';
import '../widgets/ai/ai_quick_start.dart';
import '../widgets/ping_pong/ping_pong_dialog.dart';
import '../widgets/memorial/hesabix_developers_memorial_dialog.dart';
import '../widgets/calculator/calculator_dialog.dart';

class KeyboardShortcutListener extends StatefulWidget {
  final Widget child;

  const KeyboardShortcutListener({
    super.key,
    required this.child,
  });

  @override
  State<KeyboardShortcutListener> createState() =>
      _KeyboardShortcutListenerState();
}

class _KeyboardShortcutListenerState extends State<KeyboardShortcutListener> {
  final List<LogicalKeyboardKey> _keySequence = [];

  /// میانبر مخفی: Q سپس hesabix → پینگ‌پونگ
  static const List<LogicalKeyboardKey> _pingPongSequence = [
    LogicalKeyboardKey.keyQ,
    LogicalKeyboardKey.keyH,
    LogicalKeyboardKey.keyE,
    LogicalKeyboardKey.keyS,
    LogicalKeyboardKey.keyA,
    LogicalKeyboardKey.keyB,
    LogicalKeyboardKey.keyI,
    LogicalKeyboardKey.keyX,
  ];

  /// میانبر مخفی: Q سپس jam → گرامیداشت
  static const List<LogicalKeyboardKey> _memorialSequence = [
    LogicalKeyboardKey.keyQ,
    LogicalKeyboardKey.keyJ,
    LogicalKeyboardKey.keyA,
    LogicalKeyboardKey.keyM,
  ];

  /// بعد از Hold-Q: تایپ A سپس I
  static const List<LogicalKeyboardKey> _aiChordAfterHold = [
    LogicalKeyboardKey.keyA,
    LogicalKeyboardKey.keyI,
  ];

  static const Duration _resetDelay = Duration(seconds: 3);
  static const Duration _qHoldDuration = Duration(milliseconds: 320);
  static const Duration _aiArmedTimeout = Duration(milliseconds: 1600);

  DateTime? _lastKeyPressTime;
  late FocusNode _focusNode;
  BuildContext? _dialogContext;

  /// Hold-Q در حال شمارش است.
  Timer? _qHoldTimer;
  bool _qKeyDown = false;

  /// Hold کامل شده؛ منتظر A→I.
  bool _aiArmed = false;
  int _aiChordIndex = 0;
  Timer? _aiArmedTimer;
  OverlayEntry? _armedHintEntry;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'KeyboardShortcutListener');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        if (mounted && _focusNode.canRequestFocus) {
          _focusNode.requestFocus();
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _cancelQHold();
    _disarmAi(animated: false);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _dialogContext = context;

    return FocusScope(
      canRequestFocus: true,
      skipTraversal: false,
      child: Focus(
        focusNode: _focusNode,
        autofocus: false,
        skipTraversal: true,
        onKeyEvent: (node, event) {
          try {
            if (event is KeyDownEvent) {
              final keyboard = HardwareKeyboard.instance;
              final isCtrlOrCmd =
                  keyboard.isControlPressed || keyboard.isMetaPressed;
              final isShiftPressed = keyboard.isShiftPressed;
              final isAltPressed = keyboard.isAltPressed;

              if (event.logicalKey == LogicalKeyboardKey.keyC &&
                  isCtrlOrCmd &&
                  isShiftPressed &&
                  !isAltPressed) {
                _openCalculator();
                return KeyEventResult.handled;
              }

              final aiHandled = _handleAiHoldAndChord(event);
              if (aiHandled) return KeyEventResult.handled;

              _handleEasterEggKeyEvent(event);
            } else if (event is KeyUpEvent) {
              _handleKeyUp(event);
            }
            return KeyEventResult.ignored;
          } catch (_) {
            return KeyEventResult.ignored;
          }
        },
        child: Listener(
          onPointerDown: (_) {
            try {
              if (mounted &&
                  !_focusNode.hasFocus &&
                  _focusNode.canRequestFocus) {
                _focusNode.requestFocus();
              }
            } catch (_) {}
          },
          child: widget.child,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Hold Q → type AI
  // ---------------------------------------------------------------------------

  /// true یعنی event مصرف شده و نباید به ایستر‌اگ برود.
  bool _handleAiHoldAndChord(KeyDownEvent event) {
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed) {
      return false;
    }

    // اگر لانچر باز است، میانبر را قورت نده
    if (AiQuickStart.isBusy) {
      _disarmAi();
      return false;
    }

    // در فیلد متنی: hold و chord را نادیده بگیر
    if (AiQuickStart.isTextInputFocused()) {
      if (_aiArmed || _qHoldTimer != null) {
        _cancelQHold();
        _disarmAi();
      }
      return false;
    }

    // شروع Hold روی Q
    if (_keysMatch(key, LogicalKeyboardKey.keyQ) && !_aiArmed) {
      if (_qKeyDown) return true; // تکرار auto-repeat را نادیده بگیر
      _qKeyDown = true;
      _keySequence.clear(); // hold نباید وارد بافر ایستر‌اگ شود
      _cancelQHold();
      _qHoldTimer = Timer(_qHoldDuration, _onQHoldComplete);
      return true; // Q را برای ایستر‌اگ نگه می‌داریم تا KeyUp
    }

    // کلید دیگر هنگام شمارش Hold → لغو Hold (نه arm)
    if (_qHoldTimer != null && _qHoldTimer!.isActive) {
      _cancelQHold();
      _qKeyDown = false;
      return false;
    }

    // حالت مسلح: فقط A سپس I
    if (_aiArmed) {
      final expected = _aiChordAfterHold[_aiChordIndex];
      if (_keysMatch(key, expected)) {
        _aiChordIndex++;
        _bumpAiArmedTimeout();
        HapticFeedback.selectionClick();
        _refreshArmedHint();
        if (_aiChordIndex >= _aiChordAfterHold.length) {
          _disarmAi();
          _openAiQuickStart();
        }
        return true;
      }
      // کلید اشتباه → لغو حالت AI
      _disarmAi();
      return false;
    }

    return false;
  }

  void _handleKeyUp(KeyUpEvent event) {
    if (!_keysMatch(event.logicalKey, LogicalKeyboardKey.keyQ)) return;

    final wasDown = _qKeyDown;
    _qKeyDown = false;

    if (!wasDown) return;

    // Hold هنوز کامل نشده → tap کوتاه = شروع ایستر‌اگ با Q
    if (_qHoldTimer != null && _qHoldTimer!.isActive) {
      _cancelQHold();
      if (!AiQuickStart.isTextInputFocused()) {
        _keySequence
          ..clear()
          ..add(LogicalKeyboardKey.keyQ);
        _lastKeyPressTime = DateTime.now();
      }
      return;
    }

    // Hold کامل شده بود؛ رها کردن Q حالت مسلح را نگه می‌دارد تا timeout
  }

  void _onQHoldComplete() {
    _qHoldTimer = null;
    if (!mounted || !_qKeyDown) return;
    if (AiQuickStart.isTextInputFocused() || AiQuickStart.isBusy) return;

    _armAi();
  }

  void _armAi() {
    _aiArmed = true;
    _aiChordIndex = 0;
    _keySequence.clear();
    HapticFeedback.mediumImpact();
    _bumpAiArmedTimeout();
    _showArmedHint();
  }

  void _bumpAiArmedTimeout() {
    _aiArmedTimer?.cancel();
    _aiArmedTimer = Timer(_aiArmedTimeout, () {
      if (mounted) _disarmAi();
    });
  }

  void _cancelQHold() {
    _qHoldTimer?.cancel();
    _qHoldTimer = null;
  }

  void _disarmAi({bool animated = true}) {
    _aiArmed = false;
    _aiChordIndex = 0;
    _aiArmedTimer?.cancel();
    _aiArmedTimer = null;
    _removeArmedHint(animated: animated);
  }

  void _openAiQuickStart() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = navigatorKey.currentContext ?? _dialogContext ?? context;
      if (!ctx.mounted) return;
      unawaited(AiQuickStart.open(ctx));
    });
  }

  // ---------------------------------------------------------------------------
  // Armed hint overlay (pill)
  // ---------------------------------------------------------------------------

  void _showArmedHint() {
    _removeArmedHint(animated: false);
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) return;

    _armedHintEntry = OverlayEntry(
      builder: (context) => _AiArmedHint(
        progress: _aiChordIndex,
        total: _aiChordAfterHold.length,
      ),
    );
    overlay.insert(_armedHintEntry!);
  }

  void _refreshArmedHint() {
    _armedHintEntry?.markNeedsBuild();
  }

  void _removeArmedHint({bool animated = true}) {
    final entry = _armedHintEntry;
    _armedHintEntry = null;
    if (entry == null) return;
    try {
      entry.remove();
      entry.dispose();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Easter eggs (Q → hesabix / jam)
  // ---------------------------------------------------------------------------

  void _handleEasterEggKeyEvent(KeyDownEvent event) {
    try {
      final now = DateTime.now();
      final logicalKey = event.logicalKey;

      if (_lastKeyPressTime != null &&
          now.difference(_lastKeyPressTime!) > _resetDelay) {
        _keySequence.clear();
      }

      _lastKeyPressTime = now;

      final len = _keySequence.length;

      if (len == 0) {
        if (_keysMatch(logicalKey, LogicalKeyboardKey.keyQ)) {
          _keySequence.add(logicalKey);
        }
        return;
      }

      if (len == 1) {
        if (!_keysMatch(_keySequence[0], LogicalKeyboardKey.keyQ)) {
          _keySequence.clear();
          if (_keysMatch(logicalKey, LogicalKeyboardKey.keyQ)) {
            _keySequence.add(logicalKey);
          }
          return;
        }
        if (_keysMatch(logicalKey, LogicalKeyboardKey.keyH)) {
          _keySequence.add(logicalKey);
          return;
        }
        if (_keysMatch(logicalKey, LogicalKeyboardKey.keyJ)) {
          _keySequence.add(logicalKey);
          return;
        }
        if (_keysMatch(logicalKey, LogicalKeyboardKey.keyQ)) {
          _keySequence
            ..clear()
            ..add(logicalKey);
          return;
        }
        _keySequence.clear();
        return;
      }

      final bool isPingPong =
          _keysMatch(_keySequence[1], LogicalKeyboardKey.keyH);
      final bool isMemorial =
          _keysMatch(_keySequence[1], LogicalKeyboardKey.keyJ);
      if (!isPingPong && !isMemorial) {
        _keySequence.clear();
        if (_keysMatch(logicalKey, LogicalKeyboardKey.keyQ)) {
          _keySequence.add(logicalKey);
        }
        return;
      }

      final active = isPingPong ? _pingPongSequence : _memorialSequence;
      if (len >= active.length) {
        _keySequence.clear();
        if (_keysMatch(logicalKey, LogicalKeyboardKey.keyQ)) {
          _keySequence.add(logicalKey);
        }
        return;
      }

      final expectedKey = active[len];
      if (_keysMatch(logicalKey, expectedKey)) {
        _keySequence.add(logicalKey);
        if (_keySequence.length == active.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && context.mounted) {
              if (active == _pingPongSequence) {
                _openPingPongDialog();
              } else {
                _openMemorialDialog();
              }
            }
          });
          _keySequence.clear();
        }
      } else {
        _keySequence.clear();
        if (_keysMatch(logicalKey, LogicalKeyboardKey.keyQ)) {
          _keySequence.add(logicalKey);
        }
      }
    } catch (_) {}
  }

  bool _keysMatch(LogicalKeyboardKey key1, LogicalKeyboardKey key2) {
    return key1.keyId == key2.keyId;
  }

  void _openPingPongDialog() {
    _openShortcutDialog(
      dialog: const PingPongDialog(),
      barrierDismissible: false,
    );
  }

  void _openMemorialDialog() {
    _openShortcutDialog(
      dialog: const HesabixDevelopersMemorialDialog(),
      barrierDismissible: true,
    );
  }

  void _openShortcutDialog({
    required Widget dialog,
    required bool barrierDismissible,
  }) {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      try {
        final contextToUse = _dialogContext ?? context;
        _showDialogWithContext(
          contextToUse,
          dialog: dialog,
          barrierDismissible: barrierDismissible,
        );
      } catch (_) {}
    });
  }

  void _showDialogWithContext(
    BuildContext contextToUse, {
    required Widget dialog,
    required bool barrierDismissible,
  }) {
    try {
      final navigator = Navigator.maybeOf(contextToUse, rootNavigator: false);
      if (navigator == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final newContext = _dialogContext ?? context;
            _showDialogDirectly(
              newContext,
              dialog: dialog,
              barrierDismissible: barrierDismissible,
            );
          }
        });
        return;
      }

      _showDialogDirectly(
        contextToUse,
        dialog: dialog,
        barrierDismissible: barrierDismissible,
      );
    } catch (_) {}
  }

  void _showDialogDirectly(
    BuildContext contextToUse, {
    required Widget dialog,
    required bool barrierDismissible,
  }) {
    try {
      BuildContext? dialogContext = navigatorKey.currentContext;

      if (dialogContext == null) {
        dialogContext = contextToUse;
        final navigator = Navigator.maybeOf(dialogContext, rootNavigator: true);
        if (navigator == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              dialogContext = navigatorKey.currentContext ?? contextToUse;
              _showDialogDirectly(
                dialogContext!,
                dialog: dialog,
                barrierDismissible: barrierDismissible,
              );
            }
          });
          return;
        }
      }

      showGlassDialog<void>(
        context: dialogContext,
        barrierDismissible: barrierDismissible,
        useRootNavigator: true,
        builder: (dialogBuildContext) {
          return dialog;
        },
      ).then((_) {}).catchError((_) {});
    } catch (_) {
      try {
        final fallbackContext = navigatorKey.currentContext ?? contextToUse;
        showGeneralDialog<void>(
          context: fallbackContext,
          barrierDismissible: barrierDismissible,
          barrierLabel: '',
          barrierColor: Colors.black54,
          transitionDuration: const Duration(milliseconds: 200),
          pageBuilder: (context, animation, secondaryAnimation) {
            return dialog;
          },
          transitionBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
        );
      } catch (_) {}
    }
  }

  void _openCalculator() {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final contextToUse = _dialogContext ?? context;
        final dialogContext = navigatorKey.currentContext ?? contextToUse;
        CalculatorDialog.show(dialogContext);
      } catch (_) {}
    });
  }
}

/// پیل شناور پایین صفحه وقتی Hold-Q فعال شده و منتظر تایپ AI است.
class _AiArmedHint extends StatefulWidget {
  final int progress;
  final int total;

  const _AiArmedHint({
    required this.progress,
    required this.total,
  });

  @override
  State<_AiArmedHint> createState() => _AiArmedHintState();
}

class _AiArmedHintState extends State<_AiArmedHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final label = l10n.aiQuickLauncherArmedHint;

    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );

    return Positioned(
      left: 0,
      right: 0,
      bottom: bottom + 28,
      child: IgnorePointer(
        ignoring: true,
        child: FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.35),
              end: Offset.zero,
            ).animate(curved),
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: scheme.primary.withValues(
                          alpha: isDark ? 0.45 : 0.35,
                        ),
                      ),
                      gradient: LinearGradient(
                        colors: [
                          scheme.primary.withValues(
                            alpha: isDark ? 0.28 : 0.16,
                          ),
                          scheme.tertiary.withValues(
                            alpha: isDark ? 0.20 : 0.12,
                          ),
                          (isDark
                                  ? scheme.surfaceContainerHighest
                                  : scheme.surface)
                              .withValues(alpha: 0.88),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: scheme.primary.withValues(alpha: 0.22),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            size: 18,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            label,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(width: 12),
                          _ChordDots(
                            progress: widget.progress,
                            total: widget.total,
                            color: scheme.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChordDots extends StatelessWidget {
  final int progress;
  final int total;
  final Color color;

  const _ChordDots({
    required this.progress,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(total, (i) {
        final filled = i < progress;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          margin: EdgeInsets.only(left: i == 0 ? 0 : 5),
          width: filled ? 8 : 7,
          height: filled ? 8 : 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? color : color.withValues(alpha: 0.28),
            boxShadow: filled
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.45),
                      blurRadius: 6,
                    ),
                  ]
                : null,
          ),
        );
      }),
    );
  }
}
