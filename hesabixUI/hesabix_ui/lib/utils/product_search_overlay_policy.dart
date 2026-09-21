/// سیاست نمایش و ثبت پیشنهادهای جست‌وجوی کالا در فیلدهای دسکتاپ.
///
/// منوی پیشنهاد فقط پس از ورود متن باز می‌شود. در فروش سریع نیز Enter تنها
/// زمانی پیشنهاد هایلایت‌شده را ثبت می‌کند که کاربر با صفحه‌کلید داخل همان
/// نتایج حرکت کرده باشد؛ در غیر این صورت متن فیلد مرجع جست‌وجو/بارکد است.
bool shouldShowProductSearchSuggestions(String input) =>
    input.trim().isNotEmpty;

bool shouldCommitHighlightedProductSuggestion({
  required String input,
  required String loadedQuery,
  required bool hasSuggestions,
  required bool navigatedByKeyboard,
}) {
  final normalizedInput = input.trim();
  return normalizedInput.isNotEmpty &&
      hasSuggestions &&
      navigatedByKeyboard &&
      loadedQuery.trim() == normalizedInput;
}
