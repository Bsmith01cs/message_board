// Firestore Security Rules tests for CSC 4360 Homework 02.
//
// These run against the local Firestore emulator on the isolated demo project
// below. They never touch a real Firebase project.

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import {
  doc,
  getDoc,
  getDocs,
  collection,
  setDoc,
  updateDoc,
  deleteDoc,
  serverTimestamp,
  Timestamp,
} from 'firebase/firestore';

const PROJECT_ID = 'demo-message-board-hw02';
const ALICE = 'alice-uid';
const BOB = 'bob-uid';

let testEnv;
let alice;
let bob;
let anon;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync('../firestore.rules', 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

after(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  alice = testEnv.authenticatedContext(ALICE).firestore();
  bob = testEnv.authenticatedContext(BOB).firestore();
  anon = testEnv.unauthenticatedContext().firestore();
});

/** Seeds data with rules disabled, so seeding never depends on the rules. */
async function seed(path, data) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), path), data);
  });
}

const aliceMessage = {
  text: 'Hello board',
  authorUid: ALICE,
  authorName: 'Alice Author',
  createdAt: Timestamp.fromDate(new Date('2026-01-01T09:00:00Z')),
  editedAt: null,
};

// What BoardService.postMessage actually writes.
const newMessageFrom = (uid) => ({
  text: 'Hello board',
  authorUid: uid,
  authorName: 'Alice Author',
  createdAt: serverTimestamp(),
  editedAt: null,
});

// What UserRecordService.saveProfile writes for a brand new user.
const newProfileFor = (uid) => ({
  uid,
  firstName: 'Alice',
  lastName: 'Author',
  role: 'member',
  registrationDateTime: serverTimestamp(),
});

describe('messages: reading', () => {
  beforeEach(async () => {
    await seed('messages/msg1', aliceMessage);
  });

  it('denies a signed-out read of a message', async () => {
    await assertFails(getDoc(doc(anon, 'messages/msg1')));
  });

  it('denies a signed-out query of the board', async () => {
    await assertFails(getDocs(collection(anon, 'messages')));
  });

  it('allows a signed-in read of a message', async () => {
    await assertSucceeds(getDoc(doc(alice, 'messages/msg1')));
  });

  it('allows a signed-in user to read the whole board, including others', async () => {
    await assertSucceeds(getDocs(collection(bob, 'messages')));
  });
});

describe('messages: creating', () => {
  it('allows the author to create their own message', async () => {
    await assertSucceeds(
      setDoc(doc(alice, 'messages/new1'), newMessageFrom(ALICE)),
    );
  });

  it('denies a forged authorUid', async () => {
    await assertFails(
      setDoc(doc(alice, 'messages/forged'), newMessageFrom(BOB)),
    );
  });

  it('denies a signed-out create', async () => {
    await assertFails(
      setDoc(doc(anon, 'messages/anon'), newMessageFrom(ALICE)),
    );
  });

  it('denies empty message text', async () => {
    await assertFails(
      setDoc(doc(alice, 'messages/empty'), {
        ...newMessageFrom(ALICE),
        text: '',
      }),
    );
  });

  it('denies a client-supplied createdAt instead of the server timestamp', async () => {
    await assertFails(
      setDoc(doc(alice, 'messages/faketime'), {
        ...newMessageFrom(ALICE),
        createdAt: Timestamp.fromDate(new Date('2020-01-01T00:00:00Z')),
      }),
    );
  });

  it('denies extra fields that the app never writes', async () => {
    await assertFails(
      setDoc(doc(alice, 'messages/extra'), {
        ...newMessageFrom(ALICE),
        pinned: true,
      }),
    );
  });
});

describe('messages: updating', () => {
  beforeEach(async () => {
    await seed('messages/msg1', aliceMessage);
  });

  it('allows the author to edit text and editedAt', async () => {
    await assertSucceeds(
      updateDoc(doc(alice, 'messages/msg1'), {
        text: 'Edited text',
        editedAt: serverTimestamp(),
      }),
    );
  });

  it('denies another user editing the message', async () => {
    await assertFails(
      updateDoc(doc(bob, 'messages/msg1'), {
        text: 'Hijacked',
        editedAt: serverTimestamp(),
      }),
    );
  });

  it('denies changing authorUid during an update', async () => {
    await assertFails(
      updateDoc(doc(alice, 'messages/msg1'), {
        text: 'Edited text',
        editedAt: serverTimestamp(),
        authorUid: BOB,
      }),
    );
  });

  it('denies changing createdAt during an update', async () => {
    await assertFails(
      updateDoc(doc(alice, 'messages/msg1'), {
        text: 'Edited text',
        editedAt: serverTimestamp(),
        createdAt: serverTimestamp(),
      }),
    );
  });

  it('denies changing authorName during an update', async () => {
    await assertFails(
      updateDoc(doc(alice, 'messages/msg1'), {
        text: 'Edited text',
        editedAt: serverTimestamp(),
        authorName: 'Someone Else',
      }),
    );
  });

  it('denies emptying the text during an update', async () => {
    await assertFails(
      updateDoc(doc(alice, 'messages/msg1'), {
        text: '',
        editedAt: serverTimestamp(),
      }),
    );
  });

  it('denies a signed-out update', async () => {
    await assertFails(
      updateDoc(doc(anon, 'messages/msg1'), {
        text: 'Edited text',
        editedAt: serverTimestamp(),
      }),
    );
  });
});

describe('messages: deleting', () => {
  beforeEach(async () => {
    await seed('messages/msg1', aliceMessage);
  });

  it('allows the author to delete their own message', async () => {
    await assertSucceeds(deleteDoc(doc(alice, 'messages/msg1')));
  });

  it('denies another user deleting the message', async () => {
    await assertFails(deleteDoc(doc(bob, 'messages/msg1')));
  });

  it('denies a signed-out delete', async () => {
    await assertFails(deleteDoc(doc(anon, 'messages/msg1')));
  });
});

describe('users: private profiles', () => {
  it('allows a user to read their own profile', async () => {
    await seed(`users/${ALICE}`, {
      uid: ALICE,
      firstName: 'Alice',
      lastName: 'Author',
      role: 'member',
      registrationDateTime: Timestamp.fromDate(new Date('2026-01-01T09:00:00Z')),
    });

    await assertSucceeds(getDoc(doc(alice, `users/${ALICE}`)));
  });

  it("denies reading another user's profile", async () => {
    await seed(`users/${BOB}`, {
      uid: BOB,
      firstName: 'Bob',
      lastName: 'Builder',
      role: 'member',
      registrationDateTime: Timestamp.fromDate(new Date('2026-01-01T09:00:00Z')),
    });

    await assertFails(getDoc(doc(alice, `users/${BOB}`)));
  });

  it('denies listing the users collection', async () => {
    await assertFails(getDocs(collection(alice, 'users')));
  });

  it('denies a signed-out profile read', async () => {
    await seed(`users/${ALICE}`, { uid: ALICE });
    await assertFails(getDoc(doc(anon, `users/${ALICE}`)));
  });

  it('allows creating your own valid profile', async () => {
    await assertSucceeds(
      setDoc(doc(alice, `users/${ALICE}`), newProfileFor(ALICE)),
    );
  });

  it("denies creating a profile at another user's uid", async () => {
    await assertFails(
      setDoc(doc(alice, `users/${BOB}`), newProfileFor(BOB)),
    );
  });

  it('denies a profile whose uid field does not match the document', async () => {
    await assertFails(
      setDoc(doc(alice, `users/${ALICE}`), newProfileFor(BOB)),
    );
  });

  it('denies claiming a privileged role at creation', async () => {
    await assertFails(
      setDoc(doc(alice, `users/${ALICE}`), {
        ...newProfileFor(ALICE),
        role: 'admin',
      }),
    );
  });

  it('denies a missing required field', async () => {
    const { lastName, ...withoutLastName } = newProfileFor(ALICE);
    await assertFails(
      setDoc(doc(alice, `users/${ALICE}`), withoutLastName),
    );
  });

  it('denies an empty name', async () => {
    await assertFails(
      setDoc(doc(alice, `users/${ALICE}`), {
        ...newProfileFor(ALICE),
        firstName: '',
      }),
    );
  });

  it('denies profile deletion', async () => {
    await seed(`users/${ALICE}`, newProfileFor(ALICE));
    await assertFails(deleteDoc(doc(alice, `users/${ALICE}`)));
  });
});

describe('users: completing and protecting a profile', () => {
  const originalRegistration = Timestamp.fromDate(
    new Date('2026-01-01T09:00:00Z'),
  );

  it('allows completing a profile that is missing a name', async () => {
    // What a failed registration write leaves behind.
    await seed(`users/${ALICE}`, {
      uid: ALICE,
      firstName: 'Alice',
      lastName: '',
      role: 'member',
      registrationDateTime: originalRegistration,
    });

    await assertSucceeds(
      setDoc(
        doc(alice, `users/${ALICE}`),
        { uid: ALICE, firstName: 'Alice', lastName: 'Author', role: 'member' },
        { merge: true },
      ),
    );
  });

  it('allows a merge write that supplies a first registration timestamp', async () => {
    await seed(`users/${ALICE}`, { uid: ALICE, firstName: 'Alice' });

    await assertSucceeds(
      setDoc(
        doc(alice, `users/${ALICE}`),
        {
          uid: ALICE,
          firstName: 'Alice',
          lastName: 'Author',
          role: 'member',
          registrationDateTime: serverTimestamp(),
        },
        { merge: true },
      ),
    );
  });

  it('denies rewriting an existing registration timestamp', async () => {
    await seed(`users/${ALICE}`, {
      uid: ALICE,
      firstName: 'Alice',
      lastName: 'Author',
      role: 'member',
      registrationDateTime: originalRegistration,
    });

    await assertFails(
      updateDoc(doc(alice, `users/${ALICE}`), {
        registrationDateTime: serverTimestamp(),
      }),
    );
  });

  it('denies escalating the role on an existing profile', async () => {
    await seed(`users/${ALICE}`, {
      uid: ALICE,
      firstName: 'Alice',
      lastName: 'Author',
      role: 'member',
      registrationDateTime: originalRegistration,
    });

    await assertFails(
      updateDoc(doc(alice, `users/${ALICE}`), { role: 'admin' }),
    );
  });

  it('denies changing the uid field on an existing profile', async () => {
    await seed(`users/${ALICE}`, {
      uid: ALICE,
      firstName: 'Alice',
      lastName: 'Author',
      role: 'member',
      registrationDateTime: originalRegistration,
    });

    await assertFails(
      updateDoc(doc(alice, `users/${ALICE}`), { uid: BOB }),
    );
  });

  it("denies repairing another user's profile", async () => {
    await seed(`users/${BOB}`, {
      uid: BOB,
      firstName: 'Bob',
      lastName: '',
      role: 'member',
      registrationDateTime: originalRegistration,
    });

    await assertFails(
      setDoc(
        doc(alice, `users/${BOB}`),
        { uid: BOB, firstName: 'Bob', lastName: 'Builder', role: 'member' },
        { merge: true },
      ),
    );
  });
});

describe('default deny', () => {
  it('denies reading an unrelated collection', async () => {
    await seed('challenges/today', { prompt: 'unrelated coursework' });
    await assertFails(getDoc(doc(alice, 'challenges/today')));
  });

  it('denies writing an unrelated collection', async () => {
    await assertFails(
      setDoc(doc(alice, 'challenges/today'), { prompt: 'hijack' }),
    );
  });

  it('denies a subcollection under a message', async () => {
    await assertFails(
      setDoc(doc(alice, 'messages/msg1/replies/r1'), { text: 'nope' }),
    );
  });

  it('denies a subcollection under a user profile', async () => {
    await assertFails(
      setDoc(doc(alice, `users/${ALICE}/secrets/s1`), { value: 'nope' }),
    );
  });

  it('keeps the rules file free of a catch-all allow', () => {
    const rules = readFileSync('../firestore.rules', 'utf8');
    assert.match(rules, /rules_version = '2'/);
    assert.ok(
      !/allow read, write: if true/.test(rules),
      'no blanket allow should exist',
    );
  });
});
