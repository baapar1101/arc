import 'package:analyzer/error/error.dart';
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

import '../m3_lint.dart';

/// هر `Color(0xFF……)` خارج از `lib/theme/` را خطا می‌کند.
class AvoidRawHexColor extends DartLintRule {
  const AvoidRawHexColor() : super(code: _code);

  static const _code = LintCode(
    name: 'avoid_raw_hex_color',
    problemMessage: 'رنگ هگز سخت‌کدشده — توکن رنگ باید یک منبع داشته باشد.',
    correctionMessage:
        'آن را به lib/theme/tokens/color_schemes.dart منتقل کنید.',
    errorSeverity: ErrorSeverity.ERROR,
  );

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    if (isThemeFile(resolver.path)) return;

    context.registry.addInstanceCreationExpression((node) {
      if (node.constructorName.type.name2.lexeme != 'Color') return;
      reporter.atNode(node, _code);
    });
  }
}
