import 'package:dio/dio.dart';

Stream<String> postSsePayloads({
  required Uri uri,
  required Map<String, String> headers,
  required String body,
  CancelToken? cancelToken,
}) {
  return Stream<String>.error(
    UnsupportedError('Native SSE fetch is only available on Flutter Web.'),
  );
}
