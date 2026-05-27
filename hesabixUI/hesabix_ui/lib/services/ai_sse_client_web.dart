// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;

import 'package:dio/dio.dart';

Stream<String> postSsePayloads({
  required Uri uri,
  required Map<String, String> headers,
  required String body,
  CancelToken? cancelToken,
}) {
  final controller = StreamController<String>();
  final request = html.HttpRequest();
  var consumedChars = 0;
  var pendingText = '';
  final eventBuffer = <String>[];
  var completed = false;

  void emitBufferedEvent() {
    if (eventBuffer.isEmpty) return;
    controller.add(eventBuffer.join('\n'));
    eventBuffer.clear();
  }

  void consumeAvailableText() {
    final text = request.responseText ?? '';
    if (text.length <= consumedChars) return;
    pendingText += text.substring(consumedChars);
    consumedChars = text.length;

    while (true) {
      final newline = pendingText.indexOf('\n');
      if (newline < 0) break;
      final rawLine = pendingText.substring(0, newline).trimRight();
      pendingText = pendingText.substring(newline + 1);
      final line = rawLine.endsWith('\r')
          ? rawLine.substring(0, rawLine.length - 1)
          : rawLine;
      if (line.isEmpty) {
        emitBufferedEvent();
        continue;
      }
      if (line.startsWith(':')) {
        continue;
      }
      if (line.startsWith('data:')) {
        final value = line.length > 5 && line[5] == ' '
            ? line.substring(6)
            : line.substring(5);
        eventBuffer.add(value);
      }
    }
  }

  void finishIfNeeded() {
    if (completed) return;
    completed = true;
    consumeAvailableText();
    if (pendingText.trim().isNotEmpty) {
      final line = pendingText.trimRight();
      if (line.startsWith('data:')) {
        eventBuffer.add(line.length > 5 && line[5] == ' '
            ? line.substring(6)
            : line.substring(5));
      }
      pendingText = '';
    }
    emitBufferedEvent();
    if (!controller.isClosed) {
      controller.close();
    }
  }

  request.onProgress.listen((_) => consumeAvailableText());
  request.onLoadEnd.listen((_) {
    final status = request.status ?? 0;
    if (status >= 200 && status < 400) {
      finishIfNeeded();
      return;
    }
    if (!controller.isClosed) {
      controller.addError(
        DioException(
          requestOptions: RequestOptions(path: uri.toString()),
          response: Response(
            requestOptions: RequestOptions(path: uri.toString()),
            statusCode: status,
            statusMessage: request.statusText,
            data: request.responseText,
          ),
          type: DioExceptionType.badResponse,
        ),
      );
      controller.close();
    }
  });
  request.onError.listen((_) {
    if (!controller.isClosed) {
      controller.addError(
        DioException(
          requestOptions: RequestOptions(path: uri.toString()),
          error: request.statusText,
          type: DioExceptionType.connectionError,
        ),
      );
      controller.close();
    }
  });

  cancelToken?.whenCancel.then((_) {
    try {
      request.abort();
    } catch (_) {
      // ignore abort failures
    }
    if (!controller.isClosed) {
      controller.close();
    }
  });

  scheduleMicrotask(() {
    try {
      request
        ..open('POST', uri.toString(), async: true)
        ..responseType = 'text';
      headers.forEach(request.setRequestHeader);
      request.send(body);
    } catch (error) {
      if (!controller.isClosed) {
        controller.addError(error);
        controller.close();
      }
    }
  });

  return controller.stream;
}
