/// مدل پاسخ صفحه‌بندی شده
class PaginatedResponse<T> {
  final List<T> items;
  final int totalCount;
  final int page;
  final int pageSize;
  final bool hasNextPage;
  final bool hasPreviousPage;

  const PaginatedResponse({
    required this.items,
    required this.totalCount,
    required this.page,
    required this.pageSize,
    required this.hasNextPage,
    required this.hasPreviousPage,
  });

  factory PaginatedResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJsonT,
  ) {
    final items = (json['items'] as List<dynamic>?)
        ?.map((item) => fromJsonT(item as Map<String, dynamic>))
        .toList() ?? <T>[];

    final totalCount = json['total_count'] as int? ?? 0;
    final page = json['page'] as int? ?? 1;
    final pageSize = json['page_size'] as int? ?? 20;
    final hasNextPage = json['has_next_page'] as bool? ?? false;
    final hasPreviousPage = json['has_previous_page'] as bool? ?? false;

    return PaginatedResponse<T>(
      items: items,
      totalCount: totalCount,
      page: page,
      pageSize: pageSize,
      hasNextPage: hasNextPage,
      hasPreviousPage: hasPreviousPage,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'items': items,
      'total_count': totalCount,
      'page': page,
      'page_size': pageSize,
      'has_next_page': hasNextPage,
      'has_previous_page': hasPreviousPage,
    };
  }
}
