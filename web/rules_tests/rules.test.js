const fs = require('node:fs');
const path = require('node:path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const { doc, setDoc, updateDoc } = require('firebase/firestore');

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
      doc(alice.firestore(), 'users/alice/onboardingDrafts/current'),
      validDraft,
    ));
    await assertFails(setDoc(
      doc(bob.firestore(), 'users/alice/onboardingDrafts/current'),
      validDraft,
    ));
    await assertFails(setDoc(
      doc(alice.firestore(), 'users/alice/onboardingDrafts/current'),
      { ...validDraft, unexpectedSecret: 'must fail' },
    ));
    await assertFails(setDoc(
      doc(alice.firestore(), 'users/alice/onboardingDrafts/current'),
      { ...validDraft, initialOdo: -1 },
    ));
    await assertFails(setDoc(
      doc(alice.firestore(), 'users/alice/onboardingDrafts/current'),
      { ...validDraft, attemptCount: 9 },
    ));
    await assertFails(setDoc(
      doc(alice.firestore(), 'Vehicles/vehicle-forged-by-client'),
      { ownerUid: 'alice', vehicleName: 'Forged' },
    ));
    await assertSucceeds(setDoc(
      doc(alice.firestore(), 'users/alice'),
      { uid: 'alice', name: 'Alice' },
    ));
    await assertFails(updateDoc(
      doc(alice.firestore(), 'users/alice'),
      { onboardingCompletedAt: 'client-forged' },
    ));
  } finally {
    await teardown();
  }
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
