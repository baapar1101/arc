import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/l10n/app_localizations_fa.dart';
import 'package:hesabix_ui/l10n/app_localizations_en.dart';
import 'package:hesabix_ui/utils/business_menu_labels.dart';

void main() {
  test('business sidebar exposes native project and task manager routes', () {
    final shell = File(
      'lib/pages/business/business_shell.dart',
    ).readAsStringSync();
    final appearance = File(
      'lib/pages/profile/appearance_settings_page.dart',
    ).readAsStringSync();

    expect(shell, contains("key: 'projects'"));
    expect(shell, contains("path: _bu('projects')"));
    expect(shell, contains("key: 'tasks'"));
    expect(shell, contains("label: 'مدیریت کارها'"));
    expect(shell, contains("path: _bu('tasks')"));

    expect(appearance, contains("'projects',"));
    expect(appearance, contains("'tasks',"));
    // Labels moved to the shared resolver during the upstream sidebar refactor.
    final fa = AppLocalizationsFa();
    final en = AppLocalizationsEn();
    expect(businessMenuItemLabel(fa, 'projects'), 'پروژه‌ها');
    expect(businessMenuItemLabel(fa, 'tasks'), 'مدیریت کارها');
    expect(businessMenuItemLabel(en, 'projects'), 'Projects');
    expect(businessMenuItemLabel(en, 'tasks'), 'Task manager');
  });
}
