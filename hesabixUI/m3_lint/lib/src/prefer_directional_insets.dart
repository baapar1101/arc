import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

/// `EdgeInsets.only(left:/right:)` در رابط راست‌به‌چپ برعکس می‌شود.
class PreferDirectionalInsets extends DartLintRule {
  const PreferDirectionalInsets() : super(code: _code);

  static const _code = LintCode(
    name: 'prefer_directional_insets',
    problemMessage: 'left/right در چیدمان فارسی برعکس می‌شود.',
    correctionMessage:
        'EdgeInsetsDirectional.only(start: ..., end: ...) را به کار ببرید.',
    errorSeverity: ErrorSeverity.WARNING,
  );

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    context.registry.addInstanceCreationExpression((node) {
      if (node.constructorName.type.name2.lexeme != 'EdgeInsets') return;
      final ctor = node.constructorName.name?.name;

      if (ctor == 'fromLTRB') {
        reporter.atNode(node, _code);
        return;
      }
      if (ctor != 'only') return;

      for (final arg in node.argumentList.arguments) {
        if (arg is! NamedExpression) continue;
        final label = arg.name.label.name;
        if (label == 'left' || label == 'right') {
          reporter.atNode(arg, _code);
        }
      }
    });
  }
}
