import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
    expect(appearance, contains("'projects': 'پروژه‌ها'"));
    expect(appearance, contains("'tasks': 'مدیریت کارها'"));
  });
}
