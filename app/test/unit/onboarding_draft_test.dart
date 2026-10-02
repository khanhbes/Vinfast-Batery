import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/models/onboarding_draft.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'delayed remote restore cannot overwrite final local confirmation',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final remote = Completer<Map<String, dynamic>?>();
      final pending = OnboardingDraft.create(
        uid: 'race-qa',
        name: 'QA',
        catalogId: 'evo200',
      ).copyWith(revision: 20);
      final reader = OnboardingDraftRepository(
        loadRemote: (_) => remote.future,
      );
      final writer = OnboardingDraftRepository(loadRemote: (_) async => null);
      await writer.save(pending);
      final restoring = reader.load(pending.uid);
      final confirmed = pending.copyWith(
        revision: 22,
        finalizedAt: DateTime.utc(2026, 10, 2),
        state: OnboardingDraftState.failedRetryable,
      );
      await writer.save(confirmed);
      remote.complete(pending.toMap());
      final result = await restoring;
      expect(result?.revision, 22);
      expect(result?.isEligibleForCommit, isTrue);
      final afterRestart = await writer.load(pending.uid);
      expect(afterRestart?.finalizedAt, confirmed.finalizedAt);
      expect(afterRestart?.operationId, confirmed.operationId);
    },
  );

  test('onboarding draft round-trips without credentials', () {
    final draft = OnboardingDraft.create(
      uid: 'qa-user',
      name: 'QA User',
      catalogId: 'evo200',
      phone: '0900000000',
      initialOdo: 120,
      avgDailyDistanceKm: 18,
    );
    final restored = OnboardingDraft.fromMap(draft.uid, draft.toMap());

    expect(restored.uid, draft.uid);
    expect(restored.operationId, draft.operationId);
    expect(restored.catalogId, 'evo200');
    expect(restored.initialOdo, 120);
    expect(restored.avgDailyDistanceKm, 18);
    expect(restored.toMap().containsKey('password'), isFalse);
    expect(restored.toMap().containsKey('cloudAuthKey'), isFalse);
  });

  test('delayed save cannot erase final confirmation', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final repository = OnboardingDraftRepository(loadRemote: (_) async => null);
    final pending = OnboardingDraft.create(
      uid: 'stale-save-user',
      name: 'QA',
      catalogId: 'evo200',
    ).copyWith(revision: 20);
    final finalized = pending.copyWith(
      revision: 22,
      finalizedAt: DateTime.utc(2026, 10, 2),
    );
    await repository.save(finalized);
    await repository.save(pending);
    // Even a stale writer's independently incremented revision cannot erase
    // confirmation for the same operation.
    await repository.save(pending.copyWith(revision: 24));
    final restored = await repository.load(pending.uid);
    expect(restored?.revision, 22);
    expect(restored?.finalizedAt, finalized.finalizedAt);
  });

  test('copyWith preserves an idempotent operation identity', () {
    final draft = OnboardingDraft.create(
      uid: 'qa-user',
      name: 'QA User',
      catalogId: 'feliz',
    );
    final next = draft.copyWith(
      state: OnboardingDraftState.failedRetryable,
      attemptCount: 3,
    );
    expect(next.operationId, draft.operationId);
    expect(next.state, OnboardingDraftState.failedRetryable);
    expect(next.attemptCount, 3);
    expect(next.copyWith(dateOfBirth: null).dateOfBirth, isNull);
    expect(next.copyWith(nextAttemptAt: null).nextAttemptAt, isNull);
  });

  test('unfinished vehicle draft has no implicit ODO or completion marker', () {
    final draft = OnboardingDraft.create(
      uid: 'qa-user',
      name: 'QA User',
      catalogId: 'feliz',
    );

    expect(draft.initialOdo, isNull);
    expect(draft.finalizedAt, isNull);
    expect(draft.toMap().containsKey('initialOdo'), isFalse);
    expect(draft.toMap().containsKey('finalizedAt'), isFalse);
  });

  test('finalization marker survives local/Firestore map restoration', () {
    final finalizedAt = DateTime.utc(2026, 9, 26, 12);
    final draft = OnboardingDraft.create(
      uid: 'qa-user',
      name: 'QA User',
      catalogId: 'evo200',
    ).copyWith(finalizedAt: finalizedAt);

    final restored = OnboardingDraft.fromMap(draft.uid, draft.toMap());
    expect(restored.finalizedAt, finalizedAt);
  });

  test('syncing state never substitutes for final confirmation', () {
    final draft = OnboardingDraft.create(
      uid: 'qa-user',
      name: 'QA User',
      catalogId: 'evo200',
    );
    expect(draft.isEligibleForCommit, isFalse);
    expect(
      draft.copyWith(state: OnboardingDraftState.syncing).isEligibleForCommit,
      isFalse,
    );
    expect(
      draft
          .copyWith(state: OnboardingDraftState.failedRetryable)
          .isEligibleForCommit,
      isFalse,
    );
    expect(
      draft
          .copyWith(finalizedAt: DateTime.utc(2026, 9, 28))
          .isEligibleForCommit,
      isTrue,
    );
    expect(
      draft
          .copyWith(
            finalizedAt: DateTime.utc(2026, 9, 28),
            state: OnboardingDraftState.failedPermanent,
          )
          .isEligibleForCommit,
      isFalse,
    );
  });
}
