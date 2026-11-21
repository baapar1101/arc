import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/widgets/telephony/telephony_party.dart';

void main() {
  group('telephony party labels', () {
    test('inbound call shows recognized person with caller number subtitle', () {
      final call = <String, dynamic>{
        'direction': 'inbound',
        'from_number_normalized': '+989121234567',
        'person_name': 'Customer',
      };

      expect(
        telephonyPartyTitle(call, unknownLabel: 'Unknown'),
        'Customer',
      );
      expect(telephonyPartySubtitle(call), '+989121234567');
    });

    test('outbound unknown contact falls back to dialed number', () {
      final call = <String, dynamic>{
        'direction': 'outbound',
        'to_number_normalized': '+982112345678',
      };

      expect(
        telephonyPartyTitle(call, unknownLabel: 'Unknown'),
        '+982112345678',
      );
      expect(telephonyPartySubtitle(call), isNull);
    });

    test('ambiguous call uses warning label and retains peer number', () {
      final call = <String, dynamic>{
        'direction': 'inbound',
        'from_number_raw': '02155500000',
        'ambiguous': true,
        'person_name': 'Potential match',
      };

      expect(
        telephonyPartyTitle(
          call,
          unknownLabel: 'Unknown',
          ambiguousLabel: 'Ambiguous caller',
        ),
        'Ambiguous caller',
      );
      expect(telephonyPartySubtitle(call), '02155500000');
    });

    test('call without number or contact uses unknown label', () {
      expect(
        telephonyPartyTitle(const {}, unknownLabel: 'Unknown'),
        'Unknown',
      );
      expect(telephonyPartySubtitle(const {}), isNull);
    });
  });
}
