import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/pages/business/distribution/distribution_tab_permissions.dart';

void main() {
  group('distribution tab access', () {
    test('read-only users see visits and returns, not field operations', () {
      expect(
        distributionVisibleTabKeys(
          canOperate: false,
          canManage: false,
          enableVanSales: true,
          enablePresell: true,
        ),
        ['visits', 'returns'],
      );
    });

    test('operator without optional features sees standard flow', () {
      expect(
        distributionVisibleTabKeys(
          canOperate: true,
          canManage: false,
          enableVanSales: false,
          enablePresell: false,
        ),
        ['field', 'visits', 'returns', 'settlement'],
      );
    });

    test('optional commerce and van tabs follow business settings', () {
      expect(
        distributionVisibleTabKeys(
          canOperate: true,
          canManage: false,
          enableVanSales: true,
          enablePresell: true,
        ),
        ['field', 'visits', 'returns', 'settlement', 'van', 'commercial'],
      );
    });

    test('manager sees management tab and commercial flow', () {
      expect(
        distributionVisibleTabKeys(
          canOperate: true,
          canManage: true,
          enableVanSales: false,
          enablePresell: false,
        ),
        ['field', 'visits', 'returns', 'settlement', 'commercial', 'manage'],
      );
    });
  });
}
