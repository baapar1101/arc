import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/calculator_engine.dart';
import '../../utils/responsive_helper.dart';

/// دیالوگ ماشین حساب با UI Responsive
class CalculatorDialog extends StatefulWidget {
  final bool fullscreen;

  const CalculatorDialog({
    super.key,
    this.fullscreen = false,
  });

  /// نمایش دیالوگ به صورت Responsive
  static Future<double?> show(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    if (isMobile) {
      return Navigator.of(context).push<double>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const CalculatorDialog(fullscreen: true),
        ),
      );
    }
    return showDialog<double>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const CalculatorDialog(),
    );
  }

  @override
  State<CalculatorDialog> createState() => _CalculatorDialogState();
}

class _CalculatorDialogState extends State<CalculatorDialog> {
  String _display = '0';
  String _expression = '';
  double? _result;
  bool _shouldResetDisplay = false;
  late FocusNode _focusNode;

  void _onButtonPressed(String value) {
    setState(() {
      if (_shouldResetDisplay) {
        _display = '0';
        _expression = '';
        _shouldResetDisplay = false;
      }

      switch (value) {
        case 'C':
          // Clear All
          _display = '0';
          _expression = '';
          _result = null;
          break;
        case 'CE':
          // Clear Entry
          _display = '0';
          break;
        case '⌫':
          // Backspace
          if (_display.length > 1) {
            _display = _display.substring(0, _display.length - 1);
          } else {
            _display = '0';
          }
          break;
        case '=':
          // Calculate
          _calculate();
          break;
        case '+':
        case '-':
        case '*':
        case '/':
        case '%':
          // Operator
          if (_result != null) {
            _expression = CalculatorEngine.formatNumber(_result!);
            _display = CalculatorEngine.formatNumberWithSeparator(_result!);
            _result = null;
          }
          
          // حذف جداکننده هزارگان از display قبل از اضافه کردن به expression
          final displayValue = _display.replaceAll(',', '');
          
          // اگر expression خالی نیست و آخرین کاراکتر یک عملگر است، آن را جایگزین کن
          if (_expression.isNotEmpty) {
            final lastChar = _expression[_expression.length - 1];
            if (['+', '-', '*', '/', '%'].contains(lastChar)) {
              // جایگزین کردن عملگر قبلی
              _expression = _expression.substring(0, _expression.length - 1) + value;
            } else {
              // اضافه کردن عدد فعلی و سپس عملگر
              _expression += displayValue + value;
            }
          } else {
            // اگر expression خالی است، عدد فعلی را اضافه کن
            _expression += displayValue + value;
          }
          
          _display = '0';
          break;
        case '.':
          // Decimal point
          if (!_display.contains('.')) {
            // حذف جداکننده قبل از اضافه کردن نقطه
            final displayWithoutComma = _display.replaceAll(',', '');
            _display = displayWithoutComma + '.';
          }
          break;
        case '±':
          // Toggle sign
          if (_display != '0' && _display != 'Error') {
            final displayWithoutComma = _display.replaceAll(',', '');
            final numValue = double.tryParse(displayWithoutComma);
            if (numValue != null) {
              final newValue = -numValue;
              _display = CalculatorEngine.formatNumberWithSeparator(newValue);
            }
          }
          break;
        default:
          // Number
          if (_display == '0' || _display == 'Error') {
            _display = value;
          } else {
            // حذف جداکننده قبل از اضافه کردن عدد جدید
            final displayWithoutComma = _display.replaceAll(',', '');
            _display = displayWithoutComma + value;
            
            // اضافه کردن جداکننده هزارگان
            final numValue = double.tryParse(_display);
            if (numValue != null) {
              _display = CalculatorEngine.formatNumberWithSeparator(numValue);
            }
          }
      }
    });
  }

  void _calculate() {
    if (_expression.isEmpty) {
      // اگر عبارت خالی است، فقط نمایشگر را نگه دار
      return;
    }

    // اضافه کردن عدد فعلی به عبارت (حذف جداکننده هزارگان)
    final displayValue = _display.replaceAll(',', '');
    final fullExpression = _expression + displayValue;
    final result = CalculatorEngine.evaluate(fullExpression);

    if (result != null) {
      setState(() {
        _result = result;
        // استفاده از جداکننده هزارگان برای خوانایی بیشتر
        _display = CalculatorEngine.formatNumberWithSeparator(result);
        _expression = '';
        _shouldResetDisplay = true;
      });
    } else {
      // خطا در محاسبه
      setState(() {
        _display = 'Error';
        _expression = '';
        _shouldResetDisplay = true;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      final key = event.logicalKey;
      
      // اعداد
      if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
        _onButtonPressed('0');
      } else if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) {
        _onButtonPressed('1');
      } else if (key == LogicalKeyboardKey.digit2 || key == LogicalKeyboardKey.numpad2) {
        _onButtonPressed('2');
      } else if (key == LogicalKeyboardKey.digit3 || key == LogicalKeyboardKey.numpad3) {
        _onButtonPressed('3');
      } else if (key == LogicalKeyboardKey.digit4 || key == LogicalKeyboardKey.numpad4) {
        _onButtonPressed('4');
      } else if (key == LogicalKeyboardKey.digit5 || key == LogicalKeyboardKey.numpad5) {
        _onButtonPressed('5');
      } else if (key == LogicalKeyboardKey.digit6 || key == LogicalKeyboardKey.numpad6) {
        _onButtonPressed('6');
      } else if (key == LogicalKeyboardKey.digit7 || key == LogicalKeyboardKey.numpad7) {
        _onButtonPressed('7');
      } else if (key == LogicalKeyboardKey.digit8 || key == LogicalKeyboardKey.numpad8) {
        _onButtonPressed('8');
      } else if (key == LogicalKeyboardKey.digit9 || key == LogicalKeyboardKey.numpad9) {
        _onButtonPressed('9');
      }
      // عملگرها
      else if (key == LogicalKeyboardKey.add || key == LogicalKeyboardKey.numpadAdd) {
        _onButtonPressed('+');
      } else if (key == LogicalKeyboardKey.minus || key == LogicalKeyboardKey.numpadSubtract) {
        _onButtonPressed('-');
      } else if (key == LogicalKeyboardKey.asterisk || key == LogicalKeyboardKey.numpadMultiply) {
        _onButtonPressed('*');
      } else if (key == LogicalKeyboardKey.slash || key == LogicalKeyboardKey.numpadDivide) {
        _onButtonPressed('/');
      } else if (key == LogicalKeyboardKey.percent) {
        _onButtonPressed('%');
      }
      // نقطه اعشار
      else if (key == LogicalKeyboardKey.period || key == LogicalKeyboardKey.numpadDecimal) {
        _onButtonPressed('.');
      }
      // Enter یا = برای محاسبه
      else if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter || key == LogicalKeyboardKey.equal) {
        _onButtonPressed('=');
      }
      // Backspace
      else if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
        _onButtonPressed('⌫');
      }
      // Escape برای Clear
      else if (key == LogicalKeyboardKey.escape) {
        _onButtonPressed('C');
      }
    }
  }

  void _copyResult() {
    if (_result != null) {
      Clipboard.setData(ClipboardData(text: _display));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('نتیجه کپی شد'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = ResponsiveHelper.isMobile(context);
    final colorScheme = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenSize = MediaQuery.of(context).size;
        final padding = MediaQuery.of(context).padding;
        
        // محاسبه دقیق بر اساس فضای موجود - responsive کامل
        final availableHeight = isMobile 
            ? screenSize.height - padding.top - padding.bottom
            : (screenSize.height * 0.85).clamp(500.0, 650.0);
        final availableWidth = isMobile 
            ? screenSize.width
            : 340.0;
        
        // محاسبه اندازه‌ها بر اساس فضای موجود
        final headerHeight = isMobile ? 56.0 : 50.0;
        final displayHeight = isMobile ? 80.0 : 70.0;
        final buttonPadding = isMobile ? 8.0 : 10.0;
        final spacing = isMobile ? 6.0 : 8.0;
        
        // محاسبه ارتفاع دکمه‌ها: 5 ردیف با 4 spacing
        final buttonAreaHeight = availableHeight - headerHeight - displayHeight - (buttonPadding * 2);
        final buttonHeight = (buttonAreaHeight - (spacing * 4)) / 5;
        
        final content = Container(
          width: availableWidth,
          height: availableHeight,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: isMobile ? null : BorderRadius.circular(16),
          ),
          child: Column(
            children: [
          // Header - مینیمال
          if (!isMobile)
            Container(
              height: headerHeight,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    colorScheme.primary,
                    colorScheme.primary.withValues(alpha: 0.8),
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calculate, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'ماشین حساب',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.of(context).pop(_result),
                    tooltip: 'بستن',
                  ),
                ],
              ),
            )
          else
            AppBar(
              toolbarHeight: headerHeight,
              title: const Text('ماشین حساب', style: TextStyle(fontSize: 16)),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, size: 20),
                onPressed: () => Navigator.of(context).pop(_result),
              ),
              actions: [
                if (_result != null)
                  IconButton(
                    icon: const Icon(Icons.content_copy, size: 20),
                    onPressed: _copyResult,
                    tooltip: 'کپی نتیجه',
                  ),
              ],
            ),

          // Display - مینیمال
          Container(
            height: displayHeight,
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 12 : 12,
              vertical: isMobile ? 8 : 8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Expression (if exists)
                if (_expression.isNotEmpty)
                  Text(
                    _expression,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                      fontSize: isMobile ? 9 : 11,
                    ),
                    textDirection: TextDirection.ltr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 4),
                // Main display
                Expanded(
                  child: GestureDetector(
                    onLongPress: _copyResult,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: SelectableText(
                        _display,
                        style: TextStyle(
                          fontSize: isMobile ? 20 : 24,
                          fontWeight: FontWeight.bold,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: colorScheme.onSurface,
                        ),
                        textDirection: TextDirection.ltr,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Buttons - با ارتفاع محاسبه شده
          Expanded(
            child: Container(
              padding: EdgeInsets.all(buttonPadding),
              child: _buildButtonGrid(context, isMobile, colorScheme, buttonHeight, spacing, availableWidth),
            ),
          ),
            ],
          ),
        );

        final widgetWithKeyboard = Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: (node, event) {
            _handleKeyEvent(event);
            return KeyEventResult.handled;
          },
          child: content,
        );

        if (isMobile) {
          return Scaffold(
            backgroundColor: colorScheme.surface,
            body: SafeArea(child: widgetWithKeyboard),
          );
        }

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          insetPadding: const EdgeInsets.all(24),
          child: SizedBox(
            width: availableWidth,
            height: availableHeight,
            child: widgetWithKeyboard,
          ),
        );
      },
    );
  }

      Widget _buildButtonGrid(BuildContext context, bool isMobile, ColorScheme colorScheme, double buttonHeight, double spacing, double containerWidth) {
      final fontSize = isMobile ? 15.0 : 17.0;
      final buttonWidth = (containerWidth - (spacing * 3) - (isMobile ? 16.0 : 20.0)) / 4;

      return GridView.count(
      crossAxisCount: 4,
      mainAxisSpacing: spacing,
      crossAxisSpacing: spacing,
      childAspectRatio: buttonWidth / buttonHeight,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
        children: [
          // Row 1
          _CalculatorButton(
            label: 'C',
            onPressed: () => _onButtonPressed('C'),
            backgroundColor: colorScheme.errorContainer,
            textColor: colorScheme.onErrorContainer,
            fontSize: fontSize,
          ),
          _CalculatorButton(
            label: 'CE',
            onPressed: () => _onButtonPressed('CE'),
            backgroundColor: colorScheme.errorContainer,
            textColor: colorScheme.onErrorContainer,
            fontSize: fontSize,
          ),
          _CalculatorButton(
            label: '⌫',
            onPressed: () => _onButtonPressed('⌫'),
            backgroundColor: colorScheme.surfaceContainerHighest,
            textColor: colorScheme.onSurface,
            fontSize: fontSize,
          ),
          _CalculatorButton(
            label: '/',
            onPressed: () => _onButtonPressed('/'),
            backgroundColor: colorScheme.primaryContainer,
            textColor: colorScheme.onPrimaryContainer,
            fontSize: fontSize,
          ),

          // Row 2
          _CalculatorButton(
            label: '7',
            onPressed: () => _onButtonPressed('7'),
            backgroundColor: colorScheme.surfaceContainerHigh,
            textColor: colorScheme.onSurface,
            fontSize: fontSize,
          ),
          _CalculatorButton(
            label: '8',
            onPressed: () => _onButtonPressed('8'),
            backgroundColor: colorScheme.surfaceContainerHigh,
            textColor: colorScheme.onSurface,
            fontSize: fontSize,
          ),
          _CalculatorButton(
            label: '9',
            onPressed: () => _onButtonPressed('9'),
            backgroundColor: colorScheme.surfaceContainerHigh,
            textColor: colorScheme.onSurface,
            fontSize: fontSize,
          ),
          _CalculatorButton(
            label: '*',
            onPressed: () => _onButtonPressed('*'),
            backgroundColor: colorScheme.primaryContainer,
            textColor: colorScheme.onPrimaryContainer,
            fontSize: fontSize,
          ),

          // Row 3
          _CalculatorButton(
            label: '4',
            onPressed: () => _onButtonPressed('4'),
            backgroundColor: colorScheme.surfaceContainerHigh,
            textColor: colorScheme.onSurface,
            fontSize: fontSize,
          ),
          _CalculatorButton(
            label: '5',
            onPressed: () => _onButtonPressed('5'),
            backgroundColor: colorScheme.surfaceContainerHigh,
            textColor: colorScheme.onSurface,
            fontSize: fontSize,
          ),
          _CalculatorButton(
            label: '6',
            onPressed: () => _onButtonPressed('6'),
            backgroundColor: colorScheme.surfaceContainerHigh,
            textColor: colorScheme.onSurface,
            fontSize: fontSize,
          ),
          _CalculatorButton(
            label: '-',
            onPressed: () => _onButtonPressed('-'),
            backgroundColor: colorScheme.primaryContainer,
            textColor: colorScheme.onPrimaryContainer,
            fontSize: fontSize,
          ),

          // Row 4
          _CalculatorButton(
            label: '1',
            onPressed: () => _onButtonPressed('1'),
            backgroundColor: colorScheme.surfaceContainerHigh,
            textColor: colorScheme.onSurface,
            fontSize: fontSize,
          ),
          _CalculatorButton(
            label: '2',
            onPressed: () => _onButtonPressed('2'),
            backgroundColor: colorScheme.surfaceContainerHigh,
            textColor: colorScheme.onSurface,
            fontSize: fontSize,
          ),
          _CalculatorButton(
            label: '3',
            onPressed: () => _onButtonPressed('3'),
            backgroundColor: colorScheme.surfaceContainerHigh,
            textColor: colorScheme.onSurface,
            fontSize: fontSize,
          ),
          _CalculatorButton(
            label: '+',
            onPressed: () => _onButtonPressed('+'),
            backgroundColor: colorScheme.primaryContainer,
            textColor: colorScheme.onPrimaryContainer,
            fontSize: fontSize,
          ),

          // Row 5
          _CalculatorButton(
            label: '±',
            onPressed: () => _onButtonPressed('±'),
            backgroundColor: colorScheme.surfaceContainerHighest,
            textColor: colorScheme.onSurface,
            fontSize: fontSize,
          ),
          _CalculatorButton(
            label: '0',
            onPressed: () => _onButtonPressed('0'),
            backgroundColor: colorScheme.surfaceContainerHigh,
            textColor: colorScheme.onSurface,
            fontSize: fontSize,
          ),
          _CalculatorButton(
            label: '.',
            onPressed: () => _onButtonPressed('.'),
            backgroundColor: colorScheme.surfaceContainerHigh,
            textColor: colorScheme.onSurface,
            fontSize: fontSize,
          ),
          _CalculatorButton(
            label: '=',
            onPressed: () => _onButtonPressed('='),
            backgroundColor: colorScheme.primary,
            textColor: colorScheme.onPrimary,
            fontSize: fontSize,
          ),
        ],
      );
  }
}

/// دکمه ماشین حساب
class _CalculatorButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final Color backgroundColor;
  final Color textColor;
  final double fontSize;

  const _CalculatorButton({
    required this.label,
    required this.onPressed,
    required this.backgroundColor,
    required this.textColor,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}

