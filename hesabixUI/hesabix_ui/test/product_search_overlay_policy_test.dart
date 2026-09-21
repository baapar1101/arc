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
    test('keeps the field as reference for a fast barcode scan', () {
      expect(
        shouldCommitHighlightedProductSuggestion(
          input: '6260151234567',
          loadedQuery: '6260151234567',
          hasSuggestions: true,
          navigatedByKeyboard: false,
        ),
        isFalse,
      );
    });

    test('commits the highlighted row after keyboard navigation', () {
      expect(
        shouldCommitHighlightedProductSuggestion(
          input: 'شیر',
          loadedQuery: 'شیر',
          hasSuggestions: true,
          navigatedByKeyboard: true,
        ),
        isTrue,
      );
    });

    test('rejects a highlighted row from stale search results', () {
      expect(
        shouldCommitHighlightedProductSuggestion(
          input: 'شیر کم چرب',
          loadedQuery: 'شیر',
          hasSuggestions: true,
          navigatedByKeyboard: true,
        ),
        isFalse,
      );
    });
  });
}
