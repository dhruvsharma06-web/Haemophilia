import unittest
from datetime import datetime, timedelta, timezone
from workflow import activation_decision, build_session_report, notification_copy, notification_is_current


class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime(2026, 10, 2, 9, tzinfo=timezone.utc)
        self.schedule = {'status': 'scheduled', 'doctorId': 'doctor', 'scheduledAt': self.now, 'expiresAt': self.now + timedelta(hours=12)}
        self.patient = {'doctorId': 'doctor', 'accountActive': True}
        self.doctor = {'role': 'doctor', 'isApproved': True, 'accountActive': True}

    def decide(self, assignment=None, **overrides):
        return activation_decision({**self.schedule, **overrides}, self.patient, self.doctor, assignment, self.now)

    def test_due_schedule_activates(self):
        self.assertEqual(self.decide(), 'activate')

    def test_future_schedule_never_notifies_early(self):
        self.assertEqual(self.decide(scheduledAt=self.now + timedelta(minutes=1)), 'ignore')

    def test_expired_schedule_is_missed(self):
        self.assertEqual(self.decide(expiresAt=self.now), 'missed')

    def test_paused_and_active_sessions_are_not_overwritten(self):
        for status in ('paused', 'in_progress'):
            self.assertEqual(self.decide({'status': status, 'scheduledAt': self.now}), 'wait')

    def test_legacy_assignment_without_a_clock_cannot_block_forever(self):
        self.assertEqual(self.decide({'status': 'assigned'}), 'activate')
        self.assertEqual(self.decide({'status': 'assigned', 'createdAt': self.now}), 'wait')

    def test_all_unfinished_states_expire_at_original_start_plus_one_hour(self):
        for status in ('assigned', 'paused', 'in_progress'):
            self.assertEqual(self.decide({'status': status, 'scheduledAt': self.now - timedelta(hours=1),
                                          'expiresAt': self.now + timedelta(days=1)}), 'activate')
        self.assertEqual(self.decide(scheduledAt=self.now - timedelta(hours=1)), 'missed')

    def test_completed_or_expired_assignment_allows_next(self):
        self.assertEqual(self.decide({'status': 'completed'}), 'activate')
        self.assertEqual(self.decide({'status': 'assigned', 'expiresAt': self.now - timedelta(seconds=1)}), 'activate')

    def test_pending_inactive_removed_doctor_cancel(self):
        for field, value in [('role','pending_doctor'),('isApproved',False),('accountActive',False)]:
            self.doctor={'role':'doctor','isApproved':True,'accountActive':True,field:value}
            self.assertEqual(self.decide(), 'cancelled')

    def test_transferred_or_inactive_patient_cancels_old_schedule(self):
        self.patient['doctorId']='newDoctor'
        self.assertEqual(self.decide(), 'cancelled')
        self.patient={'doctorId':'doctor','accountActive':False}
        self.assertEqual(self.decide(), 'cancelled')

    def test_activated_schedule_cannot_activate_again(self):
        self.assertEqual(self.decide(status='activated'), 'ignore')

    def test_report_combines_reps_across_pauses_without_duplicates(self):
        rows=[{'repNumber':i,'form':'correct' if i % 2 else 'incorrect','score':80,'rangeOfMotion':90} for i in range(1,8)]
        report=build_session_report({'totalReps':7,'totalCorrectReps':4},rows+[rows[0]])
        self.assertEqual(report['totalReps'],7)
        self.assertEqual(report['correctReps'],4)
        self.assertEqual(report['recordedReps'],7)
        self.assertEqual(report['averageScore'],80)

    def test_empty_report_has_no_invented_movement_scores(self):
        report=build_session_report({'totalReps':3,'totalCorrectReps':2},[])
        self.assertIsNone(report['averageScore'])
        self.assertEqual(report['totalReps'],3)

    def test_report_ignores_invalid_and_nonfinite_estimates(self):
        report=build_session_report({},[{'score':float('nan'),'rangeOfMotion':500},{'score':None,'rangeOfMotion':None}])
        self.assertIsNone(report['averageScore'])
        self.assertIsNone(report['averageRangeOfMotion'])

    def test_notifications_use_language_without_health_or_message_contents(self):
        for language in ('en','hi'):
            for kind in ('new_message','session_assigned','support'):
                title,body=notification_copy(kind,language)
                self.assertTrue(title and body)
        self.assertIn('सत्र',notification_copy('session_assigned','hi')[0])

    def test_old_message_or_expired_schedule_push_is_suppressed(self):
        message={'type':'new_message','patientId':'patient','doctorId':'doctor'}
        self.assertTrue(notification_is_current(message,'doctor',self.patient,self.doctor,None,self.now))
        self.patient['doctorId']='newDoctor'
        self.assertFalse(notification_is_current(message,'doctor',self.patient,self.doctor,None,self.now))
        self.patient['doctorId']='doctor'
        data={**message,'type':'session_assigned','scheduleId':'old'}
        assignment={'scheduleId':'new','status':'assigned','expiresAt':self.now+timedelta(hours=1)}
        self.assertFalse(notification_is_current(data,'patient',self.patient,self.doctor,assignment,self.now))


if __name__ == '__main__':
    unittest.main()
