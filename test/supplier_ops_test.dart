// Covers the supplier operations module — Delivery & Settlement, Supply
// Requests and Team & Staff. The demo dataset has to reconcile with the finance
// module whose escrow it shares, the request lifecycle has to move forwards
// only, and phone validation has to accept every way a Rwandan number is
// written (the bug this suite exists for: `+250 78…` was being rejected).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:mvec_mobile/core/api_client.dart';
import 'package:mvec_mobile/core/theme.dart';
import 'package:mvec_mobile/features/supplier/models/supplier_operations.dart';
import 'package:mvec_mobile/features/supplier/models/supplier_team.dart';
import 'package:mvec_mobile/features/supplier/permissions.dart';
import 'package:mvec_mobile/features/supplier/screens/supplier_delivery_screen.dart';
import 'package:mvec_mobile/features/supplier/screens/supplier_supply_requests_screen.dart';
import 'package:mvec_mobile/features/supplier/screens/supplier_team_screen.dart';
import 'package:mvec_mobile/features/supplier/services/mock_supplier_finance_service.dart';
import 'package:mvec_mobile/features/supplier/services/mock_supplier_operations_service.dart';
import 'package:mvec_mobile/features/supplier/services/mock_supplier_team_service.dart';
import 'package:mvec_mobile/features/supplier/widgets/supplier_ops_widgets.dart';
import 'package:mvec_mobile/features/supplier/supplier_dependencies.dart';
import 'package:mvec_mobile/models/user.dart';
import 'package:mvec_mobile/providers/auth_provider.dart';

/// Stands in for the login, so permission-gated screens can be driven without a
/// real token or secure storage.
class _FixedAuth extends AuthController {
  _FixedAuth(this.user);

  final UserRecord user;

  @override
  AuthState build() =>
      AuthState(session: AuthSession(token: 'test-token', user: user));
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  MockSupplierOperationsService ops() =>
      MockSupplierOperationsService(delay: Duration.zero);
  MockSupplierTeamService team() =>
      MockSupplierTeamService(delay: Duration.zero);

  group('rwandan phone numbers', () {
    test('accepts every prefix and format the same number is written in', () {
      // 78, 79 and 73 as the supplier writes them, plus every variant that
      // means the same nine-digit subscriber number.
      const canonical = '788000000';
      for (final written in const [
        '+250788000000',
        '+250 78 800 0000',
        '+250-78-800-0000',
        '00250788000000',
        '0788000000',
        '0788 000 000',
        '788000000',
      ]) {
        expect(
          normalizeRwandanPhone(written),
          canonical,
          reason: '$written should normalise to $canonical',
        );
      }

      for (final prefix in const ['78', '79', '73', '72']) {
        final number = '${prefix}1234567';
        expect(
          normalizeRwandanPhone('+250$number'),
          number,
          reason: '+250$number is a valid number',
        );
      }
    });

    test('rejects anything that is not a Rwandan mobile number', () {
      for (final bad in const [
        '',
        '+250',
        '+250 78',
        '78800000', // one digit short
        '7880000000', // one digit long once the leading 0 is dropped
        '+250 788 000 000 1',
        '123456789', // not a mobile prefix
        '+256 788 000 000', // wrong country code
        'abcdefghi',
      ]) {
        expect(normalizeRwandanPhone(bad), isNull, reason: '$bad is invalid');
        expect(rwandanPhoneError(bad), isNotNull);
      }
    });

    test('recognises the carrier and formats for display', () {
      expect(rwandanCarrier('+250788000000'), 'MTN');
      expect(rwandanCarrier('0789123456'), 'MTN');
      expect(rwandanCarrier('+250 73 123 4567'), 'Airtel');
      expect(formatRwandanPhone('0788123456'), '+250 78 812 3456');
      expect(formatRwandanPhone('+250738123456'), '+250 73 812 3456');
      // Unparseable input is passed through rather than mangled.
      expect(formatRwandanPhone('nonsense'), 'nonsense');
    });

    test('the seeded numbers are all valid and distinct', () async {
      final seeded = await team().members();
      final numbers = seeded.map((m) => normalizeRwandanPhone(m.phone));
      expect(numbers.every((n) => n != null), isTrue);
      expect(numbers.toSet().length, seeded.length);
    });
  });

  group('delivery & settlement', () {
    test('the demo module is the bundled dataset', () {
      final service = ops();
      expect(service.isDemo, isTrue);
      expect(service.fallbackReason, isNull);
    });

    test('settlement reconciles with the finance escrow it releases', () async {
      final service = ops();
      final shipments = await service.shipments();
      final settlements = await service.settlements();
      final summary = await service.deliverySummary();
      final finance =
          await MockSupplierFinanceService(delay: Duration.zero).summary();

      expect(shipments, isNotEmpty);
      expect(settlements, isNotEmpty);

      // Every consignment posts the hold that locked its money, so the escrow
      // still sitting in the schedule is the sum of the undelivered net values.
      final heldByShipments = shipments
          .where((s) => s.settledAt == null)
          .fold<num>(0, (sum, s) => sum + s.net);
      expect(summary.inEscrow, closeTo(heldByShipments, 1));

      // And that is the same escrow the Payments page reports as held.
      expect(summary.inEscrow, closeTo(finance.escrowHeld, 1));

      // Every shipment is represented in the schedule, and the header counters
      // come off the shipment list rather than a second copy of it.
      expect(
        settlements.map((e) => e.orderNumber).toSet(),
        containsAll(shipments.map((s) => s.orderNumber)),
      );
      expect(
        summary.activeShipments,
        shipments.where((s) => !s.isDelivered).length,
      );
      expect(
        summary.deliveredThisMonth,
        shipments.where((s) => s.isDelivered).length,
      );
      expect(summary.releasedThisPeriod, greaterThanOrEqualTo(0));
      expect(summary.heldOrders, shipments.where((s) => s.isOnHold).length);
    });

    test('a shipment only reports milestones it has actually reached', () async {
      final shipments = await ops().shipments();
      for (final shipment in shipments) {
        // Stages progress in order, so a completed stage means every earlier
        // stage is complete too.
        var seenPending = false;
        for (final stage in DeliveryStage.values) {
          if (shipment.milestoneFor(stage)?.at == null) {
            seenPending = true;
          } else {
            expect(
              seenPending,
              isFalse,
              reason:
                  '${shipment.orderNumber} reached ${stage.label} out of order',
            );
          }
        }
        // An undelivered order has no delivery milestone, and escrow is only
        // released once the money has actually moved — which a disputed
        // delivery has not done, so delivered alone does not release it.
        if (!shipment.isDelivered) {
          expect(shipment.milestoneFor(DeliveryStage.delivered)?.at, isNull);
          expect(shipment.settledAt, isNull);
          expect(shipment.escrowAmount, closeTo(shipment.net, 1));
        } else {
          expect(shipment.deliveredAt, isNotNull);
          if (shipment.settledAt != null) {
            expect(shipment.escrowAmount, 0);
          } else {
            expect(shipment.isOnHold, isTrue);
            expect(shipment.escrowAmount, closeTo(shipment.net, 1));
          }
        }
      }
    });

    test('progress and on-time rate are percentages, not fractions', () async {
      final summary = await ops().deliverySummary();
      expect(summary.onTimeRate, greaterThanOrEqualTo(0));
      expect(summary.onTimeRate, lessThanOrEqualTo(100));
      expect(summary.releasedShare, inInclusiveRange(0, 100));
      expect(
        summary.pipelineValue,
        closeTo(summary.inEscrow + summary.scheduled, 1),
      );

      for (final shipment in await ops().shipments()) {
        expect(shipment.progress, inInclusiveRange(0, 1));
        expect(
          shipment.progress,
          closeTo(
            shipment.stageIndex / (DeliveryStage.values.length - 1),
            .001,
          ),
        );
      }
    });

    test('a paused settlement is one that has not been released', () async {
      final settlements = await ops().settlements();
      for (final event in settlements) {
        if (event.isPaused) {
          expect(event.isSettled, isFalse, reason: event.description);
          expect(event.isScheduled, isFalse, reason: event.description);
        }
        if (event.isSettled) {
          expect(event.settledAt, isNotNull);
        }
      }
      // The seeded demo includes a disputed order, so the paused branch is
      // actually exercised rather than dead code.
      final paused = settlements.where((e) => e.isPaused).toList();
      expect(paused, isNotEmpty);
      expect(paused.every((e) => e.description.contains('paused')), isTrue);

      // A held consignment's money is still locked, and is not counted as
      // booked into a future release.
      final shipments = await ops().shipments();
      for (final shipment in shipments.where((s) => s.isOnHold)) {
        expect(shipment.settledAt, isNull);
        expect(shipment.escrowAmount, shipment.net);
        expect(shipment.isAwaitingSettlement, isFalse);
      }
    });
  });

  group('supply requests', () {
    test('the guide covers every stage of the process', () async {
      final steps = await ops().supplyProcess();
      expect(steps, isNotEmpty);
      expect(steps.length, SupplyProcessStage.values.length);
      for (final stage in SupplyProcessStage.values) {
        expect(
          steps.any((s) => s.stage == stage),
          isTrue,
          reason: '${stage.label} is missing from the guide',
        );
      }
      // Both sides of every step are spelled out, and the numbering is 1-based.
      for (final step in steps) {
        expect(step.youDo, isNotEmpty);
        expect(step.mvecDoes, isNotEmpty);
        expect(step.timeframe, isNotEmpty);
        expect(step.number, inInclusiveRange(1, steps.length));
      }
    });

    test('the summary matches the requests it is derived from', () async {
      final service = ops();
      final all = await service.supplyRequests();
      final summary = SupplyRequestSummary.fromRequests(all);

      expect(summary.open + summary.closed, all.length);
      expect(summary.open, all.where((r) => r.isOpen).length);
      expect(summary.closed, all.where((r) => !r.isOpen).length);
      // Awaiting action means MVEC owes the supplier an answer, not that the
      // supplier can cancel.
      expect(
        summary.awaitingAction,
        all
            .where(
              (r) =>
                  r.status == SupplyRequestStatus.submitted ||
                  r.status == SupplyRequestStatus.underReview,
            )
            .length,
      );
      expect(
        summary.inProgress,
        all
            .where(
              (r) =>
                  r.status == SupplyRequestStatus.approved ||
                  r.status == SupplyRequestStatus.sourcing ||
                  r.status == SupplyRequestStatus.inTransit,
            )
            .length,
      );
      expect(summary.pipelineValue, greaterThan(0));
    });

    test('a request totals its lines and needs something to send', () async {
      final service = ops();
      final created = await service.createSupplyRequest(
        lines: const [
          SupplyRequestLine(
            product: 'Maize',
            category: 'Grains',
            units: 20,
            unit: 'bag',
            unitPrice: 1200,
          ),
          SupplyRequestLine(
            product: 'Beans',
            category: 'Grains',
            units: 10,
            unit: 'bag',
            unitPrice: 1800,
          ),
        ],
        neededBy: DateTime.now().add(const Duration(days: 30)),
        note: 'Q3 restock',
      );

      expect(created.status, SupplyRequestStatus.submitted);
      expect(created.lines.length, 2);
      expect(created.totalValue, 20 * 1200 + 10 * 1800);
      expect(created.totalUnits, 30);
      expect(created.note, 'Q3 restock');
      expect(created.reference, startsWith('SR-'));

      // Nothing to send, a bad quantity and a date already gone are all refused.
      expect(
        () => service.createSupplyRequest(
          lines: const [],
          neededBy: DateTime.now().add(const Duration(days: 5)),
        ),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => service.createSupplyRequest(
          lines: const [
            SupplyRequestLine(
              product: 'Maize',
              category: 'Grains',
              units: 0,
              unit: 'bag',
              unitPrice: 1200,
            ),
          ],
          neededBy: DateTime.now().add(const Duration(days: 5)),
        ),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => service.createSupplyRequest(
          lines: const [
            SupplyRequestLine(
              product: 'Maize',
              category: 'Grains',
              units: 5,
              unit: 'bag',
              unitPrice: 1200,
            ),
          ],
          neededBy: DateTime.now().subtract(const Duration(days: 1)),
        ),
        throwsA(isA<ApiException>()),
      );
    });

    test(
      'withdrawing then resubmitting works, and double-withdrawing does not',
      () async {
        final service = ops();
        final open = (await service.supplyRequests()).firstWhere(
          (r) => r.canCancel,
        );

        final cancelled = await service.cancelSupplyRequest(
          open.id,
          'Quantity changed',
        );
        expect(cancelled.status, SupplyRequestStatus.cancelled);
        expect(cancelled.decision, contains('Quantity changed'));
        expect(cancelled.canCancel, isFalse);
        expect(cancelled.canResubmit, isTrue);
        // The decision is recorded in the request's history.
        expect(cancelled.events.last.detail, contains('Quantity changed'));

        expect(
          () => service.cancelSupplyRequest(open.id, 'Again'),
          throwsA(isA<ApiException>()),
        );

        final back = await service.resubmitSupplyRequest(open.id);
        expect(back.status, SupplyRequestStatus.submitted);
        expect(back.isOpen, isTrue);
      },
    );

    test('a request that is already in flight cannot be withdrawn', () async {
      final service = ops();
      final inFlight = (await service.supplyRequests()).firstWhere(
        (r) => r.status == SupplyRequestStatus.inTransit,
      );
      expect(inFlight.canCancel, isFalse);
      expect(
        () => service.cancelSupplyRequest(inFlight.id, 'Too late'),
        throwsA(isA<ApiException>()),
      );
    });

    test('cancelling something that does not exist is refused', () async {
      expect(
        () => ops().cancelSupplyRequest('nope', 'why'),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => ops().resubmitSupplyRequest('nope'),
        throwsA(isA<ApiException>()),
      );
    });

    test('days until needed counts down and goes negative when overdue', () {
      final today = DateTime.now();
      SupplierSupplyRequest request(int days) => SupplierSupplyRequest(
        id: 'r',
        reference: 'SR-0000',
        createdAt: today,
        updatedAt: today,
        status: SupplyRequestStatus.submitted,
        lines: const [],
        neededBy: today.add(Duration(days: days)),
      );

      expect(request(3).daysUntilNeeded(today), 3);
      expect(request(-2).daysUntilNeeded(today), lessThan(0));
      // No date set means nothing to count down.
      expect(
        SupplierSupplyRequest(
          id: 'r',
          reference: 'SR-0000',
          createdAt: today,
          updatedAt: today,
          status: SupplyRequestStatus.submitted,
          lines: const [],
        ).daysUntilNeeded(today),
        isNull,
      );
    });

    test('the step number follows the status', () async {
      final requests = await ops().supplyRequests();
      for (final request in requests) {
        expect(request.stepNumber, request.status.stepNumber);
        if (request.stage == null) {
          expect(request.stepNumber, 0, reason: request.reference);
        } else {
          expect(
            request.stepNumber,
            inInclusiveRange(1, SupplyProcessStage.values.length),
          );
        }
      }
    });
  });

  group('team & staff', () {
    test('roles carry fixed permissions', () {
      for (final role in TeamRole.values) {
        expect(role.permissions, isNotEmpty, reason: '${role.label} has none');
      }
      expect(TeamRole.owner.isProtected, isTrue);
      expect(TeamRole.operations.isProtected, isFalse);
      expect(
        TeamRole.warehouse.permissions.length,
        lessThan(TeamRole.owner.permissions.length),
      );
    });

    test('the summary counts only active members towards coverage', () async {
      final service = team();
      final members = await service.members();
      final summary = await service.summary();

      expect(summary.total, members.length);
      expect(summary.active, members.where((m) => m.isActive).length);
      expect(
        summary.invited,
        members.where((m) => m.status == TeamMemberStatus.invited).length,
      );
      expect(
        summary.suspended,
        members.where((m) => m.status == TeamMemberStatus.suspended).length,
      );
      expect(
        summary.active + summary.invited + summary.suspended,
        members.length,
      );

      // Coverage is about permissions the roster can actually exercise today.
      for (final entry in summary.coverage) {
        expect(entry.holders.length, greaterThan(0));
        expect(entry.holders.every((m) => m.countsTowardsCoverage), isTrue);
      }
      expect(
        summary.gaps.map((g) => g.permission),
        isNot(contains(TeamPermission.requestPayout)),
      );
    });

    test('adding a member accepts a +250 number and normalises it', () async {
      final service = team();
      final added = await service.addMember(
        fullName: '  Claude Uwase  ',
        phone: '+250788123456',
        role: TeamRole.operations,
      );

      expect(added.fullName, 'Claude Uwase');
      expect(added.phone, '+250 78 812 3456');
      expect(added.status, TeamMemberStatus.invited);
      expect(added.role, TeamRole.operations);
      expect((await service.members()).any((m) => m.id == added.id), isTrue);
    });

    test('the same number cannot be added twice in another format', () async {
      final service = team();
      await service.addMember(
        fullName: 'Claude Uwase',
        phone: '+250788123456',
        role: TeamRole.operations,
      );
      expect(
        () => service.addMember(
          fullName: 'Someone Else',
          phone: '0788123456',
          role: TeamRole.warehouse,
        ),
        throwsA(isA<ApiException>()),
      );
    });

    test('a member needs a name and a valid number', () async {
      final service = team();
      expect(
        () => service.addMember(
          fullName: '   ',
          phone: '+250788123456',
          role: TeamRole.operations,
        ),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => service.addMember(
          fullName: 'Bad Number',
          phone: '12345',
          role: TeamRole.operations,
        ),
        throwsA(isA<ApiException>()),
      );
    });

    test('an owner cannot be added twice, edited or removed', () async {
      final service = team();
      expect(
        () => service.addMember(
          fullName: 'Second Owner',
          phone: '+250788000999',
          role: TeamRole.owner,
        ),
        throwsA(isA<ApiException>()),
      );

      final owner = (await service.members()).firstWhere((m) => m.isOwner);
      expect(
        () => service.updateMember(owner.id, fullName: 'Renamed'),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => service.removeMember(owner.id),
        throwsA(isA<ApiException>()),
      );
    });

    test('editing a member cannot hand them a duplicate number', () async {
      final service = team();
      final members = await service.members();
      final a = members.firstWhere((m) => !m.isOwner);
      final b = members.firstWhere((m) => !m.isOwner && m.id != a.id);

      await service.updateMember(a.id, phone: '+250789000111');
      final updated = (await service.members()).firstWhere((m) => m.id == a.id);
      expect(updated.phone, '+250 78 900 0111');

      expect(
        () => service.updateMember(a.id, phone: b.phone),
        throwsA(isA<ApiException>()),
      );
    });

    test('removing a member takes them off the roster', () async {
      final service = team();
      final member = (await service.members()).firstWhere((m) => !m.isOwner);
      final before = (await service.members()).length;

      await service.removeMember(member.id);
      final after = await service.members();
      expect(after.length, before - 1);
      expect(after.any((m) => m.id == member.id), isFalse);

      // Removing them twice is refused rather than silently ignored.
      expect(
        () => service.removeMember(member.id),
        throwsA(isA<ApiException>()),
      );
    });

    test('a suspended member cannot be forced active', () async {
      final service = team();
      final member = (await service.members()).firstWhere(
        (m) => !m.isOwner && m.isActive,
      );
      await service.updateMember(member.id, status: TeamMemberStatus.suspended);

      final after = (await service.members()).firstWhere(
        (m) => m.id == member.id,
      );
      expect(after.status, TeamMemberStatus.suspended);
      // Suspended staff no longer count towards permission coverage.
      expect(after.countsTowardsCoverage, isFalse);

      expect(
        () => service.updateMember(member.id, status: TeamMemberStatus.active),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('the signed-in login\'s permissions', () {
    UserRecord supplier({
      String? staffRole,
      String? status = 'active',
      List<String> permissions = const [],
    }) => UserRecord(
      id: 'u1',
      fullname: 'Test',
      role: 'supplier',
      status: status,
      staffRole: staffRole,
      permissions: permissions,
    );

    ProviderContainer containerFor(UserRecord user) {
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(() => _FixedAuth(user)),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('the account itself is the owner and can manage the team', () {
      final ref = containerFor(supplier());
      expect(ref.read(currentSupplierRoleProvider), TeamRole.owner);
      expect(ref.read(canManageTeamProvider), isTrue);
      expect(ref.read(canDoProvider(TeamPermission.requestPayout)), isTrue);
    });

    test('a staff login only gets its role\'s permissions', () {
      final ref = containerFor(supplier(staffRole: 'WAREHOUSE'));
      expect(ref.read(currentSupplierRoleProvider), TeamRole.warehouse);
      expect(ref.read(canManageTeamProvider), isFalse);
      expect(ref.read(canDoProvider(TeamPermission.adjustStock)), isTrue);
      expect(ref.read(canDoProvider(TeamPermission.viewFinance)), isFalse);
      expect(ref.read(canDoProvider(TeamPermission.requestPayout)), isFalse);
    });

    test(
      'a token claiming to be the owner gets the least access, not the most',
      () {
        // Self-promotion defence: `TeamRole.parse` has no owner case, so a forged
        // staffRole cannot walk into owner rights.
        final ref = containerFor(supplier(staffRole: 'OWNER'));
        expect(ref.read(currentSupplierRoleProvider), TeamRole.viewer);
        expect(ref.read(canManageTeamProvider), isFalse);
        expect(ref.read(canDoProvider(TeamPermission.viewFinance)), isFalse);
      },
    );

    test('an explicit token grant narrows the role further', () {
      final ref = containerFor(
        supplier(
          staffRole: 'FULFILMENT',
          permissions: const ['VIEW_DASHBOARD'],
        ),
      );
      expect(ref.read(supplierPermissionsProvider), {
        TeamPermission.viewDashboard,
      });
      expect(ref.read(canDoProvider(TeamPermission.confirmDelivery)), isFalse);
    });

    test('an unaccepted invite gets nothing at all', () {
      final ref = containerFor(
        supplier(staffRole: 'FINANCE', status: 'invited'),
      );
      expect(ref.read(currentSupplierRoleProvider), isNull);
      expect(ref.read(supplierPermissionsProvider), isEmpty);
      expect(ref.read(canManageTeamProvider), isFalse);
    });

    test('a non-supplier login has no supplier permissions', () {
      final ref = containerFor(
        UserRecord(id: 'u2', role: 'buyer', status: 'active'),
      );
      expect(ref.read(currentSupplierRoleProvider), isNull);
      expect(ref.read(supplierPermissionsProvider), isEmpty);
    });
  });

  group('supplier operations screens', () {
    Widget wrap(
      Widget child, {
      MockSupplierOperationsService? opsService,
      MockSupplierTeamService? teamService,
      UserRecord? asUser,
    }) => ProviderScope(
      overrides: [
        // Default to the account itself, which is what a real owner session
        // looks like; individual tests override it to exercise the guard.
        authControllerProvider.overrideWith(
          () => _FixedAuth(
            asUser ??
                UserRecord(
                  id: 'owner',
                  fullname: 'Demo Supplier',
                  role: 'supplier',
                  status: 'active',
                ),
          ),
        ),
        supplierOperationsModuleProvider.overrideWith(
          (ref) => opsService ?? ops(),
        ),
        supplierTeamModuleProvider.overrideWith((ref) => teamService ?? team()),
      ],
      child: MaterialApp(
        theme: lightAppTheme,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

    testWidgets('the delivery page lists consignments and the schedule', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const SupplierDeliveryScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(ShipmentCard), findsWidgets);
      expect(find.byType(DeliveryStageTrack), findsWidgets);
      expect(find.text('Settlement schedule'), findsOneWidget);
    });

    testWidgets('the supply requests page shows the guide and the queue', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const SupplierSupplyRequestsScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(SupplyProcessTimeline), findsOneWidget);
      expect(find.byType(SupplyRequestCard), findsWidgets);
      expect(find.byType(SupplyStepDots), findsWidgets);
    });

    testWidgets('the add-team-member form accepts a +250 number', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const SupplierTeamScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Add team member'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Phone number'),
        '+250788123456',
      );
      await tester.pumpAndSettle();

      // No validation error, and the entry is echoed back in a form the
      // supplier can check — which is what went wrong before.
      expect(
        find.text('Enter a Rwandan number, e.g. +250 788 000 000'),
        findsNothing,
      );
      expect(find.text('MTN · +250 78 812 3456'), findsOneWidget);
    });

    testWidgets('a bad number is still refused by the form', (tester) async {
      await tester.pumpWidget(wrap(const SupplierTeamScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Add team member'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Phone number'),
        '12345',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Send invite'));
      await tester.pumpAndSettle();

      expect(
        find.text('Enter a Rwandan number, e.g. +250 788 000 000'),
        findsOneWidget,
      );
    });

    testWidgets('staff without manage-team see a read-only roster', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const SupplierTeamScreen(),
          asUser: UserRecord(
            id: 'staff-1',
            fullname: 'Aline Mukamana',
            role: 'supplier',
            status: 'active',
            staffRole: 'WAREHOUSE',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The roster still renders — read-only staff must be able to see who
      // else is on the account — but every write is switched off. The button
      // stays visible rather than vanishing, so the supplier can see the
      // feature exists and read why they cannot use it.
      expect(find.text('Team & staff'), findsOneWidget);
      expect(find.byType(TeamMemberTile), findsWidgets);
      final addButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Add team member'),
      );
      expect(addButton.onPressed, isNull);
      expect(find.textContaining('cannot change the team'), findsOneWidget);
      // Nobody on the roster can be edited or removed by this login.
      for (final tile in tester.widgetList<TeamMemberTile>(
        find.byType(TeamMemberTile),
      )) {
        expect(tile.onEdit, isNull);
        expect(tile.onRemove, isNull);
      }
    });

    testWidgets('a valid member is saved onto the roster', (tester) async {
      final service = team();
      await tester.pumpWidget(
        wrap(const SupplierTeamScreen(), teamService: service),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Add team member'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Full name'),
        'Claude Uwase',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Phone number'),
        '+250 788 123 456',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Send invite'));
      // Bounded pumps rather than pumpAndSettle: the save, the dialog's closing
      // animation and the confirmation snackbar each schedule frames. Awaiting
      // the service directly would deadlock — inside testWidgets a
      // Future.delayed only fires when the clock is pumped.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 5));

      // The roster shows the new member, with the number normalised.
      expect(find.text('Claude Uwase'), findsWidgets);
      expect(find.text('+250 78 812 3456'), findsWidgets);
    });
  });
}
