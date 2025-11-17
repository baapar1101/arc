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
          print('🔑 KeyboardShortcutListener: Focus requested');
        } else {
          print('🔑 KeyboardShortcutListener: Cannot request focus (canRequestFocus: ${_focusNode.canRequestFocus}, mounted: $mounted)');
        }
      } catch (e) {
        print('🔑 KeyboardShortcutListener: Error requesting focus: $e');
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
    print('🔑 KeyboardShortcutListener: Building widget, context saved');
    
    return FocusScope(
      canRequestFocus: true,
      skipTraversal: false,
      child: Focus(
        focusNode: _focusNode,
        autofocus: false, // از autofocus استفاده نکنیم
        skipTraversal: true, // در focus traversal شرکت نکن
        onKeyEvent: (node, event) {
          try {
            print('🔑 KeyboardShortcutListener: Key event received: ${event.runtimeType}, key: ${event.logicalKey.keyLabel}, keyId: ${event.logicalKey.keyId}');
            if (event is KeyDownEvent) {
              _handleKeyEvent(event);
            }
            return KeyEventResult.ignored; // اجازه بده سایر widget ها هم event را دریافت کنند
          } catch (e) {
            print('🔑 KeyboardShortcutListener: Error handling key event: $e');
            return KeyEventResult.ignored;
          }
        },
        child: Listener(
          onPointerDown: (_) {
            // وقتی کاربر کلیک می‌کند، focus را حفظ کن
            try {
              if (mounted && !_focusNode.hasFocus && _focusNode.canRequestFocus) {
                _focusNode.requestFocus();
                print('🔑 KeyboardShortcutListener: Focus requested on pointer down');
              }
            } catch (e) {
              print('🔑 KeyboardShortcutListener: Error requesting focus on pointer down: $e');
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
      final keyId = logicalKey.keyId;
      final keyLabel = logicalKey.keyLabel;

      print('🔑 KeyboardShortcutListener: Handling key - Label: "$keyLabel", KeyId: $keyId, Current sequence length: ${_keySequence.length}');

      // Reset sequence اگر مدت زیادی از آخرین فشردن کلید گذشته باشد
      if (_lastKeyPressTime != null &&
          now.difference(_lastKeyPressTime!) > _resetDelay) {
        print('🔑 KeyboardShortcutListener: Resetting sequence (timeout)');
        _keySequence.clear();
      }

      _lastKeyPressTime = now;

      // بررسی اینکه آیا این کلید در توالی هدف است
      final expectedIndex = _keySequence.length;
      
      if (expectedIndex < _targetSequence.length) {
        final expectedKey = _targetSequence[expectedIndex];
        final expectedKeyId = expectedKey.keyId;
        
        print('🔑 KeyboardShortcutListener: Expected key at index $expectedIndex - KeyId: $expectedKeyId');
        
        // مقایسه با استفاده از keyId که مستقل از زبان است
        if (_keysMatch(logicalKey, expectedKey)) {
          _keySequence.add(logicalKey);
          print('🔑 KeyboardShortcutListener: Key matched! Sequence length: ${_keySequence.length}/${_targetSequence.length}');
          
          // اگر توالی کامل شد، دیالوگ را باز کن
          if (_keySequence.length == _targetSequence.length) {
            print('🔑 KeyboardShortcutListener: ✅ Sequence complete! Opening dialog...');
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && context.mounted) {
                _openPingPongDialog();
              } else {
                print('🔑 KeyboardShortcutListener: Cannot open dialog - context not mounted');
              }
            });
            _keySequence.clear();
          }
        } else {
          print('🔑 KeyboardShortcutListener: Key mismatch. Expected: $expectedKeyId, Got: $keyId');
          // اگر کلید اشتباه است، sequence را reset کن
          // اما اگر کلید اول Q باشد، شروع کن
          if (expectedIndex == 0 && _keysMatch(logicalKey, LogicalKeyboardKey.keyQ)) {
            _keySequence.clear();
            _keySequence.add(logicalKey);
            print('🔑 KeyboardShortcutListener: Starting new sequence with Q');
          } else if (expectedIndex > 0) {
            // اگر sequence شروع شده بود، reset کن
            _keySequence.clear();
            print('🔑 KeyboardShortcutListener: Resetting sequence (wrong key)');
            // دوباره چک کن که آیا Q فشرده شده
            if (_keysMatch(logicalKey, LogicalKeyboardKey.keyQ)) {
              _keySequence.add(logicalKey);
              print('🔑 KeyboardShortcutListener: Starting new sequence with Q');
            }
          } else {
            _keySequence.clear();
          }
        }
      } else {
        // اگر sequence کامل شده، reset کن
        _keySequence.clear();
        print('🔑 KeyboardShortcutListener: Sequence already complete, resetting');
        // دوباره چک کن که آیا Q فشرده شده
        if (_keysMatch(logicalKey, LogicalKeyboardKey.keyQ)) {
          _keySequence.add(logicalKey);
          print('🔑 KeyboardShortcutListener: Starting new sequence with Q');
        }
      }
    } catch (e, stackTrace) {
      print('🔑 KeyboardShortcutListener: Error in _handleKeyEvent: $e');
      print('🔑 KeyboardShortcutListener: Stack trace: $stackTrace');
    }
  }

  bool _keysMatch(LogicalKeyboardKey key1, LogicalKeyboardKey key2) {
    // مقایسه با استفاده از keyId که مستقل از زبان است
    return key1.keyId == key2.keyId;
  }

  void _openPingPongDialog() {
    if (!mounted) {
      print('🔑 KeyboardShortcutListener: Widget not mounted');
      return;
    }

    print('🔑 KeyboardShortcutListener: Attempting to open dialog');
    
    // استفاده از postFrameCallback برای اطمینان از اینکه widget tree کامل build شده
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        print('🔑 KeyboardShortcutListener: Widget unmounted during postFrameCallback');
        return;
      }
      
      try {
        // استفاده از context فعلی که باید MaterialApp را داشته باشد
        final contextToUse = _dialogContext ?? context;
        
        print('🔑 KeyboardShortcutListener: Checking Navigator and Overlay...');
        
        // بررسی Navigator
        final navigator = Navigator.maybeOf(contextToUse, rootNavigator: false);
        print('🔑 KeyboardShortcutListener: Navigator found: ${navigator != null}');
        
        // بررسی Overlay
        final overlay = Overlay.maybeOf(contextToUse);
        print('🔑 KeyboardShortcutListener: Overlay found: ${overlay != null}');
        
        // بررسی MaterialApp
        final materialApp = contextToUse.findAncestorWidgetOfExactType<MaterialApp>();
        print('🔑 KeyboardShortcutListener: MaterialApp found: ${materialApp != null}');
        
        // تلاش برای باز کردن دیالوگ
        _showDialogWithContext(contextToUse);
      } catch (e, stackTrace) {
        print('🔑 KeyboardShortcutListener: Error in postFrameCallback: $e');
        print('🔑 KeyboardShortcutListener: Stack trace: $stackTrace');
      }
    });
  }

  void _showDialogWithContext(BuildContext contextToUse) {
    try {
      print('🔑 KeyboardShortcutListener: Showing dialog...');
      
      // بررسی وجود Navigator در context
      final navigator = Navigator.maybeOf(contextToUse, rootNavigator: false);
      if (navigator == null) {
        print('🔑 KeyboardShortcutListener: Navigator not found, trying to find in widget tree...');
        
        // تلاش برای پیدا کردن context معتبر با استفاده از Builder
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final newContext = _dialogContext ?? context;
            final newNavigator = Navigator.maybeOf(newContext, rootNavigator: false);
            if (newNavigator != null) {
              print('🔑 KeyboardShortcutListener: Navigator found in postFrameCallback');
              _showDialogDirectly(newContext);
            } else {
              print('🔑 KeyboardShortcutListener: Navigator still not found after postFrameCallback');
              // آخرین تلاش: استفاده مستقیم از showDialog
              _showDialogDirectly(newContext);
            }
          }
        });
        return;
      }
      
      _showDialogDirectly(contextToUse);
    } catch (e, stackTrace) {
      print('🔑 KeyboardShortcutListener: Error in _showDialogWithContext: $e');
      print('🔑 KeyboardShortcutListener: Stack trace: $stackTrace');
    }
  }

  void _showDialogDirectly(BuildContext contextToUse) {
    try {
      print('🔑 KeyboardShortcutListener: Calling showDialog directly...');
      
      // استفاده از navigatorKey.currentContext که همیشه معتبر است
      BuildContext? dialogContext = navigatorKey.currentContext;
      
      if (dialogContext == null) {
        print('🔑 KeyboardShortcutListener: navigatorKey.currentContext is null, trying contextToUse...');
        // اگر navigatorKey.currentContext null است، از contextToUse استفاده کن
        dialogContext = contextToUse;
        
        // بررسی Overlay
        final overlay = Overlay.maybeOf(dialogContext);
        print('🔑 KeyboardShortcutListener: Overlay found: ${overlay != null}');
        
        // بررسی Navigator
        final navigator = Navigator.maybeOf(dialogContext, rootNavigator: true);
        print('🔑 KeyboardShortcutListener: Navigator found: ${navigator != null}');
        
        if (navigator == null) {
          print('🔑 KeyboardShortcutListener: Navigator not found in contextToUse, waiting...');
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
        print('🔑 KeyboardShortcutListener: Using navigatorKey.currentContext');
      }
      
      // استفاده مستقیم از showDialog با navigatorKey.currentContext یا contextToUse
      print('🔑 KeyboardShortcutListener: Attempting showDialog with context: ${dialogContext == navigatorKey.currentContext ? "navigatorKey" : "contextToUse"}...');
      showDialog<void>(
        context: dialogContext,
        barrierDismissible: false,
        useRootNavigator: true, // استفاده از root navigator
        builder: (dialogBuildContext) {
          print('🔑 KeyboardShortcutListener: ✅ Dialog builder called successfully!');
          return const PingPongDialog();
        },
      ).then((_) {
        print('🔑 KeyboardShortcutListener: Dialog closed');
      }).catchError((e, stackTrace) {
        print('🔑 KeyboardShortcutListener: ❌ Error in dialog: $e');
        print('🔑 KeyboardShortcutListener: Stack trace: $stackTrace');
      });
    } catch (e, stackTrace) {
      print('🔑 KeyboardShortcutListener: ❌ Error in _showDialogDirectly: $e');
      print('🔑 KeyboardShortcutListener: Stack trace: $stackTrace');
      
      // آخرین تلاش: استفاده از showGeneralDialog
      try {
        print('🔑 KeyboardShortcutListener: Last attempt: Using showGeneralDialog...');
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
        print('🔑 KeyboardShortcutListener: showGeneralDialog also failed: $e2');
      }
    }
  }
}
