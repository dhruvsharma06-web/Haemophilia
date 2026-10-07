import { readFileSync } from 'node:fs';
import { before, after, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, collection, setDoc, getDoc, getDocs, query, where, updateDoc, writeBatch, serverTimestamp, Timestamp, documentId } from 'firebase/firestore';

let env;
const version='2026-10-02-v1';
const future=Timestamp.fromMillis(Date.now()+3600000);
const past=Timestamp.fromMillis(Date.now()-3600000);
const recent=Timestamp.fromMillis(Date.now()-900000);
const profile=(role,doctorId=null)=>({role, doctorId, email:`${role}@example.com`, accountActive:true, isApproved:role==='doctor', consentVersion:version, onboardingCompleted:true});
const db=(uid)=>env.authenticatedContext(uid,{email:`${uid}@example.com`}).firestore();
before(async()=>{env=await initializeTestEnvironment({projectId:'demo-hemo-workflow',firestore:{host:'127.0.0.1',port:8089,rules:readFileSync(process.env.HEMO_RULES_PATH || new URL('../firestore.rules',import.meta.url),'utf8')}});});
after(async()=>{await env.cleanup();});
beforeEach(async()=>{
 await env.clearFirestore();
 await env.withSecurityRulesDisabled(async(context)=>{
  const store=context.firestore(); const batch=writeBatch(store);
  for(const [id,data] of Object.entries({admin:profile('admin'),doctor:profile('doctor'),otherDoctor:profile('doctor'),pending:profile('pending_doctor'),patient:profile('patient','doctor'),otherPatient:profile('patient','otherDoctor'),inactive:{...profile('doctor'),accountActive:false},legacy:{role:'doctor',accountActive:true}}))batch.set(doc(store,'users',id),data);
  batch.set(doc(store,'exerciseAssignments','patient'),{patientId:'patient',doctorId:'doctor',sessionId:'patient_existing',assignmentId:'original',status:'assigned',scheduledAt:recent,expiresAt:future,exercises:[{exercise:'assisted_shoulder_flexion'}]});
  batch.set(doc(store,'assessmentSessions','patient_existing'),{sessionId:'patient_existing',patientId:'patient',doctorId:'doctor',status:'paused',practice:false,startedAt:past,totalReps:4,totalCorrectReps:3});
  batch.set(doc(store,'conversations','patient_doctor'),{patientId:'patient',doctorId:'doctor'});
  batch.set(doc(store,'conversations','patient_doctor','messages','existing'),{conversationId:'patient_doctor',patientId:'patient',doctorId:'doctor',senderId:'patient',text:'hello'});
  await batch.commit();
 });
});

test('new patient can create own consented profile; cannot create doctor/admin',async()=>{
 const store=db('newuser');const data={...profile('patient'),email:'newuser@example.com'};
 await assertSucceeds(setDoc(doc(store,'users','newuser'),data));
 await assertFails(updateDoc(doc(store,'users','newuser'),{role:'doctor',isApproved:true}));
 await assertFails(setDoc(doc(db('newadmin'),'users','newadmin'),{...data,email:'newadmin@example.com',role:'admin'}));
});
test('new pending doctor can register, mirror application; pending has no patient access',async()=>{
 const store=db('newdoctor');await assertSucceeds(setDoc(doc(store,'users','newdoctor'),{...profile('pending_doctor'),email:'newdoctor@example.com'}));
 await assertSucceeds(setDoc(doc(store,'doctorApplications','newdoctor'),{isApproved:false}));
 await assertFails(getDoc(doc(store,'users','patient')));
 await assertFails(getDoc(doc(db('pending'),'assessmentSessions','patient_existing')));
});
test('unapproved and inactive doctors cannot read records; existing approved legacy doctor remains supported',async()=>{
 await assertFails(getDoc(doc(db('inactive'),'users','patient')));
 await env.withSecurityRulesDisabled(c=>updateDoc(doc(c.firestore(),'users','doctor'),{isApproved:false}));
 await assertFails(getDoc(doc(db('doctor'),'users','patient')));
 await env.withSecurityRulesDisabled(c=>updateDoc(doc(c.firestore(),'users','patient'),{doctorId:'legacy'}));
 await assertSucceeds(getDoc(doc(db('legacy'),'users','patient')));
});
test('doctor patients query includes newly assigned patients with no exercise plan',async()=>{
 await assertSucceeds(getDocs(query(collection(db('doctor'),'users'),where('role','==','patient'),where('doctorId','==','doctor'))));
 await assertFails(getDocs(query(collection(db('doctor'),'users'),where('role','==','patient'))));
 await env.withSecurityRulesDisabled(c=>setDoc(doc(c.firestore(),'users','newAssignedPatient'),profile('patient','doctor')));
 await assertSucceeds(getDoc(doc(db('doctor'),'exerciseAssignments','newAssignedPatient')));
});
test('patient doctor picker only returns their current assigned doctor',async()=>{
 await assertSucceeds(getDocs(query(collection(db('patient'),'users'),where(documentId(),'==','doctor'))));
 await assertFails(getDocs(query(collection(db('patient'),'users'),where('role','==','doctor'))));
});
test('doctor can review assigned records; unrelated patient/doctor cannot',async()=>{
 await assertSucceeds(getDoc(doc(db('doctor'),'assessmentSessions','patient_existing')));
 await assertSucceeds(getDocs(query(collection(db('doctor'),'assessmentSessions'),where('patientId','==','patient'))));
 await assertFails(getDoc(doc(db('otherDoctor'),'assessmentSessions','patient_existing')));
 await assertFails(getDoc(doc(db('otherPatient'),'assessmentSessions','patient_existing')));
});
test('transfer immediately revokes previous doctor and exposes full history to new doctor',async()=>{
 await assertSucceeds(updateDoc(doc(db('admin'),'users','patient'),{doctorId:'otherDoctor'}));
 await assertFails(getDoc(doc(db('doctor'),'assessmentSessions','patient_existing')));
 await assertSucceeds(getDoc(doc(db('otherDoctor'),'assessmentSessions','patient_existing')));
 await assertFails(getDocs(collection(db('doctor'),'conversations','patient_doctor','messages')));
});
test('patient cannot change routing, role, approval or server report',async()=>{
 const store=db('patient');
 for(const change of [{doctorId:'otherDoctor'},{role:'admin'},{isApproved:true},{accountActive:false}]) await assertFails(updateDoc(doc(store,'users','patient'),change));
 await assertFails(updateDoc(doc(store,'assessmentSessions','patient_existing'),{report:{totalReps:999}}));
 await assertFails(updateDoc(doc(store,'assessmentSessions','patient_existing'),{doctorId:'otherDoctor'}));
});
test('patients can read their schedules but cannot activate future or unrelated occurrences',async()=>{
 const store=db('doctor');const data={patientId:'patient',doctorId:'doctor',seriesId:'series',sessionName:'Morning',exercises:[{exercise:'assisted_shoulder_flexion',targetCorrectReps:3}],exerciseProgress:[],scheduledAt:future,expiresAt:Timestamp.fromMillis(future.toMillis()+3600000),status:'scheduled',createdAt:serverTimestamp()};
 await assertSucceeds(setDoc(doc(store,'exerciseSchedules','valid'),data));
 await assertSucceeds(getDoc(doc(db('patient'),'exerciseSchedules','valid')));
 await assertFails(getDoc(doc(db('otherPatient'),'exerciseSchedules','valid')));
 await assertFails(updateDoc(doc(db('patient'),'exerciseSchedules','valid'),{status:'activated',updatedAt:serverTimestamp()}));
 await assertFails(setDoc(doc(db('otherDoctor'),'exerciseSchedules','wrong'),data));
 await assertFails(setDoc(doc(store,'exerciseSchedules','past'),{...data,scheduledAt:past}));
 await assertFails(updateDoc(doc(store,'exerciseSchedules','valid'),{status:'activated'}));
 await assertSucceeds(updateDoc(doc(store,'exerciseSchedules','valid'),{status:'cancelled',updatedAt:serverTimestamp()}));
});
test('camera session needs consent, no-bleeding affirmation and a due assignment',async()=>{
 const store=db('patient'); const payload={sessionId:'patient_new',patientId:'patient',doctorId:'doctor',status:'active',practice:false,safetyConfirmedAt:serverTimestamp(),recordingConsentVersion:version,startedAt:serverTimestamp()};
 await env.withSecurityRulesDisabled(c=>updateDoc(doc(c.firestore(),'exerciseAssignments','patient'),{sessionId:''}));
 await assertSucceeds(getDoc(doc(store,'assessmentSessions','patient_new')));
 await assertFails(setDoc(doc(store,'assessmentSessions','patient_new'),{...payload,safetyConfirmedAt:null}));
 const start=writeBatch(store);
 start.set(doc(store,'assessmentSessions','patient_new'),payload);
 start.update(doc(store,'exerciseAssignments','patient'),{status:'in_progress',sessionId:'patient_new'});
 await assertSucceeds(start.commit());
 await env.withSecurityRulesDisabled(c=>updateDoc(doc(c.firestore(),'exerciseAssignments','patient'),{scheduledAt:future}));
 await assertFails(setDoc(doc(store,'assessmentSessions','patient_future'),{...payload,sessionId:'patient_future'}));
 await assertFails(setDoc(doc(store,'assessmentSessions','patient_practice'),{...payload,sessionId:'patient_practice',practice:true}));
});
test('session pause/resume keeps totals under the same record; completed sessions cannot restart',async()=>{
 const store=db('patient'); const ref=doc(store,'assessmentSessions','patient_existing');
 await assertSucceeds(updateDoc(ref,{status:'active',resumedAt:serverTimestamp(),totalReps:4}));
 await assertSucceeds(updateDoc(ref,{status:'paused',totalReps:7,totalCorrectReps:5}));
 assert.equal((await getDoc(ref)).data().totalReps,7);
 await assertSucceeds(updateDoc(ref,{status:'completed',totalReps:9}));
 await assertFails(updateDoc(ref,{status:'active'}));
});
test('assignment and session pause batch commits together and preserves counts',async()=>{
 const store=db('patient');const batch=writeBatch(store);
 batch.update(doc(store,'exerciseAssignments','patient'),{status:'paused',sessionId:'patient_existing',totalCompletedReps:7});
 batch.update(doc(store,'assessmentSessions','patient_existing'),{status:'paused',totalReps:7,totalCorrectReps:5});
 await assertSucceeds(batch.commit());
 assert.equal((await getDoc(doc(store,'exerciseAssignments','patient'))).data().totalCompletedReps,7);
 assert.equal((await getDoc(doc(store,'assessmentSessions','patient_existing'))).data().totalReps,7);
});
test('patient cannot start or resume any future or expired session',async()=>{
 const ref=doc(db('patient'),'exerciseAssignments','patient');
 await env.withSecurityRulesDisabled(c=>updateDoc(doc(c.firestore(),'exerciseAssignments','patient'),{scheduledAt:future}));
 await assertFails(updateDoc(ref,{status:'in_progress'}));
 await env.withSecurityRulesDisabled(c=>updateDoc(doc(c.firestore(),'exerciseAssignments','patient'),{scheduledAt:past,expiresAt:past}));
 await assertFails(updateDoc(ref,{status:'in_progress'}));
 await env.withSecurityRulesDisabled(c=>updateDoc(doc(c.firestore(),'exerciseAssignments','patient'),{status:'paused'}));
 await assertFails(updateDoc(ref,{status:'in_progress'}));
});
test('assigned pair can chat atomically; unrelated doctor cannot spoof or send',async()=>{
 const store=db('patient'); const batch=writeBatch(store);
 batch.set(doc(store,'conversations','patient_doctor','messages','new'),{conversationId:'patient_doctor',patientId:'patient',doctorId:'doctor',senderId:'patient',text:'question',createdAt:serverTimestamp()});
 batch.set(doc(store,'conversations','patient_doctor'),{patientId:'patient',doctorId:'doctor',lastMessage:'question'},{merge:true});
 await assertSucceeds(batch.commit());
 await assertFails(setDoc(doc(db('otherDoctor'),'conversations','patient_doctor','messages','spoof'),{conversationId:'patient_doctor',patientId:'patient',doctorId:'doctor',senderId:'otherDoctor',text:'bad'}));
});
test('support can create ticket and initial message together; only owner/admin can read/reply',async()=>{
 const store=db('patient');const batch=writeBatch(store);
 batch.set(doc(store,'supportTickets','help'),{userId:'patient',status:'open',category:'Doctor not responding'});
 batch.set(doc(store,'supportTickets','help','messages','first'),{senderId:'patient',text:'Please help',createdAt:serverTimestamp()});
 await assertSucceeds(batch.commit());
 await assertSucceeds(getDocs(collection(store,'supportTickets','help','messages')));
 await assertFails(getDoc(doc(db('otherPatient'),'supportTickets','help')));
 await assertSucceeds(setDoc(doc(db('admin'),'supportTickets','help','messages','reply'),{senderId:'admin',text:'We will help'}));
 await assertFails(updateDoc(doc(store,'supportTickets','help'),{status:'closed'}));
 await assertSucceeds(updateDoc(doc(db('admin'),'supportTickets','help'),{status:'closed',closedAt:serverTimestamp()}));
});
test('notifications can only reach assigned recipients and cannot fake successful delivery',async()=>{
 const data={senderId:'patient',title:'New message',body:'Open app',read:false,data:{type:'new_message'}};
 await assertSucceeds(setDoc(doc(db('patient'),'users','doctor','notifications','notice'),data));
 await assertFails(setDoc(doc(db('patient'),'users','otherDoctor','notifications','notice'),data));
 await assertFails(updateDoc(doc(db('doctor'),'users','doctor','notifications','notice'),{pushStatus:'sent'}));
 await assertSucceeds(updateDoc(doc(db('doctor'),'users','doctor','notifications','notice'),{read:true}));
});

test('legacy paused sessions can initialize missing resume metadata once',async()=>{
 const ref=doc(db('patient'),'assessmentSessions','patient_legacy');
 await env.withSecurityRulesDisabled(c=>setDoc(doc(c.firestore(),'assessmentSessions','patient_legacy'),{sessionId:'patient_legacy',patientId:'patient',doctorId:'doctor',status:'paused',totalReps:4}));
 await env.withSecurityRulesDisabled(c=>updateDoc(doc(c.firestore(),'exerciseAssignments','patient'),{sessionId:'patient_legacy'}));
 await assertSucceeds(updateDoc(ref,{status:'active',startedAt:serverTimestamp(),practice:false,totalReps:4}));
 await assertFails(updateDoc(ref,{startedAt:past}));
 await assertFails(updateDoc(ref,{practice:true}));
 assert.equal((await getDoc(ref)).data().totalReps,4);
});

test('patient activates a due schedule atomically; cannot overwrite paused work or alter prescriptions',async()=>{
 const schedule={patientId:'patient',doctorId:'doctor',sessionName:'Due session',exercises:[{exercise:'assisted_shoulder_flexion',targetCorrectReps:3}],exerciseProgress:[],scheduledAt:recent,expiresAt:future,status:'scheduled'};
 await env.withSecurityRulesDisabled(async(c)=>{
  await setDoc(doc(c.firestore(),'exerciseSchedules','due'),schedule);
  await updateDoc(doc(c.firestore(),'exerciseAssignments','patient'),{status:'paused'});
 });
 function activate(extra={}) {
  const store=db('patient'); const batch=writeBatch(store);
  batch.set(doc(store,'exerciseAssignments','patient'),{...schedule,sourceScheduleId:'due',scheduleId:'due',status:'assigned',createdAt:serverTimestamp(),updatedAt:serverTimestamp(),...extra});
  batch.update(doc(store,'exerciseSchedules','due'),{status:'activated',updatedAt:serverTimestamp()});
  batch.set(doc(store,'users','patient','notifications','schedule_due'),{senderId:'patient',read:false,createdAt:serverTimestamp(),title:'Exercise session available',data:{type:'session_assigned',patientId:'patient',doctorId:'doctor',scheduleId:'due'}});
  return batch.commit();
 }
 await assertFails(activate());
 await env.withSecurityRulesDisabled(c=>updateDoc(doc(c.firestore(),'exerciseAssignments','patient'),{status:'completed'}));
 await assertFails(activate({exercises:[{exercise:'elbow_flexion',targetCorrectReps:100}]}));
 await assertSucceeds(activate());
 assert.equal((await getDoc(doc(db('patient'),'exerciseAssignments','patient'))).data().sourceScheduleId,'due');
 await assertFails(activate());
});
test('unpublished or expired schedules cannot be activated and patients cannot clear admin decisions',async()=>{
 await env.withSecurityRulesDisabled(async(c)=>{
  const store=c.firestore();
  await setDoc(doc(store,'exerciseScheduleSeries','unfinished'),{patientId:'patient',doctorId:'doctor',status:'preparing'});
  await setDoc(doc(store,'exerciseSchedules','unpublished'),{patientId:'patient',doctorId:'doctor',seriesId:'unfinished',managedSeries:true,sessionName:'Later',exercises:[],exerciseProgress:[],scheduledAt:past,expiresAt:future,status:'scheduled'});
  await updateDoc(doc(store,'exerciseAssignments','patient'),{status:'completed'});
 });
 const store=db('patient'); const schedule=(await getDoc(doc(store,'exerciseSchedules','unpublished'))).data();
 const batch=writeBatch(store);
 const {seriesId,managedSeries,...payload}=schedule;
 batch.set(doc(store,'exerciseAssignments','patient'),{...payload,sourceScheduleId:'unpublished',status:'assigned',createdAt:serverTimestamp(),updatedAt:serverTimestamp()});
 batch.update(doc(store,'exerciseSchedules','unpublished'),{status:'activated',updatedAt:serverTimestamp()});
 await assertFails(batch.commit());
 await env.withSecurityRulesDisabled(async(c)=>{
  await updateDoc(doc(c.firestore(),'exerciseScheduleSeries','unfinished'),{status:'ready'});
  await updateDoc(doc(c.firestore(),'exerciseSchedules','unpublished'),{expiresAt:past});
 });
 const expired=writeBatch(store);
 expired.set(doc(store,'exerciseAssignments','patient'),{...payload,expiresAt:past,sourceScheduleId:'unpublished',status:'assigned',createdAt:serverTimestamp(),updatedAt:serverTimestamp()});
 expired.update(doc(store,'exerciseSchedules','unpublished'),{status:'activated',updatedAt:serverTimestamp()});
 await assertFails(expired.commit());
 await assertFails(updateDoc(doc(store,'users','patient'),{rejectionReason:'',removedAt:serverTimestamp()}));
 await assertSucceeds(updateDoc(doc(db('admin'),'users','patient'),{status:'rejected',accountActive:false,rejectionReason:'Review required'}));
 await assertFails(getDoc(doc(store,'exerciseAssignments','patient')));
});

test('expired paused assignment and recording are archived atomically and cannot resume',async()=>{
 await env.withSecurityRulesDisabled(c=>updateDoc(doc(c.firestore(),'exerciseAssignments','patient'),{status:'paused',scheduledAt:past}));
 const store=db('patient'), ref=doc(store,'exerciseAssignments','patient');
 const data=(await getDoc(ref)).data();
 const batch=writeBatch(store);
 const terminal={status:'expired',expiredAt:serverTimestamp(),updatedAt:serverTimestamp()};
 batch.set(doc(store,'exerciseAssignments','patient','archive','original'),{...data,...terminal,archiveId:'original',archivedAt:serverTimestamp()});
 batch.update(ref,terminal);
 batch.update(doc(store,'assessmentSessions','patient_existing'),{...terminal,lastUpdatedAt:serverTimestamp()});
 await assertSucceeds(batch.commit());
 await assertFails(updateDoc(ref,{status:'in_progress'}));
 await assertFails(updateDoc(doc(store,'assessmentSessions','patient_existing'),{status:'active'}));
 await assertSucceeds(getDoc(doc(store,'exerciseAssignments','patient','archive','original')));
 await assertFails(updateDoc(doc(store,'exerciseAssignments','patient','archive','original'),{status:'assigned'}));
});

test('patient cannot expire a fresh session or extend its deadline',async()=>{
 const ref=doc(db('patient'),'exerciseAssignments','patient');
 await assertFails(updateDoc(ref,{status:'expired',expiredAt:serverTimestamp(),updatedAt:serverTimestamp()}));
 await assertFails(updateDoc(ref,{expiresAt:Timestamp.fromMillis(Date.now()+86400000)}));
 await assertFails(updateDoc(ref,{sessionId:'patient_different'}));
});

test('assigned doctor cancels paused work and recording; queued patient progress cannot resurrect it',async()=>{
 await env.withSecurityRulesDisabled(c=>updateDoc(doc(c.firestore(),'exerciseAssignments','patient'),{status:'paused'}));
 const store=db('doctor'), ref=doc(store,'exerciseAssignments','patient'), data=(await getDoc(ref)).data();
 const terminal={status:'cancelled',cancelledBy:'doctor',cancelledAt:serverTimestamp(),updatedAt:serverTimestamp()};
 const batch=writeBatch(store);
 batch.set(doc(store,'exerciseAssignments','patient','archive','original'),{...data,...terminal,archiveId:'original',archivedAt:serverTimestamp()});
 batch.update(ref,terminal);
 batch.update(doc(store,'assessmentSessions','patient_existing'),{...terminal,lastUpdatedAt:serverTimestamp()});
 await assertSucceeds(batch.commit());
 await assertFails(updateDoc(doc(db('patient'),'exerciseAssignments','patient'),{status:'paused',totalCompletedReps:20}));
 await assertFails(updateDoc(doc(db('patient'),'assessmentSessions','patient_existing'),{status:'active'}));
 await assertFails(updateDoc(doc(db('otherDoctor'),'exerciseAssignments','patient'),terminal));
});

test('a new assignment does not permit updates to an old unfinished recording',async()=>{
 await env.withSecurityRulesDisabled(c=>updateDoc(doc(c.firestore(),'exerciseAssignments','patient'),{assignmentId:'new',sessionId:'patient_other'}));
 await assertFails(updateDoc(doc(db('patient'),'assessmentSessions','patient_existing'),{status:'active'}));
});
