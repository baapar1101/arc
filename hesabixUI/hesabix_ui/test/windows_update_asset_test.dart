import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/services/windows_update/windows_update_models.dart';

/// Mirrors ranking rules used by WindowsUpdateService (kept in sync manually for
/// unit coverage without hitting Forgejo / dart:io installer launch).
int assetRank(WindowsReleaseAsset a) {
  final lower = a.name.toLowerCase();
  if (lower.contains('hesabix-windows') && lower.endsWith('.msi')) return 0;
  if (lower.endsWith('.msi')) return 1;
  if (lower.contains('hesabix-windows') && lower.endsWith('.exe')) return 2;
  if (lower.endsWith('.exe')) return 3;
  return 9;
}

bool looksLikeWindowsInstaller(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.apk')) return false;
  if (lower.endsWith('.msi')) return true;
  if (!lower.endsWith('.exe')) return false;
  return lower.contains('hesabix-windows') ||
      lower.contains('setup') ||
      lower.contains('installer') ||
      lower.contains('install');
}

void main() {
  group('Windows installer asset selection', () {
    test('ignores APK assets', () {
      expect(looksLikeWindowsInstaller('app-release.70.1.0.apk'), isFalse);
    });

    test('accepts MSI and setup EXE', () {
      expect(looksLikeWindowsInstaller('hesabix-windows.70.1.0.msi'), isTrue);
      expect(looksLikeWindowsInstaller('other.msi'), isTrue);
      expect(looksLikeWindowsInstaller('HesabixSetup.exe'), isTrue);
      expect(looksLikeWindowsInstaller('hesabix_ui.exe'), isFalse);
    });

    test('prefers hesabix-windows MSI', () {
      final assets = [
        const WindowsReleaseAsset(
          name: 'Setup.exe',
          size: 1,
          downloadUrl: 'https://example/Setup.exe',
        ),
        const WindowsReleaseAsset(
          name: 'hesabix-windows.70.1.0.msi',
          size: 2,
          downloadUrl: 'https://example/hesabix-windows.70.1.0.msi',
        ),
        const WindowsReleaseAsset(
          name: 'plain.msi',
          size: 3,
          downloadUrl: 'https://example/plain.msi',
        ),
      ]..sort((a, b) => assetRank(a).compareTo(assetRank(b)));

      expect(assets.first.name, 'hesabix-windows.70.1.0.msi');
      expect(assets.first.isMsi, isTrue);
    });
  });
}
