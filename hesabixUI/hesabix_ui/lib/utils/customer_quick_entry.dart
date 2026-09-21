import 'number_normalizer.dart';

class CustomerQuickEntry {
  final String? aliasName;
  final String? mobile;

  const CustomerQuickEntry({required this.aliasName, required this.mobile});
}

enum CustomerSearchSubmitAction {
  selectSuggestion,
  search,
  quickCreate,
  waitForSelection,
}

String _collapseCustomerName(String value) => value
    .replaceAll('ي', 'ی')
    .replaceAll('ى', 'ی')
    .replaceAll('ك', 'ک')
    .replaceAll('‌', ' ')
    .trim()
    .split(RegExp(r'\s+'))
    .where((part) => part.isNotEmpty)
    .join(' ');

String? _canonicalIranianMobile(String value) {
  final digits = toEnglishDigits(value).replaceAll(RegExp(r'\D'), '');
  late final String canonical;
  if (digits.startsWith('0098') && digits.length == 14) {
    canonical = '0${digits.substring(4)}';
  } else if (digits.startsWith('98') && digits.length == 12) {
    canonical = '0${digits.substring(2)}';
  } else if (digits.startsWith('09') && digits.length == 11) {
    canonical = digits;
  } else if (digits.startsWith('9') && digits.length == 10) {
    canonical = '0$digits';
  } else {
    return null;
  }
  return RegExp(r'^09\d{9}$').hasMatch(canonical) ? canonical : null;
}

CustomerQuickEntry? parseCustomerQuickEntry(String rawInput) {
  final input = toEnglishDigits(rawInput).trim();
  if (input.isEmpty) return null;

  final mobilePattern = RegExp(
    r'(?:(?:\+98|0098|98)9|0?9)(?:[\s\-\(\)]?\d){9}',
  );
  final matches = mobilePattern.allMatches(input).where((match) {
    final before = match.start > 0 ? input[match.start - 1] : '';
    final after = match.end < input.length ? input[match.end] : '';
    return !RegExp(r'\d').hasMatch(before) && !RegExp(r'\d').hasMatch(after);
  }).toList();

  if (matches.length > 1) return null;
  if (matches.isEmpty) {
    final alias = _collapseCustomerName(input);
    return alias.isEmpty
        ? null
        : CustomerQuickEntry(aliasName: alias, mobile: null);
  }

  final rawMobile = matches.single.group(0)!;
  final mobile = _canonicalIranianMobile(rawMobile);
  if (mobile == null) return null;
  final alias = _collapseCustomerName(
    input.replaceRange(matches.single.start, matches.single.end, ' '),
  );
  return CustomerQuickEntry(
    aliasName: alias.isEmpty ? null : alias,
    mobile: mobile,
  );
}

CustomerSearchSubmitAction resolveCustomerSearchSubmitAction({
  required String input,
  required String loadedQuery,
  required int suggestionCount,
  required bool hasMoreSuggestions,
  required bool navigatedByKeyboard,
  required bool isLoading,
  required bool quickCreateEnabled,
}) {
  final query = input.trim();
  if (query.isEmpty) return CustomerSearchSubmitAction.waitForSelection;
  if (isLoading || loadedQuery.trim() != query) {
    return CustomerSearchSubmitAction.search;
  }
  if (navigatedByKeyboard || (suggestionCount == 1 && !hasMoreSuggestions)) {
    return CustomerSearchSubmitAction.selectSuggestion;
  }
  if (suggestionCount > 0) {
    return CustomerSearchSubmitAction.waitForSelection;
  }
  return quickCreateEnabled
      ? CustomerSearchSubmitAction.quickCreate
      : CustomerSearchSubmitAction.waitForSelection;
}
