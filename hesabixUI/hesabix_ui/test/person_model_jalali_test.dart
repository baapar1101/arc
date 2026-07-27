import 'package:hesabix_ui/models/person_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Person.fromJson parses Jalali dates in nested social_contacts and bank_accounts', () {
    final person = Person.fromJson({
      'id': 58071,
      'business_id': 15,
      'alias_name': 'آوین',
      'person_types': ['تامین‌کننده'],
      'is_active': true,
      'created_at': '1405/02/02 17:29:36',
      'updated_at': '1405/02/02 17:29:36',
      'social_contacts': [
        {
          'id': 8,
          'person_id': 58071,
          'platform_key': 'rubika',
          'value': '09304379321',
          'sort_order': 0,
          'created_at': '1405/02/15 16:34:31',
          'updated_at': '1405/02/15 16:34:31',
        },
      ],
      'bank_accounts': [
        {
          'id': 1,
          'person_id': 58071,
          'bank_name': 'test',
          'is_active': true,
          'created_at': '1405/02/15 16:34:31',
          'updated_at': '1405/02/15 16:34:31',
        },
      ],
    });

    expect(person.displayName, 'آوین');
    expect(person.socialContacts.length, 1);
    expect(person.bankAccounts.length, 1);
    expect(person.socialContacts.first.createdAt.year, greaterThan(2020));
    expect(person.bankAccounts.first.createdAt.year, greaterThan(2020));
  });

  test('Person.fromJson parses Jalali dates when API sends formatted created_at', () {
    final person = Person.fromJson({
      'id': 1,
      'business_id': 15,
      'alias_name': 'test',
      'person_types': [],
      'is_active': true,
      'created_at': '1405/02/15 16:34:31',
      'created_at_raw': '2026-05-05T13:04:31Z',
      'updated_at': '1405/02/15 16:34:31',
      'updated_at_raw': '2026-05-05T13:04:31Z',
      'social_contacts': [
        {
          'id': 1,
          'person_id': 1,
          'platform_key': 'telegram',
          'value': 'x',
          'created_at': '1405/02/15 16:34:31',
          'created_at_raw': '2026-05-05T13:04:31Z',
          'updated_at': '1405/02/15 16:34:31',
          'updated_at_raw': '2026-05-05T13:04:31Z',
        },
      ],
    });

    expect(person.createdAt.year, greaterThan(2020));
    expect(person.socialContacts.first.createdAt.year, greaterThan(2020));
  });
}
