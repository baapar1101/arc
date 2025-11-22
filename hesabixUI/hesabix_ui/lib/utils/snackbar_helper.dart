import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import '../main.dart' show navigatorKey;

/// Helper utility for showing SnackBar messages that appear above dialogs.
/// 
/// When multiple dialogs and bottom sheets are stacked, regular ScaffoldMessenger.of(context)
/// shows SnackBar below them. This helper finds the root ScaffoldMessenger
/// to ensure SnackBar appears above all dialogs and bottom sheets.
class SnackBarHelper {
  /// Shows a SnackBar using the root ScaffoldMessenger to ensure it appears
  /// above all dialogs.
  /// 
  /// [context] - The current BuildContext (can be from a dialog)
  /// [message] - The message to display
  /// [backgroundColor] - Optional background color (defaults to theme error color for errors)
  /// [isError] - If true, uses error styling
  /// [duration] - How long to show the SnackBar
  /// [action] - Optional action button
  static void show(
    BuildContext context, {
    required String message,
    Color? backgroundColor,
    bool isError = false,
    Duration? duration,
    SnackBarAction? action,
  }) {
    debugPrint('[SnackBarHelper.show] Called with message: "$message"');
    debugPrint('[SnackBarHelper.show] Context type: ${context.runtimeType}');
    debugPrint('[SnackBarHelper.show] Context mounted: ${context.mounted}');
    
    if (!context.mounted) {
      debugPrint('[SnackBarHelper.show] ✗ Context not mounted, returning');
      return;
    }

    // Try to use OverlayEntry method first (most reliable for stacked dialogs)
    final rootContext = navigatorKey.currentContext;
    if (rootContext != null) {
      if (rootContext.mounted) {
        debugPrint('[SnackBarHelper.show] Attempting to show via OverlayEntry in root context');
        try {
          _showViaOverlay(rootContext, message: message, backgroundColor: backgroundColor, isError: isError, duration: duration, action: action);
          debugPrint('[SnackBarHelper.show] ✓ Successfully shown via OverlayEntry');
          return;
        } catch (e) {
          debugPrint('[SnackBarHelper.show] ✗ OverlayEntry method failed: $e, falling back to ScaffoldMessenger');
        }
      } else {
        debugPrint('[SnackBarHelper.show] ✗ Root context not mounted, falling back to ScaffoldMessenger');
      }
    } else {
      debugPrint('[SnackBarHelper.show] ✗ Root context is null, falling back to ScaffoldMessenger');
    }

    // Fallback to ScaffoldMessenger method
    debugPrint('[SnackBarHelper.show] Falling back to ScaffoldMessenger method...');
    final rootMessenger = _findRootScaffoldMessenger(context);
    debugPrint('[SnackBarHelper.show] Found ScaffoldMessenger: ${rootMessenger.runtimeType}');
    
    final theme = Theme.of(context);
    final effectiveBackgroundColor = backgroundColor ?? 
        (isError ? Colors.red : theme.colorScheme.surfaceContainerHighest);
    
    debugPrint('[SnackBarHelper.show] Showing SnackBar with message: "$message"');
    rootMessenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: effectiveBackgroundColor,
        duration: duration ?? const Duration(seconds: 4),
        action: action,
      ),
    );
    debugPrint('[SnackBarHelper.show] ✓ SnackBar.showSnackBar called');
  }

  /// Shows SnackBar using OverlayEntry directly in root Overlay
  /// This ensures it appears above all dialogs and bottom sheets
  static void _showViaOverlay(
    BuildContext rootContext, {
    required String message,
    Color? backgroundColor,
    bool isError = false,
    Duration? duration,
    SnackBarAction? action,
  }) {
    // Get root Navigator's overlay which is above all dialogs
    final rootNavigator = Navigator.of(rootContext, rootNavigator: true);
    final overlay = rootNavigator.overlay;
    if (overlay == null) {
      throw Exception('Root overlay not found');
    }

    final theme = Theme.of(rootContext);
    final effectiveBackgroundColor = backgroundColor ?? 
        (isError ? Colors.red : theme.colorScheme.surfaceContainerHighest);
    final effectiveDuration = duration ?? const Duration(seconds: 4);

    late OverlayEntry overlayEntry;
    Timer? timer;

    overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Material(
              color: Colors.transparent,
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(4),
                  color: effectiveBackgroundColor,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            message,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        if (action != null)
                          TextButton(
                            onPressed: () {
                              action.onPressed();
                              overlayEntry.remove();
                              timer?.cancel();
                            },
                            child: Text(
                              action.label,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(overlayEntry);

    // Auto-remove after duration
    timer = Timer(effectiveDuration, () {
      overlayEntry.remove();
    });
  }

  /// Shows an error SnackBar
  static void showError(
    BuildContext context, {
    required String message,
    Duration? duration,
    SnackBarAction? action,
  }) {
    show(
      context,
      message: message,
      isError: true,
      duration: duration,
      action: action,
    );
  }

  /// Shows a success SnackBar
  static void showSuccess(
    BuildContext context, {
    required String message,
    Duration? duration,
  }) {
    show(
      context,
      message: message,
      backgroundColor: Colors.green,
      duration: duration,
    );
  }

  /// Finds the root ScaffoldMessenger by using the global navigatorKey.
  /// This ensures SnackBar appears above all dialogs and bottom sheets.
  static ScaffoldMessengerState _findRootScaffoldMessenger(BuildContext context) {
    debugPrint('[SnackBarHelper] Starting to find root ScaffoldMessenger');
    debugPrint('[SnackBarHelper] Current context type: ${context.runtimeType}');
    
    // Strategy 1: Use the global navigatorKey which points to the root Navigator
    // This is the most reliable method when multiple dialogs/bottom sheets are stacked
    final rootContext = navigatorKey.currentContext;
    debugPrint('[SnackBarHelper] Strategy 1: navigatorKey.currentContext = ${rootContext != null ? rootContext.runtimeType : "null"}');
    
    if (rootContext != null && rootContext.mounted) {
      try {
        final messenger = ScaffoldMessenger.maybeOf(rootContext);
        if (messenger != null) {
          debugPrint('[SnackBarHelper] ✓ Strategy 1 SUCCESS: Found ScaffoldMessenger via navigatorKey');
          return messenger;
        } else {
          debugPrint('[SnackBarHelper] ✗ Strategy 1 FAILED: ScaffoldMessenger.maybeOf returned null');
        }
      } catch (e) {
        debugPrint('[SnackBarHelper] ✗ Strategy 1 ERROR: $e');
      }
    } else {
      debugPrint('[SnackBarHelper] ✗ Strategy 1 SKIPPED: rootContext is null or not mounted');
    }

    // Strategy 2: Get root navigator from current context and find ScaffoldMessenger
    // This works when we're inside a dialog but navigatorKey is not available
    try {
      final rootNavigator = Navigator.of(context, rootNavigator: true);
      final rootNavContext = rootNavigator.context;
      debugPrint('[SnackBarHelper] Strategy 2: rootNavigator.context = ${rootNavContext.runtimeType}');
      
      if (rootNavContext.mounted) {
        final messenger = ScaffoldMessenger.maybeOf(rootNavContext);
        if (messenger != null) {
          debugPrint('[SnackBarHelper] ✓ Strategy 2 SUCCESS: Found ScaffoldMessenger via rootNavigator');
          return messenger;
        } else {
          debugPrint('[SnackBarHelper] ✗ Strategy 2 FAILED: ScaffoldMessenger.maybeOf returned null');
        }
      } else {
        debugPrint('[SnackBarHelper] ✗ Strategy 2 FAILED: rootNavContext is not mounted');
      }
    } catch (e) {
      debugPrint('[SnackBarHelper] ✗ Strategy 2 ERROR: $e');
    }

    // Strategy 3: Traverse up the context tree to find ScaffoldMessenger
    // This handles edge cases where we're deep in a dialog/bottom sheet stack
    debugPrint('[SnackBarHelper] Strategy 3: Traversing up context tree...');
    BuildContext? currentContext = context;
    ScaffoldMessengerState? foundMessenger;
    int maxDepth = 20; // Prevent infinite loops
    int depth = 0;
    
    while (currentContext != null && depth < maxDepth) {
      depth++;
      try {
        if (currentContext.mounted) {
          final messenger = ScaffoldMessenger.maybeOf(currentContext);
          if (messenger != null) {
            debugPrint('[SnackBarHelper] Strategy 3: Found ScaffoldMessenger at depth $depth, context type: ${currentContext.runtimeType}');
            // Check if this context has a root Navigator (meaning it's at root level)
            try {
              final navigator = Navigator.maybeOf(currentContext, rootNavigator: true);
              if (navigator != null) {
                debugPrint('[SnackBarHelper] ✓ Strategy 3 SUCCESS: Found root ScaffoldMessenger at depth $depth');
                foundMessenger = messenger;
                break;
              } else {
                debugPrint('[SnackBarHelper] Strategy 3: ScaffoldMessenger found but no root Navigator, continuing...');
              }
            } catch (e) {
              debugPrint('[SnackBarHelper] Strategy 3: Error checking root Navigator: $e');
            }
          }
        }
      } catch (e) {
        debugPrint('[SnackBarHelper] Strategy 3: Error at depth $depth: $e');
      }
      
      // Move to parent element
      final element = currentContext as Element?;
      if (element != null) {
        BuildContext? parentContext;
        element.visitAncestorElements((parent) {
          parentContext = parent;
          return false; // Stop after first ancestor
        });
        currentContext = parentContext;
      } else {
        debugPrint('[SnackBarHelper] Strategy 3: Reached end of tree at depth $depth');
        break;
      }
    }
    
    if (foundMessenger != null) {
      return foundMessenger;
    }

    // Fallback: try to find any ScaffoldMessenger in the current context tree
    // This will work even if we're in a dialog, but might not be the root
    debugPrint('[SnackBarHelper] Fallback: Trying current context...');
    if (context.mounted) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger != null) {
        debugPrint('[SnackBarHelper] ⚠ Fallback SUCCESS: Using ScaffoldMessenger from current context (may be wrong one!)');
        return messenger;
      } else {
        debugPrint('[SnackBarHelper] ✗ Fallback FAILED: No ScaffoldMessenger in current context');
      }
    }

    // Last resort: use ScaffoldMessenger.of which will throw if not found
    // This should rarely happen in practice
    debugPrint('[SnackBarHelper] ⚠ Last resort: Using ScaffoldMessenger.of (may throw)');
    try {
      final messenger = ScaffoldMessenger.of(context);
      debugPrint('[SnackBarHelper] ⚠ Last resort SUCCESS: Got ScaffoldMessenger (may be wrong one!)');
      return messenger;
    } catch (e) {
      debugPrint('[SnackBarHelper] ✗ Last resort ERROR: $e');
      rethrow;
    }
  }
}

