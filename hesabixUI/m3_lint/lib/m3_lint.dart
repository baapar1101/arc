import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'src/avoid_raw_colors.dart';
import 'src/avoid_raw_hex_color.dart';
import 'src/prefer_directional_insets.dart';
import 'src/prefer_filled_button.dart';

PluginBase createPlugin() => _M3Lint();

class _M3Lint extends PluginBase {
  @override
  List<LintRule> getLintRules(CustomLintConfigs configs) => [
        const AvoidRawColors(),
        const AvoidRawHexColor(),
        const PreferDirectionalInsets(),
        const PreferFilledButton(),
      ];

  @override
  List<Assist> getAssists() => [];
}

/// پوشهٔ تم تنها جایی است که تعریف رنگ خام مجاز است.
bool isThemeFile(String path) {
  final p = path.replaceAll(r'\', '/');
  return p.contains('/lib/theme/');
}
