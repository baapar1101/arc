import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/utils/customer_quick_entry.dart';

void main() {
  group('customer quick entry parser', () {
    test('extracts a leading mobile and keeps the full alias', () {
      final entry = parseCustomerQuickEntry('09121234567 سید محمد مهدی رضوی');
      expect(entry?.mobile, '09121234567');
      expect(entry?.aliasName, 'سید محمد مهدی رضوی');
    });

    test('extracts a trailing international mobile', () {
      final entry = parseCustomerQuickEntry('زهرا سادات موسوی +989121234567');
      expect(entry?.mobile, '09121234567');
      expect(entry?.aliasName, 'زهرا سادات موسوی');
    });

    test('normalizes Persian digits for mobile-only entry', () {
      final entry = parseCustomerQuickEntry('۰۹۱۲۱۲۳۴۵۶۷');
      expect(entry?.mobile, '09121234567');
      expect(entry?.aliasName, isNull);
    });

    test('accepts a name-only entry and normalizes Persian letters', () {
      final entry = parseCustomerQuickEntry('  علي   رضايي  ');
      expect(entry?.mobile, isNull);
      expect(entry?.aliasName, 'علی رضایی');
    });

    test('rejects an ambiguous entry with two mobile numbers', () {
      expect(parseCustomerQuickEntry('09121234567 علی 09351234567'), isNull);
    });
  });

  group('customer Enter policy', () {
    test('selects the only loaded customer', () {
      expect(
        resolveCustomerSearchSubmitAction(
          input: '09121234567',
          loadedQuery: '09121234567',
          suggestionCount: 1,
          hasMoreSuggestions: false,
          navigatedByKeyboard: false,
          isLoading: false,
          quickCreateEnabled: true,
        ),
        CustomerSearchSubmitAction.selectSuggestion,
      );
    });

    test('selects a highlighted customer among several results', () {
      expect(
        resolveCustomerSearchSubmitAction(
          input: 'علی',
          loadedQuery: 'علی',
          suggestionCount: 3,
          hasMoreSuggestions: false,
          navigatedByKeyboard: true,
          isLoading: false,
          quickCreateEnabled: true,
        ),
        CustomerSearchSubmitAction.selectSuggestion,
      );
    });

    test('resolves several results on the server before selection', () {
      expect(
        resolveCustomerSearchSubmitAction(
          input: 'علی',
          loadedQuery: 'علی',
          suggestionCount: 3,
          hasMoreSuggestions: false,
          navigatedByKeyboard: false,
          isLoading: false,
          quickCreateEnabled: true,
        ),
        CustomerSearchSubmitAction.quickCreate,
      );
    });

    test('waits on shared fields where quick entry is disabled', () {
      expect(
        resolveCustomerSearchSubmitAction(
          input: 'علی',
          loadedQuery: 'علی',
          suggestionCount: 3,
          hasMoreSuggestions: false,
          navigatedByKeyboard: false,
          isLoading: false,
          quickCreateEnabled: false,
        ),
        CustomerSearchSubmitAction.waitForSelection,
      );
    });

    test('quick-creates only after a current empty search', () {
      expect(
        resolveCustomerSearchSubmitAction(
          input: '09121234567 علی رضایی',
          loadedQuery: '09121234567 علی رضایی',
          suggestionCount: 0,
          hasMoreSuggestions: false,
          navigatedByKeyboard: false,
          isLoading: false,
          quickCreateEnabled: true,
        ),
        CustomerSearchSubmitAction.quickCreate,
      );
    });

    test('searches before resolving stale results', () {
      expect(
        resolveCustomerSearchSubmitAction(
          input: 'علی رضایی',
          loadedQuery: 'علی',
          suggestionCount: 0,
          hasMoreSuggestions: false,
          navigatedByKeyboard: false,
          isLoading: false,
          quickCreateEnabled: true,
        ),
        CustomerSearchSubmitAction.search,
      );
    });

    test('resolves a mobile directly even while generic search is stale', () {
      expect(
        resolveCustomerSearchSubmitAction(
          input: '09171006219 موسوی',
          loadedQuery: 'موسوی',
          suggestionCount: 1,
          hasMoreSuggestions: false,
          navigatedByKeyboard: false,
          isLoading: true,
          quickCreateEnabled: true,
          inputHasMobile: true,
        ),
        CustomerSearchSubmitAction.quickCreate,
      );
    });

    test('keeps explicit keyboard selection for a mobile entry', () {
      expect(
        resolveCustomerSearchSubmitAction(
          input: '09171006219',
          loadedQuery: '09171006219',
          suggestionCount: 2,
          hasMoreSuggestions: false,
          navigatedByKeyboard: true,
          isLoading: false,
          quickCreateEnabled: true,
          inputHasMobile: true,
        ),
        CustomerSearchSubmitAction.selectSuggestion,
      );
    });
  });
}
