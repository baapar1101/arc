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

String? _canonicalPhoneCandidate(String value) {
  final normalized = toEnglishDigits(value).trim();
  final digits = toEnglishDigits(value).replaceAll(RegExp(r'\D'), '');
  if (normalized.startsWith('+')) {
    return digits.length >= 8 && digits.length <= 15 ? '+$digits' : null;
  }
  if (normalized.startsWith('00')) {
    final international = digits.substring(2);
    return international.length >= 8 && international.length <= 15
        ? '+$international'
        : null;
  }
  late final String canonical;
  if (digits.startsWith('98') && digits.length == 12) {
    canonical = '0${digits.substring(2)}';
  } else if (digits.startsWith('09') && digits.length == 11) {
    canonical = digits;
  } else if (digits.startsWith('9') && digits.length == 10) {
    canonical = '0$digits';
  } else {
    return digits.length >= 7 && digits.length <= 15 ? digits : null;
  }
  return RegExp(r'^09\d{9}$').hasMatch(canonical) ? canonical : null;
}

CustomerQuickEntry? parseCustomerQuickEntry(String rawInput) {
  final input = toEnglishDigits(rawInput).trim();
  if (input.isEmpty) return null;

  final mobilePattern = RegExp(r'(?:(?:\+|00)?\d)(?:[\s\-\(\)]*\d){6,14}');
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
  final mobile = _canonicalPhoneCandidate(rawMobile);
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
  bool inputHasMobile = false,
}) {
  final query = input.trim();
  if (query.isEmpty) return CustomerSearchSubmitAction.waitForSelection;
  // A mobile is the authoritative identity for quick entry. Resolve it on the
  // server even if the generic text search is stale, empty, or has one result.
  // Explicit keyboard navigation still wins so Enter selects that row.
  if (quickCreateEnabled && inputHasMobile && !navigatedByKeyboard) {
    return CustomerSearchSubmitAction.quickCreate;
  }
  if (isLoading || loadedQuery.trim() != query) {
    return CustomerSearchSubmitAction.search;
  }
  if (navigatedByKeyboard || (suggestionCount == 1 && !hasMoreSuggestions)) {
    return CustomerSearchSubmitAction.selectSuggestion;
  }
  if (suggestionCount > 0) {
    // در فروش سریع، API باید تشخیص دهد نتیجه دقیق است یا چند مشتری مشابه
    // باید برای انتخاب صریح کاربر نمایش داده شوند.
    return quickCreateEnabled
        ? CustomerSearchSubmitAction.quickCreate
        : CustomerSearchSubmitAction.waitForSelection;
  }
  return quickCreateEnabled
      ? CustomerSearchSubmitAction.quickCreate
      : CustomerSearchSubmitAction.waitForSelection;
}
