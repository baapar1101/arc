// مدل کاشی‌های دسترسی سریع (هماهنگ با API)

class QuickLinkPresetOption {
  final String id;
  final String title;
  final String icon;

  QuickLinkPresetOption({required this.id, required this.title, required this.icon});

  factory QuickLinkPresetOption.fromJson(Map<String, dynamic> json) {
    return QuickLinkPresetOption(
      id: '${json['id'] ?? ''}',
      title: '${json['title'] ?? ''}',
      icon: '${json['icon'] ?? 'link'}',
    );
  }
}

/// ذخیره‌شده در سرور
class QuickLinkStoredItem {
  final String id;
  final String kind; // preset | external
  final String? presetId;
  final String? url;
  final String? title;
  final String? titleOverride;

  QuickLinkStoredItem({
    required this.id,
    required this.kind,
    this.presetId,
    this.url,
    this.title,
    this.titleOverride,
  });

  Map<String, dynamic> toJson() {
    if (kind == 'external') {
      return {
        'id': id,
        'kind': 'external',
        'url': url,
        'title': title ?? 'لینک',
      };
    }
    return {
      'id': id,
      'kind': 'preset',
      'preset_id': presetId,
      if (titleOverride != null && titleOverride!.trim().isNotEmpty) 'title_override': titleOverride,
    };
  }

  factory QuickLinkStoredItem.fromJson(Map<String, dynamic> json) {
    final k = '${json['kind'] ?? 'preset'}';
    if (k == 'external') {
      return QuickLinkStoredItem(
        id: '${json['id'] ?? ''}',
        kind: 'external',
        url: json['url'] as String?,
        title: json['title'] as String?,
      );
    }
    return QuickLinkStoredItem(
      id: '${json['id'] ?? ''}',
      kind: 'preset',
      presetId: json['preset_id'] as String?,
      titleOverride: json['title_override'] as String?,
    );
  }
}

/// خروجی batch برای نمایش
class QuickLinkResolvedItem {
  final String id;
  final String kind; // internal | external
  final String title;
  final String icon;
  final String? routeName;
  final String? url;

  QuickLinkResolvedItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.icon,
    this.routeName,
    this.url,
  });

  factory QuickLinkResolvedItem.fromJson(Map<String, dynamic> json) {
    return QuickLinkResolvedItem(
      id: '${json['id'] ?? ''}',
      kind: '${json['kind'] ?? 'internal'}',
      title: '${json['title'] ?? ''}',
      icon: '${json['icon'] ?? 'link'}',
      routeName: json['route_name'] as String?,
      url: json['url'] as String?,
    );
  }
}
