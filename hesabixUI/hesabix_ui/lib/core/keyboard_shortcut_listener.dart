import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/ping_pong/ping_pong_dialog.dart';
import '../widgets/memorial/hesabix_developers_memorial_dialog.dart';
import '../widgets/calculator/calculator_dialog.dart';
import '../main.dart'; // برای دسترسی به navigatorKey

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
  DateTime? _lastKeyPressTime;
  static const Duration _resetDelay = Duration(seconds: 3);
  late FocusNode _focusNode;
  BuildContext? _dialogContext;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'KeyboardShortcutListener');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        if (mounted && _focusNode.canRequestFocus) {
          _focusNode.requestFocus();
        } else {
        }
      } catch (e) {
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ذخیره context که از MaterialApp builder می‌آید (این context Navigator دارد)
    _dialogContext = context;
    
    return FocusScope(
      canRequestFocus: true,
      skipTraversal: false,
      child: Focus(
        focusNode: _focusNode,
        autofocus: false, // از autofocus استفاده نکنیم
        skipTraversal: true, // در focus traversal شرکت نکن
        onKeyEvent: (node, event) {
          try {
            if (event is KeyDownEvent) {
              // بررسی کلید میانبر ماشین حساب: Ctrl+Shift+C یا Cmd+Shift+C
              final keyboard = HardwareKeyboard.instance;
              final isCtrlOrCmd = keyboard.isControlPressed || keyboard.isMetaPressed;
              final isShiftPressed = keyboard.isShiftPressed;
              final isAltPressed = keyboard.isAltPressed;
              
              if (event.logicalKey == LogicalKeyboardKey.keyC &&
                  isCtrlOrCmd &&
                  isShiftPressed &&
                  !isAltPressed) {
                _openCalculator();
                return KeyEventResult.handled;
              }
              _handleKeyEvent(event);
            }
            return KeyEventResult.ignored; // اجازه بده سایر widget ها هم event را دریافت کنند
          } catch (e) {
            return KeyEventResult.ignored;
          }
        },
        child: Listener(
          onPointerDown: (_) {
            // وقتی کاربر کلیک می‌کند، focus را حفظ کن
            try {
              if (mounted && !_focusNode.hasFocus && _focusNode.canRequestFocus) {
                _focusNode.requestFocus();
              }
            } catch (e) {
            }
          },
          child: widget.child,
        ),
      ),
    );
  }

  void _handleKeyEvent(KeyDownEvent event) {
    try {
      final now = DateTime.now();
      final logicalKey = event.logicalKey;

      // Reset sequence اگر مدت زیادی از آخرین فشردن کلید گذشته باشد
      if (_lastKeyPressTime != null &&
          now.difference(_lastKeyPressTime!) > _resetDelay) {
        _keySequence.clear();
      }

      _lastKeyPressTime = now;

      final len = _keySequence.length;

      // منتظر Q
      if (len == 0) {
        if (_keysMatch(logicalKey, LogicalKeyboardKey.keyQ)) {
          _keySequence.add(logicalKey);
        }
        return;
      }

      // فقط Q: شاخه به H (پینگ‌پونگ) یا J (گرامیداشت)
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

      // مسیر پینگ‌پونگ یا گرامیداشت
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
    } catch (e) {
    }
  }

  bool _keysMatch(LogicalKeyboardKey key1, LogicalKeyboardKey key2) {
    // مقایسه با استفاده از keyId که مستقل از زبان است
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
    if (!mounted) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      try {
        final contextToUse = _dialogContext ?? context;
        _showDialogWithContext(
          contextToUse,
          dialog: dialog,
          barrierDismissible: barrierDismissible,
        );
      } catch (e) {
      }
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
            final newNavigator = Navigator.maybeOf(newContext, rootNavigator: false);
            if (newNavigator != null) {
              _showDialogDirectly(
                newContext,
                dialog: dialog,
                barrierDismissible: barrierDismissible,
              );
            } else {
              _showDialogDirectly(
                newContext,
                dialog: dialog,
                barrierDismissible: barrierDismissible,
              );
            }
          }
        });
        return;
      }

      _showDialogDirectly(
        contextToUse,
        dialog: dialog,
        barrierDismissible: barrierDismissible,
      );
    } catch (e) {
    }
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

      showDialog<void>(
        context: dialogContext,
        barrierDismissible: barrierDismissible,
        useRootNavigator: true,
        builder: (dialogBuildContext) {
          return dialog;
        },
      ).then((_) {}).catchError((_) {});
    } catch (e) {
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
      } catch (e2) {
      }
    }
  }

  void _openCalculator() {
    if (!mounted) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      try {
        final contextToUse = _dialogContext ?? context;
        final dialogContext = navigatorKey.currentContext ?? contextToUse;
        CalculatorDialog.show(dialogContext);
      } catch (e) {
        // خطا در باز کردن ماشین حساب
      }
    });
  }
}
