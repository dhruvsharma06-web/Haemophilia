import assert from 'node:assert/strict';
import {initializeApp, deleteApp} from 'firebase/app';
import {getAuth, connectAuthEmulator, signInWithEmailAndPassword} from 'firebase/auth';
import {getFirestore, connectFirestoreEmulator, doc, collection, getDoc, getDocs, query, where, runTransaction, setDoc, writeBatch, serverTimestamp, Timestamp} from 'firebase/firestore';

const apps = [];
const runId = Date.now().toString();
async function login(role) {
  const app = initializeApp({apiKey: 'demo-local-only', projectId: 'demo-hemo-local'}, role);
  apps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, 'http://127.0.0.1:9099', {disableWarnings: true});
  const db = getFirestore(app);
  connectFirestoreEmulator(db, '127.0.0.1', 8089);
  const {user} = await signInWithEmailAndPassword(auth, `${role}@hemo.test`, 'LocalTest123!');
  return {db, uid: user.uid};
}
try {
  const admin = await login('admin');
  const doctor = await login('doctor');
  const patient = await login('patient');
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
  const exercise = {exercise: 'assisted_shoulder_flexion', targetCorrectReps: 3};
  await setDoc(doc(doctor.db, 'exerciseAssignments', patient.uid), {
    patientId: patient.uid, doctorId: doctor.uid, sessionName: 'Local test session',
    exercises: [exercise], exerciseProgress: [{...exercise, completedCorrectReps: 0, completedTotalReps: 0, status: 'pending'}],
    status: 'assigned', scheduledAt: serverTimestamp(), createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
    expiresAt: Timestamp.fromMillis(Date.now() + 86400000),
  });
  assert.equal((await getDoc(doc(patient.db, 'exerciseAssignments', patient.uid))).data().sessionName, 'Local test session');
  console.log('PASS: doctor assigns immediately and patient reads that prescription');
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
    batch.set(doc(actor.db, 'supportTickets', id), {userId: actor.uid, status: 'open', subject: 'Local test complaint', submitterName: 'Local Test', submitterRole: actor === doctor ? 'doctor' : 'patient', createdAt: serverTimestamp()});
    batch.set(doc(actor.db, 'supportTickets', id, 'messages', 'initial'), {senderId: actor.uid, text: 'Local test only', createdAt: serverTimestamp()});
    await batch.commit();
    await setDoc(doc(admin.db, 'supportTickets', id, 'messages', 'reply'), {senderId: admin.uid, text: 'Local test admin response', createdAt: serverTimestamp()});
    assert.equal((await getDoc(doc(actor.db, 'supportTickets', id, 'messages', 'reply'))).data().senderId, admin.uid);
  }
  console.log('PASS: patient and doctor Contact Admin tickets accept admin replies');
} finally {
  await Promise.all(apps.map(deleteApp));
}
