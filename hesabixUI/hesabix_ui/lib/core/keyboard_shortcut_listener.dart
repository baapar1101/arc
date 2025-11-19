import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/ping_pong/ping_pong_dialog.dart';
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
  static const List<LogicalKeyboardKey> _targetSequence = [
    LogicalKeyboardKey.keyQ,
    LogicalKeyboardKey.keyH,
    LogicalKeyboardKey.keyE,
    LogicalKeyboardKey.keyS,
    LogicalKeyboardKey.keyA,
    LogicalKeyboardKey.keyB,
    LogicalKeyboardKey.keyI,
    LogicalKeyboardKey.keyX,
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

      // بررسی اینکه آیا این کلید در توالی هدف است
      final expectedIndex = _keySequence.length;
      
      if (expectedIndex < _targetSequence.length) {
        final expectedKey = _targetSequence[expectedIndex];
        
        
        // مقایسه با استفاده از keyId که مستقل از زبان است
        if (_keysMatch(logicalKey, expectedKey)) {
          _keySequence.add(logicalKey);
          
          // اگر توالی کامل شد، دیالوگ را باز کن
          if (_keySequence.length == _targetSequence.length) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && context.mounted) {
                _openPingPongDialog();
              } else {
              }
            });
            _keySequence.clear();
          }
        } else {
          // اگر کلید اشتباه است، sequence را reset کن
          // اما اگر کلید اول Q باشد، شروع کن
          if (expectedIndex == 0 && _keysMatch(logicalKey, LogicalKeyboardKey.keyQ)) {
            _keySequence.clear();
            _keySequence.add(logicalKey);
          } else if (expectedIndex > 0) {
            // اگر sequence شروع شده بود، reset کن
            _keySequence.clear();
            // دوباره چک کن که آیا Q فشرده شده
            if (_keysMatch(logicalKey, LogicalKeyboardKey.keyQ)) {
              _keySequence.add(logicalKey);
            }
          } else {
            _keySequence.clear();
          }
        }
      } else {
        // اگر sequence کامل شده، reset کن
        _keySequence.clear();
        // دوباره چک کن که آیا Q فشرده شده
        if (_keysMatch(logicalKey, LogicalKeyboardKey.keyQ)) {
          _keySequence.add(logicalKey);
        }
      }
    } catch (e, stackTrace) {
    }
  }

  bool _keysMatch(LogicalKeyboardKey key1, LogicalKeyboardKey key2) {
    // مقایسه با استفاده از keyId که مستقل از زبان است
    return key1.keyId == key2.keyId;
  }

  void _openPingPongDialog() {
    if (!mounted) {
      return;
    }

    
    // استفاده از postFrameCallback برای اطمینان از اینکه widget tree کامل build شده
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      
      try {
        // استفاده از context فعلی که باید MaterialApp را داشته باشد
        final contextToUse = _dialogContext ?? context;
        
        
        // تلاش برای باز کردن دیالوگ
        _showDialogWithContext(contextToUse);
      } catch (e, stackTrace) {
      }
    });
  }

  void _showDialogWithContext(BuildContext contextToUse) {
    try {
      
      // بررسی وجود Navigator در context
      final navigator = Navigator.maybeOf(contextToUse, rootNavigator: false);
      if (navigator == null) {
        
        // تلاش برای پیدا کردن context معتبر با استفاده از Builder
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final newContext = _dialogContext ?? context;
            final newNavigator = Navigator.maybeOf(newContext, rootNavigator: false);
            if (newNavigator != null) {
              _showDialogDirectly(newContext);
            } else {
              // آخرین تلاش: استفاده مستقیم از showDialog
              _showDialogDirectly(newContext);
            }
          }
        });
        return;
      }
      
      _showDialogDirectly(contextToUse);
    } catch (e, stackTrace) {
    }
  }

  void _showDialogDirectly(BuildContext contextToUse) {
    try {
      
      // استفاده از navigatorKey.currentContext که همیشه معتبر است
      BuildContext? dialogContext = navigatorKey.currentContext;
      
      if (dialogContext == null) {
        // اگر navigatorKey.currentContext null است، از contextToUse استفاده کن
        dialogContext = contextToUse;
        
        // بررسی Navigator
        final navigator = Navigator.maybeOf(dialogContext, rootNavigator: true);
        
        if (navigator == null) {
          // صبر کن تا Navigator آماده شود
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              dialogContext = navigatorKey.currentContext ?? contextToUse;
              _showDialogDirectly(dialogContext!);
            }
          });
          return;
        }
      } else {
      }
      
      // استفاده مستقیم از showDialog با navigatorKey.currentContext یا contextToUse
      showDialog<void>(
        context: dialogContext,
        barrierDismissible: false,
        useRootNavigator: true, // استفاده از root navigator
        builder: (dialogBuildContext) {
          return const PingPongDialog();
        },
      ).then((_) {
      }).catchError((e, stackTrace) {
      });
    } catch (e, stackTrace) {
      
      // آخرین تلاش: استفاده از showGeneralDialog
      try {
        final fallbackContext = navigatorKey.currentContext ?? contextToUse;
        showGeneralDialog<void>(
          context: fallbackContext,
          barrierDismissible: false,
          barrierLabel: '',
          barrierColor: Colors.black54,
          transitionDuration: const Duration(milliseconds: 200),
          pageBuilder: (context, animation, secondaryAnimation) {
            return const PingPongDialog();
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
}
