import 'package:flutter/material.dart';
import '../core/fiscal_year_controller.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

class FiscalYearSwitcher extends StatelessWidget {
  final FiscalYearController controller;
  final List<Map<String, dynamic>> fiscalYears; // [{id, title, start_date, end_date, is_current}]
  final VoidCallback? onChanged; // برای رفرش دیتای داشبورد بعد از تغییر

  const FiscalYearSwitcher({super.key, required this.controller, required this.fiscalYears, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final int? selectedId = controller.fiscalYearId ?? _currentDefaultId();

    return DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        value: selectedId,
        icon: const Icon(Icons.expand_more, size: 18),
        items: fiscalYears.map((fy) {
          final id = fy['id'] as int;
          final title = (fy['title'] as String?) ?? id.toString();
          return DropdownMenuItem<int>(
            value: id,
            child: Text(title, overflow: TextOverflow.ellipsis),
          );
        }).toList(),
        onChanged: (id) async {
          await controller.setFiscalYearId(id);
          onChanged?.call();
        },
        hint: const Text('سال مالی'),
      ),
    );
  }

  int? _currentDefaultId() {
    try {
      final current = fiscalYears.firstWhere((e) => e['is_current'] == true, orElse: () => {});
      return (current['id'] as int?);
    } catch (_) {
      return null;
    }
  }
}


