import 'package:analyzer/error/error.dart';
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

/// در M3 کنش اصلی با FilledButton است؛ ElevatedButton فقط روی سطح شلوغ.
class PreferFilledButton extends DartLintRule {
  const PreferFilledButton() : super(code: _code);

  static const _code = LintCode(
    name: 'prefer_filled_button',
    problemMessage: 'ElevatedButton در M3 نقش حاشیه‌ای دارد.',
    correctionMessage:
        'FilledButton برای کنش اصلی، FilledButton.tonal برای کنش ثانویهٔ مهم.',
    errorSeverity: ErrorSeverity.INFO,
  );

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    context.registry.addInstanceCreationExpression((node) {
      if (node.constructorName.type.name2.lexeme != 'ElevatedButton') return;
      reporter.atNode(node.constructorName, _code);
    });
  }
}
