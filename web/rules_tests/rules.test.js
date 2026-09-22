const fs = require('node:fs');
const path = require('node:path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const {
  collection,
  doc,
  getDocs,
  query,
  setDoc,
  updateDoc,
  where,
} = require('firebase/firestore');

let env;

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
  } finally {
    await teardown();
  }
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
