import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/distribution_map_tiles.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/pages/business/distribution/distribution_field_tab.dart';
import 'package:hesabix_ui/widgets/distribution/distribution_field_helpers.dart';
import 'package:hesabix_ui/widgets/distribution/distribution_plan_stop_card.dart';

DistributionFieldTabData _data({
  List<dynamic>? planItems,
  Map<String, dynamic>? activeVisit,
  Map<String, dynamic>? visitListPayload,
  bool shareLiveLocation = false,
  bool requireLocationConsent = true,
  bool locationConsent = false,
  bool canOperate = true,
  bool canManage = false,
  bool canTeam = false,
  bool loadingPlan = false,
  bool setupCompleted = true,
}) {
  return DistributionFieldTabData(
    planDay: DateTime(2026, 10, 28),
    teamTargetUserId: null,
    dailyPlan: {'items': planItems ?? const []},
    optimizedPlanItems: null,
    summary: const {},
    scorecard: null,
    activeVisit: activeVisit,
    visitListPayload: visitListPayload,
    loadingPlan: loadingPlan,
    loadingSummary: false,
    offlinePending: 0,
    shareLiveLocation: shareLiveLocation,
    requireLocationConsent: requireLocationConsent,
    locationConsent: locationConsent,
    liveGpsOk: true,
    planPublished: false,
    planLocked: false,
    setupCompleted: setupCompleted,
    canOperate: canOperate,
    canManage: canManage,
    canTeam: canTeam,
    navProvider: 'neshan',
    mapTiles: const DistributionMapTileConfig(),
  );
}

DistributionFieldTabActions _actions({
  void Function(Map<String, dynamic> item)? onStartVisit,
  void Function(int visitId, int? personId)? onCompleteVisit,
  VoidCallback? onGrantConsent,
}) {
  return DistributionFieldTabActions(
    onRefresh: () async {},
    onPlanDayChanged: (_) async {},
    onTeamTargetChanged: (_) async {},
    onGrantConsent: onGrantConsent ?? () {},
    onRevokeConsent: () {},
    onTogglePublish: () {},
    onPublishAll: () {},
    onCompleteVisit: onCompleteVisit ?? (_, __) {},
    onCancelVisit: () {},
    onStartVisit: onStartVisit ?? (_) {},
    onSetupPlan: () {},
    onGoToManage: () {},
    onOptimize: () {},
    onPrintPlan: () {},
    onOpenTeamMap: () {},
    onOpenReports: () {},
    onSetPersonLocation: (_) {},
    onShowOfflineQueue: () {},
    onOpenSetupWizard: () async {},
  );
}

Widget _app(Widget home) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: home),
  );
}

void main() {
  group('distribution helpers', () {
    test('formats iso dates with padded month and day', () {
      expect(distributionIsoDate(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('parses timestamps and rejects junk', () {
      expect(distributionParseDt('2026-10-28T08:00:00Z'), isNotNull);
      expect(distributionParseDt(null), isNull);
      expect(distributionParseDt('not-a-date'), isNull);
    });

    test('stop kind is current for the active visit person', () {
      expect(
        distributionPlanStopKind(
          personId: 7,
          planDay: DateTime(2026, 10, 28),
          activeVisit: {'person_id': 7},
        ),
        'current',
      );
    });

    test('stop kind is done only for a completed visit on the plan day', () {
      expect(
        distributionPlanStopKind(
          personId: 7,
          planDay: DateTime(2026, 10, 28),
          visitItems: [
            {'person_id': 7, 'status': 'completed', 'started_at': '2026-10-28T09:00:00Z'},
          ],
        ),
        'done',
      );
      expect(
        distributionPlanStopKind(
          personId: 7,
          planDay: DateTime(2026, 10, 28),
          visitItems: [
            {'person_id': 7, 'status': 'completed', 'started_at': '2026-10-27T09:00:00Z'},
          ],
        ),
        'pending',
      );
    });
  });

  group('DistributionPlanStopCard', () {
    testWidgets('pending stop shows start visit for an operator', (tester) async {
      var started = false;
      await tester.pumpWidget(
        _app(
          DistributionPlanStopCard(
            item: const {
              'person_id': 11,
              'person_name': 'Store A',
              'route_code': 'R-01',
              'route_name': 'North',
              'sort_order': 1,
              'stop_id': 4,
            },
            index: 0,
            kind: 'pending',
            isNext: true,
            canOperate: true,
            canManage: false,
            activeVisit: null,
            navProvider: 'neshan',
            onStartVisit: () => started = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Store A'), findsOneWidget);
      expect(find.text('Todo'), findsOneWidget);
      await tester.tap(find.text('Start visit'));
      expect(started, isTrue);
    });

    testWidgets('current stop shows complete visit when a visit is open', (tester) async {
      var completed = false;
      await tester.pumpWidget(
        _app(
          DistributionPlanStopCard(
            item: const {
              'person_id': 11,
              'person_name': 'Store A',
              'route_code': 'R-01',
              'route_name': 'North',
              'sort_order': 1,
              'stop_id': 4,
            },
            index: 0,
            kind: 'current',
            isNext: false,
            canOperate: true,
            canManage: false,
            activeVisit: const {'id': 90, 'person_id': 11},
            navProvider: 'neshan',
            onCompleteVisit: () => completed = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Start visit'), findsNothing);
      await tester.tap(find.text('Complete visit'));
      expect(completed, isTrue);
    });

    testWidgets('done stop has no start or complete action', (tester) async {
      await tester.pumpWidget(
        _app(
          const DistributionPlanStopCard(
            item: {
              'person_id': 11,
              'person_name': 'Store A',
              'route_code': 'R-01',
              'route_name': 'North',
              'sort_order': 1,
              'stop_id': 4,
            },
            index: 0,
            kind: 'done',
            isNext: false,
            canOperate: true,
            canManage: false,
            activeVisit: null,
            navProvider: 'neshan',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Start visit'), findsNothing);
      expect(find.text('Complete visit'), findsNothing);
    });
  });

  group('DistributionFieldTab', () {
    late CalendarController calendar;

    setUp(() {
      calendar = CalendarController.forTest();
    });

    tearDown(() {
      calendar.dispose();
    });

    testWidgets('empty plan shows the no-plan state', (tester) async {
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              final t = AppLocalizations.of(context);
              return DistributionFieldTab(
                t: t,
                calendarController: calendar,
                businessId: 1,
                data: _data(),
                actions: _actions(),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No route plan for this date.'), findsOneWidget);
    });

    testWidgets('asks for GPS consent when live sharing requires it', (tester) async {
      var granted = false;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              final t = AppLocalizations.of(context);
              return DistributionFieldTab(
                t: t,
                calendarController: calendar,
                businessId: 1,
                data: _data(shareLiveLocation: true, requireLocationConsent: true, locationConsent: false),
                actions: _actions(onGrantConsent: () => granted = true),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Location sharing consent'), findsOneWidget);
      await tester.tap(find.text('Allow'));
      expect(granted, isTrue);
    });

    testWidgets('renders a pending stop and starts a visit from the field tab', (tester) async {
      Map<String, dynamic>? started;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              final t = AppLocalizations.of(context);
              return DistributionFieldTab(
                t: t,
                calendarController: calendar,
                businessId: 1,
                data: _data(
                  planItems: const [
                    {
                      'person_id': 11,
                      'person_name': 'Store A',
                      'route_code': 'R-01',
                      'route_name': 'North',
                      'sort_order': 1,
                      'stop_id': 4,
                    },
                  ],
                ),
                actions: _actions(onStartVisit: (item) => started = item),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Store A'), findsOneWidget);
      await tester.tap(find.text('Start visit'));
      expect(started?['person_id'], 11);
    });
  });
}
