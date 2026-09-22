import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/config/app_config.dart';

void main() {
  group('AppConfig.resolveApiBaseUrl', () {
    test('uses the explicitly configured API URL', () {
      expect(
        AppConfig.resolveApiBaseUrl(
          configuredValue: ' https://api.example.com ',
          isWebBuild: true,
          currentUri: Uri.parse('http://localhost:8080/sales'),
        ),
        'https://api.example.com',
      );
    });

    test('routes a local web preview to the API development port', () {
      expect(
        AppConfig.resolveApiBaseUrl(
          configuredValue: '',
          isWebBuild: true,
          currentUri: Uri.parse('http://localhost:8080/sales'),
        ),
        'http://localhost:8000',
      );
      expect(
        AppConfig.resolveApiBaseUrl(
          configuredValue: '',
          isWebBuild: true,
          currentUri: Uri.parse('http://127.0.0.1:8080/sales'),
        ),
        'http://127.0.0.1:8000',
      );
      expect(
        AppConfig.resolveApiBaseUrl(
          configuredValue: '',
          isWebBuild: true,
          currentUri: Uri.parse('http://192.168.50.101:8080/business/4952'),
        ),
        'http://192.168.50.101:8000',
      );
    });

    test('keeps the current origin behind a production reverse proxy', () {
      expect(
        AppConfig.resolveApiBaseUrl(
          configuredValue: '',
          isWebBuild: true,
          currentUri: Uri.parse('https://arc.example.com/sales'),
        ),
        'https://arc.example.com',
      );
    });

    test('uses the local API default outside web builds', () {
      expect(
        AppConfig.resolveApiBaseUrl(
          configuredValue: '',
          isWebBuild: false,
          currentUri: Uri.parse('file:///app'),
        ),
        'http://localhost:8000',
      );
    });
  });
}
