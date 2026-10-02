"""Integration checks against the local demo Firestore emulator only."""
import os
import unittest
from inspect import unwrap
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from uuid import uuid4
from unittest.mock import patch
from google.auth.credentials import AnonymousCredentials
from google.cloud.firestore import Client
import main


@unittest.skipUnless(os.environ.get('FIRESTORE_EMULATOR_HOST') == '127.0.0.1:8089', 'Start the local demo Firestore emulator first.')
class ServerEmulatorTests(unittest.TestCase):
    def setUp(self):
        self.db = Client(project='demo-hemo-workflow', credentials=AnonymousCredentials())
        self.db_patch = patch.object(main, '_db', lambda: self.db)
        self.db_patch.start()
        self.addCleanup(self.db_patch.stop)
        self.now = datetime.now(timezone.utc)
        self.suffix = uuid4().hex
        self.patient = 'P' + self.suffix
        self.doctor = 'D' + self.suffix
        self.patient_ref = self.db.collection('users').document(self.patient)
        self.patient_ref.set({'role':'patient','doctorId':self.doctor,'accountActive':True,'language':'hi','fcmTokens':['test-token']})
        self.db.collection('users').document(self.doctor).set({'role':'doctor','isApproved':True,'accountActive':True})
        self.assignment = self.db.collection('exerciseAssignments').document(self.patient)
        self.schedule = self.db.collection('exerciseSchedules').document(self.suffix)
        self.schedule.set({'patientId':self.patient,'doctorId':self.doctor,'status':'scheduled','seriesId':self.suffix,'scheduledAt':self.now-timedelta(minutes=1),'expiresAt':self.now+timedelta(hours=1),'sessionName':'Demo exercise','exercises':[{'exercise':'assisted_shoulder_flexion','targetCorrectReps':3}], 'exerciseProgress':[{'exercise':'assisted_shoulder_flexion','completedTotalReps':0,'completedCorrectReps':0}]})

    def test_activation_transaction_creates_one_assignment_and_notification(self):
        main._activate(self.db.transaction(),self.schedule,self.now)
        main._activate(self.db.transaction(),self.schedule,self.now)
        self.assertEqual(self.assignment.get().to_dict()['scheduleId'],self.suffix)
        self.assertEqual(self.schedule.get().to_dict()['status'],'activated')
        notices=list(self.patient_ref.collection('notifications').stream())
        self.assertEqual(len(notices),1)
        self.assertIn('सत्र',notices[0].to_dict()['title'])

    def test_active_assignment_is_not_overwritten(self):
        self.assignment.set({'status':'paused','sessionId':'existing','totalCompletedReps':7})
        main._activate(self.db.transaction(),self.schedule,self.now)
        self.assertEqual(self.assignment.get().to_dict()['totalCompletedReps'],7)
        self.assertEqual(self.schedule.get().to_dict()['status'],'scheduled')

    def test_transfer_routing_and_old_schedule_cancellation_use_current_profile(self):
        session=self.db.collection('assessmentSessions').document(self.patient+'_session')
        session.set({'patientId':self.patient,'doctorId':self.doctor,'status':'paused','totalReps':7})
        self.patient_ref.update({'doctorId':'replacement'})
        main._route_session(self.db.transaction(),session,self.patient)
        main._cancel_old_schedule(self.db.transaction(),self.schedule,self.patient)
        result=session.get().to_dict()
        self.assertEqual(result['doctorId'],'replacement')
        self.assertEqual(result['originalDoctorId'],self.doctor)
        self.assertEqual(result['totalReps'],7)
        self.assertEqual(self.schedule.get().to_dict()['status'],'cancelled')

    def test_report_transaction_preserves_cumulative_totals_and_does_not_loop(self):
        session_id=self.patient+'_session'
        session=self.db.collection('assessmentSessions').document(session_id)
        session.set({'patientId':self.patient,'doctorId':self.doctor,'status':'paused','totalReps':7,'totalCorrectReps':5})
        for number in range(1,8):
            self.patient_ref.collection('assessments').document(str(number)).set({'sessionId':session_id,'repNumber':number,'form':'correct' if number<=5 else 'incorrect','score':80,'rangeOfMotion':95})
        main._refresh_report(self.db.transaction(),session)
        saved=session.get()
        self.assertEqual(saved.to_dict()['report']['totalReps'],7)
        self.assertEqual(saved.to_dict()['report']['averageScore'],80)
        main._refresh_report(self.db.transaction(),session)
        self.assertEqual(session.get().update_time,saved.update_time)

    def test_retry_notification_does_not_resend_successful_tokens(self):
        notice=self.patient_ref.collection('notifications').document('retry')
        notice.set({'data':{'type':'support','ticketId':'demo'},'pushStatus':'retry','deliveredTokens':['already-sent']})
        self.patient_ref.update({'fcmTokens':['already-sent','retry-token']})
        event=SimpleNamespace(data=notice.get(),params={'userId':self.patient,'notificationId':'retry'})
        result=SimpleNamespace(responses=[SimpleNamespace(success=True)])
        with patch.object(main.messaging,'send_each_for_multicast',return_value=result) as sender:
            main.dispatch_notification.__wrapped__(event)
            self.assertEqual(sender.call_args.args[0].tokens,['retry-token'])
            main.dispatch_notification.__wrapped__(event)
            self.assertEqual(sender.call_count,1)
        self.assertEqual(notice.get().to_dict()['pushStatus'],'sent')

    def test_all_firestore_event_manifests_enable_retries(self):
        for name in ('dispatch_notification','notify_support_reply','synchronize_patient_transfer','generate_session_report','refresh_report_after_rep'):
            self.assertTrue(getattr(main,name).__firebase_endpoint__.eventTrigger['retry'])

    def test_doctor_creation_rejects_non_admin_without_creating_auth_user(self):
        request=SimpleNamespace(auth=SimpleNamespace(uid=self.patient),data={})
        with patch.object(main.auth,'create_user') as create:
            with self.assertRaises(main.https_fn.HttpsError):
                unwrap(main.create_doctor_account)(request)
            create.assert_not_called()

    def test_admin_doctor_creation_is_idempotent_and_stores_no_password(self):
        self.patient_ref.update({'role':'admin'})
        data={'name':'Doctor Example','email':'doctor@example.com','phoneNumber':'1234567890','registrationNumber':'REG-123','qualification':'MPT','specialization':'Physiotherapy','hospital':'Example hospital','password':'example-only-password','requestId':self.suffix}
        request=SimpleNamespace(auth=SimpleNamespace(uid=self.patient),data=data)
        with patch.object(main.auth,'create_user') as create:
            first=unwrap(main.create_doctor_account)(request)
            second=unwrap(main.create_doctor_account)(request)
            self.assertEqual(first,second)
            self.assertEqual(create.call_count,1)
        profile=self.db.collection('users').document(first['uid']).get().to_dict()
        self.assertNotIn('password',profile)
        self.assertNotIn('consentVersion',profile)
        self.assertEqual(profile['role'],'doctor')


if __name__=='__main__':
    unittest.main()
