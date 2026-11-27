import assert from 'node:assert/strict';
import {initializeApp, deleteApp} from 'firebase/app';
import {getAuth, connectAuthEmulator, signInWithEmailAndPassword} from 'firebase/auth';
import {getStorage, connectStorageEmulator, ref, uploadBytes, getBytes} from 'firebase/storage';
import {getFirestore, connectFirestoreEmulator, doc, collection, getDoc, getDocs, query, where, runTransaction, setDoc, writeBatch, serverTimestamp, Timestamp} from 'firebase/firestore';

const apps = [];
const runId = Date.now().toString();
async function login(role, email = `${role}@hemo.test`, password = 'LocalTest123!') {
  const app = initializeApp({apiKey: 'demo-local-only', projectId: 'demo-hemo-local'}, role);
  apps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, 'http://127.0.0.1:9099', {disableWarnings: true});
  const db = getFirestore(app);
  connectFirestoreEmulator(db, '127.0.0.1', 8089);
  const {user} = await signInWithEmailAndPassword(auth, email, password);
  return {app, db, uid: user.uid};
}
try {
  const admin = await login('admin');
  const doctor = await login('doctor', process.env.HEMO_DEMO_DOCTOR_EMAIL, process.env.HEMO_DEMO_PASSWORD);
  const patient = await login('patient', process.env.HEMO_DEMO_PATIENT_EMAIL, process.env.HEMO_DEMO_PASSWORD);
  if (process.env.FIREBASE_STORAGE_EMULATOR_HOST) {
    const pending = await login('pending');
    const evidence = new Uint8Array(Buffer.from('%PDF-1.4\nDemo document\n%%EOF'));
    const path = 'doctor_documents/' + pending.uid + '/registrationCert.pdf';
    function documentRef(actor) {
      const storage = getStorage(actor.app, 'gs://demo-hemo-local.appspot.com');
      connectStorageEmulator(storage, '127.0.0.1', 9199);
      return ref(storage, path);
    }
    await uploadBytes(documentRef(pending), evidence, {contentType: 'application/pdf'});
    await setDoc(doc(pending.db, 'users', pending.uid), {registrationCertPath: path,
      registrationCertName: 'Demo registration.pdf'}, {merge: true});
    const application = doc(admin.db, 'users', pending.uid);
    assert.equal((await getDoc(application)).data().registrationCertPath, path);
    assert.deepEqual(new Uint8Array(await getBytes(documentRef(admin))), evidence);
    await assert.rejects(getBytes(documentRef(patient)), {code: 'storage/unauthorized'});
    await setDoc(application, {role: 'doctor', isApproved: true}, {merge: true});
    assert.equal((await getDoc(doc(pending.db, 'users', pending.uid))).data().role, 'doctor');
    console.log('PASS: applicant uploads a document, admin reviews and approves, patient access is denied');
  }
  await runTransaction(admin.db, async tx => {
    const user = doc(admin.db, 'users', patient.uid);
    await tx.get(doc(admin.db, 'users', admin.uid));
    await tx.get(user);
    await tx.get(doc(admin.db, 'exerciseAssignments', patient.uid));
    await tx.get(doc(admin.db, 'users', doctor.uid));
    tx.update(user, {doctorId: doctor.uid, accountActive: true, status: 'approved', approvedBy: admin.uid, approvalUpdatedAt: serverTimestamp()});
    tx.set(doc(collection(admin.db, 'adminAudit')), {actorId: admin.uid, userId: patient.uid, action: 'local_assignment_test', createdAt: serverTimestamp()});
  });
  console.log('PASS: admin assigns patient with an atomic audit write');
  const patients = await getDocs(query(collection(doctor.db, 'users'), where('role', '==', 'patient'), where('doctorId', '==', doctor.uid)));
  assert(patients.docs.some(d => d.id === patient.uid));
  console.log('PASS: assigned patient is visible in doctor query');
  const exercises = [
    'assisted_shoulder_flexion', 'shoulder_rotation', 'assisted_elbow_flexion_v5',
    'elbow_flexion_extension', 'heel_slide', 'mini_squat', 'seated_knee_extension',
    'straight_leg_raise', 'terminal_knee_extension', 'squat',
  ].map((exercise, i) => ({exercise, order: i + 1, targetCorrectReps: 2}));
  const progress = exercises.map(e => ({...e, completedCorrectReps: 0, completedTotalReps: 0, status: 'pending'}));
  await setDoc(doc(doctor.db, 'exerciseAssignments', patient.uid), {
    patientId: patient.uid, doctorId: doctor.uid, sessionName: 'Local test session',
    exercises, exerciseProgress: progress,
    status: 'assigned', scheduledAt: serverTimestamp(), createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
    expiresAt: Timestamp.fromMillis(Date.now() + 3600000),
  });
  const assignment = doc(patient.db, 'exerciseAssignments', patient.uid);
  assert.deepEqual((await getDoc(assignment)).data().exercises, exercises);
  console.log('PASS: patient receives all ten prescribed exercises, in order, with the assigned targets');
  const sessionId = patient.uid + '_' + runId;
  const session = doc(patient.db, 'assessmentSessions', sessionId);
  const start = writeBatch(patient.db);
  start.set(session, {sessionId, patientId: patient.uid, doctorId: doctor.uid,
    practice: false, recordingConsentVersion: '2026-10-02-v1',
    safetyConfirmedAt: serverTimestamp(), startedAt: serverTimestamp(), status: 'active'});
  start.update(assignment, {sessionId, status: 'in_progress'});
  await start.commit();
  const pause = writeBatch(patient.db);
  pause.update(session, {status: 'paused', totalReps: 3, totalCorrectReps: 2});
  pause.update(assignment, {status: 'paused', totalCompletedReps: 3, completedCorrectReps: 2});
  await pause.commit();
  const resume = writeBatch(patient.db);
  resume.update(session, {status: 'active', resumedAt: serverTimestamp()});
  resume.update(assignment, {status: 'in_progress'});
  await resume.commit();
  assert.equal((await getDoc(session)).data().totalCorrectReps, 2);
  assert.equal((await getDoc(assignment)).data().sessionId, sessionId);
  console.log('PASS: pausing and resuming keeps progress under the same session');
  // Synthetic outcomes exercise persistence and review. Camera behavior is tested separately.
  const completed = progress.map(e => ({...e, completedCorrectReps: 2, completedTotalReps: 3, status: 'completed'}));
  const finish = writeBatch(patient.db);
  finish.update(session, {status: 'completed', exercises: completed, totalCorrectReps: 20, totalReps: 30});
  finish.update(assignment, {status: 'completed', exerciseProgress: completed,
    completedCorrectReps: 20, totalCompletedReps: 30, completedAt: serverTimestamp()});
  await finish.commit();
  const review = doc(doctor.db, 'assessmentSessions', sessionId);
  const record = (await getDoc(review)).data();
  assert.deepEqual(record.exercises, completed);
  assert.equal(record.totalReps, 30);
  assert.equal(record.totalCorrectReps, 20);
  await setDoc(review, {doctorFeedback: 'Demo review complete', doctorFeedbackBy: doctor.uid,
    doctorFeedbackAt: serverTimestamp()}, {merge: true});
  assert.equal((await getDoc(session)).data().doctorFeedback, 'Demo review complete');
  console.log('PASS: doctor reviews ten completed items and patient receives the feedback');
  const notificationId = `local_session_${runId}`;
  await setDoc(doc(doctor.db, 'users', patient.uid, 'notifications', notificationId), {
    senderId: doctor.uid, title: 'Exercise session available', body: 'Local test session is ready.',
    read: false, createdAt: serverTimestamp(), data: {type: 'session_assigned', patientId: patient.uid, doctorId: doctor.uid},
  });
  assert((await getDoc(doc(patient.db, 'users', patient.uid, 'notifications', notificationId))).exists());
  console.log('PASS: patient notification card data is accessible');
  const conversationId = `${patient.uid}_${doctor.uid}`;
  for (const actor of [patient, doctor]) {
    const batch = writeBatch(actor.db);
    batch.set(doc(actor.db, 'conversations', conversationId), {patientId: patient.uid, doctorId: doctor.uid, updatedAt: serverTimestamp()}, {merge: true});
    batch.set(doc(collection(actor.db, 'conversations', conversationId, 'messages')), {
      conversationId, patientId: patient.uid, doctorId: doctor.uid, senderId: actor.uid,
      text: 'Local workflow test message', createdAt: serverTimestamp(), read: false,
    });
    await batch.commit();
  }
  assert((await getDocs(collection(patient.db, 'conversations', conversationId, 'messages'))).size >= 2);
  console.log('PASS: patient and doctor exchange messages');
  for (const actor of [patient, doctor]) {
    const id = `local_help_${actor.uid}_${runId}`;
    const batch = writeBatch(actor.db);
    batch.set(doc(actor.db, 'supportTickets', id), {userId: actor.uid, status: 'open', category: 'Technical problem', submittedByName: 'Local Test', submittedByRole: actor === doctor ? 'doctor' : 'patient', createdAt: serverTimestamp(), updatedAt: serverTimestamp()});
    batch.set(doc(actor.db, 'supportTickets', id, 'messages', 'initial'), {senderId: actor.uid, text: 'Local test only', createdAt: serverTimestamp()});
    await batch.commit();
    await setDoc(doc(admin.db, 'supportTickets', id, 'messages', 'reply'), {senderId: admin.uid, text: 'Local test admin response', createdAt: serverTimestamp()});
    assert.equal((await getDoc(doc(actor.db, 'supportTickets', id, 'messages', 'reply'))).data().senderId, admin.uid);
    await setDoc(doc(admin.db, 'supportTickets', id), {status: 'resolved', resolvedBy: admin.uid,
      resolvedAt: serverTimestamp(), updatedAt: serverTimestamp()}, {merge: true});
    assert.equal((await getDoc(doc(actor.db, 'supportTickets', id))).data().status, 'resolved');
  }
  console.log('PASS: admin replies to and resolves patient and doctor grievances');
} finally {
  await Promise.all(apps.map(deleteApp));
}
