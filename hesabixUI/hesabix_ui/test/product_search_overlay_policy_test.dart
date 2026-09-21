import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/utils/product_search_overlay_policy.dart';

void main() {
  group('product search suggestion visibility', () {
    test('does not show suggestions for an empty or whitespace-only field', () {
      expect(shouldShowProductSearchSuggestions(''), isFalse);
      expect(shouldShowProductSearchSuggestions('   '), isFalse);
    });

    test('shows suggestions after the user types a query', () {
      expect(shouldShowProductSearchSuggestions('کالا'), isTrue);
      expect(shouldShowProductSearchSuggestions('  626015  '), isTrue);
    });
  });

  group('quick sales Enter behavior', () {
    test('searches the field when fast barcode suggestions are not loaded', () {
      expect(
        resolveQuickSalesProductSearchSubmitAction(
          input: '6260151234567',
          loadedQuery: '',
          suggestionCount: 0,
          hasMoreSuggestions: false,
          navigatedByKeyboard: false,
        ),
        QuickSalesProductSearchSubmitAction.searchField,
      );
    });

    test('commits the highlighted row after keyboard navigation', () {
      expect(
        resolveQuickSalesProductSearchSubmitAction(
          input: 'شیر',
          loadedQuery: 'شیر',
          suggestionCount: 4,
          hasMoreSuggestions: false,
          navigatedByKeyboard: true,
        ),
        QuickSalesProductSearchSubmitAction.selectSuggestion,
      );
    });

    test('commits the only current suggestion without keyboard navigation', () {
      expect(
        resolveQuickSalesProductSearchSubmitAction(
          input: 'شیر کم چرب',
          loadedQuery: 'شیر کم چرب',
          suggestionCount: 1,
          hasMoreSuggestions: false,
          navigatedByKeyboard: false,
        ),
        QuickSalesProductSearchSubmitAction.selectSuggestion,
      );
    });

    test(
      'waits for an explicit selection when several results are visible',
      () {
        expect(
          resolveQuickSalesProductSearchSubmitAction(
            input: 'شیر',
            loadedQuery: 'شیر',
            suggestionCount: 4,
            hasMoreSuggestions: false,
            navigatedByKeyboard: false,
          ),
          QuickSalesProductSearchSubmitAction.waitForSuggestionSelection,
        );
      },
    );

    test('does not select suggestions from stale search results', () {
      expect(
        resolveQuickSalesProductSearchSubmitAction(
          input: 'شیر کم چرب',
          loadedQuery: 'شیر',
          suggestionCount: 4,
          hasMoreSuggestions: false,
          navigatedByKeyboard: true,
        ),
        QuickSalesProductSearchSubmitAction.searchField,
      );
    });
  });
}
