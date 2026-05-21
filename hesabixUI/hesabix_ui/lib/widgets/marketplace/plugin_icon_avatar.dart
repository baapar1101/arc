import 'package:flutter/material.dart';

import 'plugin_marketplace_utils.dart';

class PluginIconAvatar extends StatelessWidget {
  final String? iconUrl;
  final String? category;
  final String name;
  final double size;

  const PluginIconAvatar({
    super.key,
    required this.iconUrl,
    required this.category,
    required this.name,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final resolved = resolvePluginIconUrl(iconUrl);
    final trimmed = name.trim();
    final letter = trimmed.isNotEmpty ? trimmed[0] : '?';

    if (resolved != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.2),
        child: Image.network(
          resolved,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback(context, cs, letter),
        ),
      );
    }

    return _fallback(context, cs, letter);
  }

  Widget _fallback(BuildContext context, ColorScheme cs, String letter) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: cs.primaryContainer.withValues(alpha: 0.9),
      child: iconUrl != null && pluginIconIsSvg(iconUrl)
          ? Icon(pluginCategoryIcon(category), color: cs.onPrimaryContainer, size: size * 0.5)
          : Text(
              letter,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
            ),
    );
  }
}
