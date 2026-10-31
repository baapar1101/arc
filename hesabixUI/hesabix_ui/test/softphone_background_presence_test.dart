import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/services/telephony/softphone_background_presence.dart';

void main() {
  group('windowsCloseDecision', () {
    test('hides to tray while Softphone wants presence', () {
      expect(
        windowsCloseDecision(softphoneWantsPresence: true),
        WindowsCloseDecision.hideToTray,
      );
    });

    test('confirms exit when Softphone is offline', () {
      expect(
        windowsCloseDecision(softphoneWantsPresence: false),
        WindowsCloseDecision.confirmExit,
      );
    });
  });

  group('softphone API envelope', () {
    test('unwraps data.session payload', () {
      final data = unwrapSoftphoneApiData({
        'success': true,
        'data': {
          'session': {'session_id': 'abc'},
          'media_ticket': 'ticket-1',
        },
      });
      expect(extractSoftphoneSessionId(data!), 'abc');
      expect(extractSoftphoneMediaTicket(data), 'ticket-1');
    });

    test('detects ended session from status and code', () {
      expect(isSoftphoneSessionGone(statusCode: 409, body: null), isTrue);
      expect(
        isSoftphoneSessionGone(
          statusCode: 200,
          body: {
            'success': false,
            'error': {'code': 'SOFTPHONE_SESSION_ENDED'},
          },
        ),
        isTrue,
      );
      expect(isSoftphoneSessionGone(statusCode: 200, body: {'success': true}), isFalse);
    });
  });
}
