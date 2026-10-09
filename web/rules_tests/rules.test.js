const fs = require('node:fs');
const path = require('node:path');
const {
  initializeTestEnvironment,
  assertFails: firebaseAssertFails,
  assertSucceeds: firebaseAssertSucceeds,
} = require('@firebase/rules-unit-testing');
const {
  collection,
  doc,
  deleteDoc,
  getDoc,
  getDocs,
  query,
  runTransaction,
  setDoc,
  updateDoc,
  where,
} = require('firebase/firestore');

let env;
let assertionCount = 0;

async function assertFails(promise) {
  await firebaseAssertFails(promise);
  assertionCount += 1;
}

async function assertSucceeds(promise) {
  await firebaseAssertSucceeds(promise);
  assertionCount += 1;
}

async function setup() {
  env = await initializeTestEnvironment({
    projectId: 'vinfast-rules-test',
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8'),
    },
  });
}

async function teardown() {
  if (env) await env.cleanup();
}

async function run() {
  await setup();
  try {
    const alice = env.authenticatedContext('alice');
    const bob = env.authenticatedContext('bob');
    const aliceDb = alice.firestore();
    const bobDb = bob.firestore();
    const validDraft = {
      schemaVersion: 1,
      state: 'localPending',
      revision: 0,
      operationId: 'operation-alice',
      name: 'Alice',
      catalogId: 'evo200',
      initialOdo: 0,
      shellyStatus: 'skipped',
      attemptCount: 0,
    };

    await assertSucceeds(setDoc(
      doc(aliceDb, 'users/alice/onboardingDrafts/current'),
      validDraft,
    ));
    await assertSucceeds(setDoc(
      doc(aliceDb, 'users/alice/onboardingDrafts/current'),
      { ...validDraft, finalizedAt: '2026-09-27T10:00:00.000Z' },
    ));
    await assertFails(setDoc(
      doc(aliceDb, 'users/alice/onboardingDrafts/current'),
      { ...validDraft, finalizedAt: true },
    ));
    await assertFails(setDoc(
      doc(bobDb, 'users/alice/onboardingDrafts/current'),
      validDraft,
    ));
    await assertFails(setDoc(
      doc(aliceDb, 'users/alice/onboardingDrafts/current'),
      { ...validDraft, unexpectedSecret: 'must fail' },
    ));
    await assertFails(setDoc(
      doc(aliceDb, 'users/alice/onboardingDrafts/current'),
      { ...validDraft, initialOdo: -1 },
    ));
    await assertFails(setDoc(
      doc(aliceDb, 'users/alice/onboardingDrafts/current'),
      { ...validDraft, attemptCount: 9 },
    ));
    await assertFails(setDoc(
      doc(aliceDb, 'Vehicles/vehicle-forged-by-client'),
      { ownerUid: 'alice', vehicleName: 'Forged' },
    ));
    await assertSucceeds(setDoc(
      doc(aliceDb, 'users/alice'),
      { uid: 'alice', name: 'Alice' },
    ));
    await assertFails(updateDoc(
      doc(aliceDb, 'users/alice'),
      { onboardingCompletedAt: 'client-forged' },
    ));

    await env.withSecurityRulesDisabled(async (context) => {
      const adminDb = context.firestore();
      await setDoc(doc(adminDb, 'Vehicles/vehicle-alice'), {
        ownerUid: 'alice', isDeleted: false, isArchived: false,
      });
      await setDoc(doc(adminDb, 'Vehicles/vehicle-bob'), {
        ownerUid: 'bob', isDeleted: false, isArchived: false,
      });
    });

    await assertSucceeds(setDoc(doc(aliceDb, 'TripLogs/trip-alice'), {
      ownerUid: 'alice', vehicleId: 'vehicle-alice', isDeleted: false,
    }));
    await assertFails(setDoc(doc(aliceDb, 'TripLogs/trip-cross-vehicle'), {
      ownerUid: 'alice', vehicleId: 'vehicle-bob', isDeleted: false,
    }));
    await assertFails(updateDoc(doc(aliceDb, 'TripLogs/trip-alice'), {
      ownerUid: 'bob',
    }));

    const reminder = {id: 'qa-reminder', uid: 'alice', vehicleId: 'vehicle-alice',
      title: 'Bảo dưỡng phanh', kind: 'maintenance', dueDate: '2026-11-20T00:00:00.000',
      timezone: 'Asia/Ho_Chi_Minh', reminderDays: [7, 1], revision: 1,
      pendingSync: false, notificationsEnabled: false};
    await assertSucceeds(setDoc(doc(aliceDb, 'users/alice/reminders/qa-reminder'), reminder));
    await assertFails(getDocs(collection(bobDb, 'users/alice/reminders')));
    await assertFails(setDoc(doc(aliceDb, 'users/alice/reminders/qa-foreign'), {...reminder, id: 'qa-foreign', vehicleId: 'vehicle-bob'}));
    await assertFails(updateDoc(doc(aliceDb, 'users/alice/reminders/qa-reminder'), {uid: 'bob', revision: 2}));
    await assertFails(updateDoc(doc(aliceDb, 'users/alice/reminders/qa-reminder'), {revision: 2, cloudAuthKey: 'not-a-real-key'}));
    await assertSucceeds(updateDoc(doc(aliceDb, 'users/alice/reminders/qa-reminder'), {title: 'Bảo dưỡng pin', revision: 2}));
    await assertFails(updateDoc(doc(aliceDb, 'users/alice/reminders/qa-reminder'), {revision: 2}));
    await assertSucceeds(updateDoc(doc(aliceDb, 'users/alice/reminders/qa-reminder'), {
      dueDate: '2026-12-20T00:00:00.000', state: 'active', operationId: 'edit-qa', revision: 3,
    }));
    await assertFails(updateDoc(doc(bobDb, 'users/alice/reminders/qa-reminder'), {revision: 4, state: 'cancelled'}));
    await assertFails(updateDoc(doc(aliceDb, 'users/alice/reminders/qa-reminder'), {revision: 4, state: 'unknown'}));
    await assertFails(updateDoc(doc(aliceDb, 'users/alice/reminders/qa-reminder'), {revision: 4, operationId: ''}));
    await assertSucceeds(updateDoc(doc(aliceDb, 'users/alice/reminders/qa-reminder'), {
      state: 'cancelled', operationId: 'cancel-qa', revision: 4,
    }));
    await assertFails(updateDoc(doc(aliceDb, 'users/alice/reminders/qa-reminder'), {revision: 5, state: 'active'}));
    await assertFails(setDoc(doc(aliceDb, 'users/alice/reminders/qa-cancelled'), {
      ...reminder, id: 'qa-cancelled', state: 'cancelled', operationId: 'invalid-create',
    }));
    await assertFails(deleteDoc(doc(aliceDb, 'users/alice/reminders/qa-reminder')));

    // Two independent authenticated runtimes, same account and expected
    // revision. A retry must not apply a stale edit after the other commits.
    const aliceSecondDb = env.authenticatedContext('alice').firestore();
    await assertSucceeds(setDoc(doc(aliceDb, 'users/alice/reminders/qa-race'), {
      ...reminder, id: 'qa-race', state: 'active', operationId: 'create-race',
    }));
    const mutate = (db, operation, state) => runTransaction(db, async tx => {
      const ref = doc(db, 'users/alice/reminders/qa-race');
      const existing = (await tx.get(ref)).data();
      if (existing.revision !== 1 || existing.state !== 'active') {
        throw new Error('reminderConflict');
      }
      tx.update(ref, {revision: 2, operationId: operation, state});
    });
    const race = await Promise.allSettled([
      mutate(aliceDb, 'edit-race', 'active'),
      mutate(aliceSecondDb, 'cancel-race', 'cancelled'),
    ]);
    if (race.filter(result => result.status === 'fulfilled').length !== 1 ||
        race.filter(result => result.status === 'rejected').length !== 1) {
      throw new Error('Concurrent reminder operations must have exactly one winner');
    }
    assertionCount += 1;
    const raceDoc = (await getDoc(doc(aliceDb, 'users/alice/reminders/qa-race'))).data();
    if (raceDoc.revision !== 2 || !['edit-race', 'cancel-race'].includes(raceDoc.operationId)) {
      throw new Error('Concurrent result has an unexpected revision/operation');
    }
    assertionCount += 1;

    // ChargeLogs queries must remain readable for the owner even when legacy
    // documents do not carry deletion flags.  The app filters presentation
    // flags client-side; rules must not require those fields in a query.
    await assertSucceeds(setDoc(
      doc(aliceDb, 'ChargeLogs/legacy-history'),
      {
        ownerUid: 'alice',
        source: 'shelly_smart_charging',
        vehicleId: 'vehicle-alice',
        startTime: new Date('2026-09-01T00:00:00Z'),
        sessionState: 'cancelled',
      },
    ));
    await assertSucceeds(setDoc(
      doc(aliceDb, 'ChargeLogs/current-history'),
      {
        ownerUid: 'alice',
        source: 'shelly_smart_charging',
        vehicleId: 'vehicle-alice',
        startTime: new Date('2026-09-02T00:00:00Z'),
        sessionState: 'interrupted',
        isDeleted: false,
      },
    ));
    const ownerHistory = query(
      collection(aliceDb, 'ChargeLogs'),
      where('ownerUid', '==', 'alice'),
      where('source', '==', 'shelly_smart_charging'),
      where('vehicleId', '==', 'vehicle-alice'),
    );
    await assertSucceeds(getDocs(ownerHistory));
    await assertFails(updateDoc(doc(aliceDb, 'ChargeLogs/legacy-history'), {
      ownerUid: 'bob',
    }));
    const crossAccountHistory = query(
      collection(bobDb, 'ChargeLogs'),
      where('ownerUid', '==', 'alice'),
    );
    await assertFails(getDocs(crossAccountHistory));

    await assertSucceeds(setDoc(
      doc(aliceDb, 'users/alice/appPreferences/ui'),
      {
        pendingAutoTours: ['tour_overview_v2'],
        dismissedTours: [],
        guideSchemaVersion: 2,
      },
    ));
    await assertFails(setDoc(
      doc(bobDb, 'users/alice/appPreferences/ui'),
      { pendingAutoTours: ['tour_overview_v2'] },
    ));
    await assertFails(setDoc(
      doc(aliceDb, 'shellyDeviceOwners/forged-device'),
      { ownerUid: 'alice', memberUids: ['alice', 'bob'], maxMembers: 2 },
    ));
    await assertFails(setDoc(
      doc(aliceDb, 'shellyConnectionCodes/ABCDEF'),
      { codeVersion: 999, isRevoked: false },
    ));
    await assertFails(setDoc(
      doc(aliceDb, 'users/alice/shellyDevices/forged-device'),
      { noLoadTestVerified: true, acknowledgedCodeVersion: 999 },
    ));
    await assertFails(setDoc(
      doc(aliceDb, 'smartChargeWorkerHealth/qa-staging'),
      { schemaVersion: 1, healthy: true, workerId: 'forged-worker', updatedAt: new Date() },
    ));
    await assertFails(getDoc(doc(aliceDb, 'smartChargeWorkerHealth/qa-staging')));
    await assertFails(setDoc(doc(aliceDb, 'smartChargeWorkerLeases/qa-staging'), {
      scope: 'qa-staging', workerId: 'forged-worker', epoch: 1, expiresAt: new Date(),
    }));
    await assertFails(getDoc(doc(aliceDb, 'smartChargeWorkerLeases/qa-staging')));
    console.log(`Firestore Rules: ${assertionCount} allow/deny assertions passed.`);
  } finally {
    await teardown();
  }
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
