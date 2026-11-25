/// سیاست نمایش و ثبت پیشنهادهای جست‌وجوی کالا در فیلدهای واکنش‌گرا.
///
/// منوی پیشنهاد فقط پس از ورود متن باز می‌شود. در فروش سریع، Enter پیشنهاد
/// انتخاب‌شده با صفحه‌کلید یا تنها نتیجهٔ موجود را ثبت می‌کند. اگر نتایج جاری
/// متعدد باشند، تا انتخاب صریح کاربر هیچ عملی انجام نمی‌شود.
bool shouldShowProductSearchSuggestions(String input) =>
    input.trim().isNotEmpty;

enum QuickSalesProductSearchSubmitAction {
  selectSuggestion,
  searchField,
  waitForSuggestionSelection,
}

QuickSalesProductSearchSubmitAction resolveQuickSalesProductSearchSubmitAction({
  required String input,
  required String loadedQuery,
  required int suggestionCount,
  required bool hasMoreSuggestions,
  required bool navigatedByKeyboard,
  bool preferDirectSearch = false,
}) {
  final normalizedInput = input.trim();
  if (normalizedInput.isEmpty) {
    return QuickSalesProductSearchSubmitAction.waitForSuggestionSelection;
  }

  if (preferDirectSearch) {
    return QuickSalesProductSearchSubmitAction.searchField;
  }

  final suggestionsBelongToInput =
      suggestionCount > 0 && loadedQuery.trim() == normalizedInput;
  if (!suggestionsBelongToInput) {
    return QuickSalesProductSearchSubmitAction.searchField;
  }

  if (navigatedByKeyboard || (suggestionCount == 1 && !hasMoreSuggestions)) {
    return QuickSalesProductSearchSubmitAction.selectSuggestion;
  }

  return QuickSalesProductSearchSubmitAction.waitForSuggestionSelection;
}
