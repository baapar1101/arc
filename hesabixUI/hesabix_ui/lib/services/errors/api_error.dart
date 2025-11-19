class ApiErrorDetails implements Exception {
  final String? code;
  final String? message;
  final Map<String, dynamic>? details;

  const ApiErrorDetails({this.code, this.message, this.details});

  @override
  String toString() => message ?? 'خطای نامشخص';
}

