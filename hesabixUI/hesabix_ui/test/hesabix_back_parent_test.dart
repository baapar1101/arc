import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/core/hesabix_back.dart';

void main() {
  group('logicalBusinessBackParent', () {
    test('dashboard is root', () {
      expect(logicalBusinessBackParent('dashboard'), isNull);
      expect(logicalBusinessBackParent(''), isNull);
      expect(isBusinessDashboardRelative('dashboard'), isTrue);
    });

    test('level-1 sidebar pages go to dashboard', () {
      expect(logicalBusinessBackParent('persons'), 'dashboard');
      expect(logicalBusinessBackParent('products'), 'dashboard');
      expect(logicalBusinessBackParent('invoice'), 'dashboard');
      expect(logicalBusinessBackParent('settings'), 'dashboard');
      expect(logicalBusinessBackParent('reports'), 'dashboard');
      expect(logicalBusinessBackParent('crm/leads'), 'dashboard');
      expect(logicalBusinessBackParent('distribution'), 'dashboard');
    });

    test('nested under hub stays in the same tab parent', () {
      expect(logicalBusinessBackParent('settings/print'), 'settings');
      expect(logicalBusinessBackParent('settings/fiscal-year'), 'settings');
      expect(logicalBusinessBackParent('reports/kardex'), 'reports');
      expect(logicalBusinessBackParent('reports/people-transactions'), 'reports');
      expect(logicalBusinessBackParent('invoice/new'), 'invoice');
      expect(logicalBusinessBackParent('invoice/12/edit'), 'invoice');
      expect(logicalBusinessBackParent('warehouses/4/locations'), 'warehouses');
      expect(logicalBusinessBackParent('warranty/settings'), 'warranty');
      expect(logicalBusinessBackParent('crm/leads/9'), 'crm/leads');
      expect(logicalBusinessBackParent('checks/reconciliation'), 'checks');
    });

    test('settings children with sibling paths go to settings', () {
      expect(logicalBusinessBackParent('users-permissions'), 'settings');
      expect(logicalBusinessBackParent('projects'), 'settings');
      expect(logicalBusinessBackParent('document-monetization'), 'settings');
      expect(logicalBusinessBackParent('notification-templates'), 'settings');
      expect(logicalBusinessBackParent('notification-templates/new'), 'notification-templates');
      expect(logicalBusinessBackParent('installments-report'), 'reports');
    });

    test('hyphenated module siblings', () {
      expect(logicalBusinessBackParent('repair-shop-settings'), 'repair-shop');
      expect(logicalBusinessBackParent('repair-shop-technicians'), 'repair-shop');
      expect(logicalBusinessBackParent('repair-shop/new'), 'repair-shop');
    });

    test('strips query string', () {
      expect(logicalBusinessBackParent('persons?q=1'), 'dashboard');
      expect(logicalBusinessBackParent('settings/print?x=1'), 'settings');
    });
  });
}
