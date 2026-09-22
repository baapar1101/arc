import 'package:analyzer/error/error.dart';
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

import '../m3_lint.dart';

/// هر `Colors.xxx` خارج از `lib/theme/` را خطا می‌کند.
class AvoidRawColors extends DartLintRule {
  const AvoidRawColors() : super(code: _code);

  static const _code = LintCode(
    name: 'avoid_raw_colors',
    problemMessage:
        'رنگ خام Material مجاز نیست — در دارک‌مود و با تعویض seed می‌شکند.',
    correctionMessage:
        'از Theme.of(context).colorScheme.* یا context.semantic.* استفاده کنید.',
    errorSeverity: ErrorSeverity.ERROR,
  );

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    if (isThemeFile(resolver.path)) return;

    context.registry.addPrefixedIdentifier((node) {
      if (node.prefix.name != 'Colors') return;
      // Colors.transparent بی‌ضرر است و معادل توکنی ندارد.
      if (node.identifier.name == 'transparent') return;
      reporter.atNode(node, _code);
    });
  }
}
