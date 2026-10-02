"""Server-owned schedule activation and device-token notification dispatch.

Deployment is separate from editing this source. No service credentials belong
in the mobile app. Cloud Functions supplies the server identity.
"""
from datetime import datetime, timezone, timedelta
from uuid import uuid4
import logging
import hashlib
import re
from functools import lru_cache
from retrying_trigger import retrying_firestore_trigger

from firebase_admin import initialize_app, firestore, messaging, auth
from firebase_functions import firestore_fn, scheduler_fn, https_fn
from google.cloud.firestore_v1.base_query import FieldFilter
from workflow import activation_decision, notification_copy, build_session_report, notification_is_current

initialize_app()
@lru_cache(maxsize=1)
def _db():
    return firestore.client()


@https_fn.on_call()
def create_doctor_account(request: https_fn.CallableRequest) -> dict:
    if request.auth is None:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.UNAUTHENTICATED, 'Please sign in.')
    actor = request.auth.uid
    administrator = _db().collection('users').document(actor).get().to_dict() or {}
    if administrator.get('role') != 'admin' or administrator.get('accountActive') is False:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.PERMISSION_DENIED, 'Administrator access required.')
    data = request.data if isinstance(request.data, dict) else {}
    fields = ('name', 'email', 'phoneNumber', 'registrationNumber', 'qualification', 'specialization', 'hospital')
    if any(not isinstance(data.get(key), str) or not data[key].strip() or len(data[key]) > 200 for key in fields):
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.INVALID_ARGUMENT, 'Complete all professional details.')
    email = data['email'].strip().lower()
    password = data.get('password')
    request_id = data.get('requestId', '')
    if not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', email) or not isinstance(password, str) or len(password) < 8 or not isinstance(request_id, str) or not re.fullmatch(r'[A-Za-z0-9]{16,64}', request_id):
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.INVALID_ARGUMENT, 'Enter a valid email and an initial password of at least 8 characters.')
    # Deterministic UID makes retries after a lost response safe; passwords are
    # passed only to Firebase Auth and are never stored in Firestore or logged.
    uid = 'D' + hashlib.sha256((actor + ':' + request_id).encode()).hexdigest()[:31]
    ref = _db().collection('users').document(uid)
    existing = ref.get().to_dict()
    if existing:
        if existing.get('email') != email or existing.get('createdBy') != actor:
            raise https_fn.HttpsError(https_fn.FunctionsErrorCode.ALREADY_EXISTS, 'Start a new doctor request.')
        return {'uid': uid}
    try:
        auth.create_user(uid=uid, email=email, password=password, display_name=data['name'].strip())
    except auth.UidAlreadyExistsError:
        if auth.get_user(uid).email != email:
            raise https_fn.HttpsError(https_fn.FunctionsErrorCode.ALREADY_EXISTS, 'Account already exists.')
    except auth.EmailAlreadyExistsError:
        raise https_fn.HttpsError(https_fn.FunctionsErrorCode.ALREADY_EXISTS, 'An account already exists with this email address.')
    profile = {key: data[key].strip() for key in fields}
    profile.update({'email': email, 'uid': uid, 'role': 'doctor', 'isApproved': True, 'accountActive': True,
                    'status': 'approved', 'createdBy': actor, 'approvedBy': actor,
                    'createdAt': firestore.SERVER_TIMESTAMP, 'approvalUpdatedAt': firestore.SERVER_TIMESTAMP})
    batch = _db().batch()
    batch.set(ref, profile)
    batch.set(_db().collection('adminAudit').document('create_' + uid), {'actorId': actor, 'userId': uid, 'action': 'create_doctor', 'createdAt': firestore.SERVER_TIMESTAMP})
    batch.commit()
    return {'uid': uid}


@scheduler_fn.on_schedule(schedule='every 1 minutes', retry_count=3)
def activate_scheduled_sessions(event: scheduler_fn.ScheduledEvent) -> None:
    now = datetime.now(timezone.utc)
    # Stream all due occurrences: paused patients must not starve later patients.
    due = _db().collection('exerciseSchedules').where(filter=FieldFilter('status', '==', 'scheduled')).where(filter=FieldFilter('scheduledAt', '<=', now)).order_by('scheduledAt').stream()
    for snapshot in due:
        _activate(_db().transaction(), snapshot.reference, now)


@firestore.transactional
def _activate(transaction, ref, now):
    schedule = ref.get(transaction=transaction).to_dict()
    if not schedule or schedule.get('status') != 'scheduled':
        return
    patient_id, doctor_id = schedule['patientId'], schedule['doctorId']
    patient_ref = _db().collection('users').document(patient_id)
    patient = patient_ref.get(transaction=transaction).to_dict()
    doctor = _db().collection('users').document(doctor_id).get(transaction=transaction).to_dict()
    assignment_ref = _db().collection('exerciseAssignments').document(patient_id)
    assignment = assignment_ref.get(transaction=transaction).to_dict()
    decision = activation_decision(schedule, patient, doctor, assignment, now)
    if schedule.get('managedSeries'):
        series = _db().collection('exerciseScheduleSeries').document(schedule['seriesId']).get(transaction=transaction).to_dict()
        if not series or series.get('status') == 'cancelled':
            decision = 'cancelled'
        elif series.get('status') != 'ready' and decision in ('activate', 'wait'):
            return
    if decision in ('ignore', 'wait'):
        return
    if decision != 'activate':
        transaction.update(ref, {'status': decision, 'updatedAt': firestore.SERVER_TIMESTAMP})
        return
    exercises = schedule['exercises']
    transaction.set(assignment_ref, {
        'patientId': patient_id, 'doctorId': doctor_id, 'scheduleId': ref.id,
        'sessionName': schedule['sessionName'], 'exercises': exercises,
        'exerciseProgress': schedule['exerciseProgress'], 'status': 'assigned',
        'scheduledAt': schedule['scheduledAt'], 'expiresAt': schedule['expiresAt'],
        'currentExerciseIndex': 0, 'currentExercise': exercises[0]['exercise'],
        'completedCorrectReps': 0, 'totalCompletedReps': 0, 'progressPercentage': 0.0,
        'createdAt': firestore.SERVER_TIMESTAMP, 'lastUpdatedAt': firestore.SERVER_TIMESTAMP,
        'updatedAt': firestore.SERVER_TIMESTAMP,
    })
    transaction.update(ref, {'status': 'activated', 'activatedAt': firestore.SERVER_TIMESTAMP})
    title, body = notification_copy('session_assigned', patient.get('language', 'en'))
    transaction.set(patient_ref.collection('notifications').document('schedule_' + ref.id), {
        'title': title, 'body': body, 'read': False, 'senderId': doctor_id,
        'createdAt': firestore.SERVER_TIMESTAMP,
        'data': {'type': 'session_assigned', 'patientId': patient_id, 'doctorId': doctor_id, 'scheduleId': ref.id},
    })


@retrying_firestore_trigger(firestore_fn.on_document_created(document='users/{userId}/notifications/{notificationId}'))
def dispatch_notification(event: firestore_fn.Event[firestore_fn.DocumentSnapshot | None]) -> None:
    if event.data is None:
        return
    uid = event.params['userId']
    notification_ref = event.data.reference
    lease = uuid4().hex
    now = datetime.now(timezone.utc)
    if not _claim(_db().transaction(), notification_ref, lease, now):
        return
    try:
        user = _db().collection('users').document(uid).get().to_dict() or {}
        if user.get('accountActive') is False:
            notification_ref.update({'pushStatus': 'inactive'})
            return
        # fcmTokens is authoritative. Do not fall back to a stale legacy token on logout.
        current = notification_ref.get().to_dict() or {}
        delivered = set(current.get('deliveredTokens', []))
        tokens = list(dict.fromkeys(t for t in user.get('fcmTokens', []) if t and t not in delivered))
        if not tokens:
            notification_ref.update({'pushStatus': 'sent' if delivered else 'no_devices'})
            return
        payload = event.data.to_dict() or {}
        data = payload.get('data') or {}
        if data.get('type') in ('new_message', 'session_assigned', 'session_completed'):
            patient_id, doctor_id = data.get('patientId'), data.get('doctorId')
            patient = _db().collection('users').document(patient_id).get().to_dict() if patient_id else None
            doctor = _db().collection('users').document(doctor_id).get().to_dict() if doctor_id else None
            assignment = _db().collection('exerciseAssignments').document(patient_id).get().to_dict() if patient_id else None
            if not notification_is_current(data, uid, patient, doctor, assignment, now):
                notification_ref.update({'pushStatus': 'obsolete'})
                return
        title, body = notification_copy(data.get('type'), user.get('language', 'en'))
        failures = False
        invalid_tokens = []
        for offset in range(0, len(tokens), 500):
            batch_tokens = tokens[offset:offset+500]
            result = messaging.send_each_for_multicast(messaging.MulticastMessage(
                tokens=batch_tokens, notification=messaging.Notification(title=title, body=body),
                data={**{str(k): str(v) for k, v in data.items()}, 'notificationId': notification_ref.id},
                android=messaging.AndroidConfig(collapse_key=notification_ref.id, notification=messaging.AndroidNotification(tag=notification_ref.id)),
                apns=messaging.APNSConfig(headers={'apns-collapse-id': notification_ref.id}),
            ))
            for token, response in zip(batch_tokens, result.responses):
                if response.success:
                    delivered.add(token)
                    continue
                if isinstance(response.exception, messaging.UnregisteredError):
                    invalid_tokens.append(token)
                else:
                    failures = True
            notification_ref.update({'deliveredTokens': list(delivered)})
        if invalid_tokens:
            _db().collection('users').document(uid).update({'fcmTokens': firestore.ArrayRemove(invalid_tokens)})
        if failures:
            raise RuntimeError('Some notification deliveries failed; retry required.')
        notification_ref.update({'pushStatus': 'sent', 'pushSentAt': firestore.SERVER_TIMESTAMP})
    except Exception:
        notification_ref.update({'pushStatus': 'retry'})
        logging.exception('Push delivery failed for notification %s', notification_ref.id)
        raise


@firestore.transactional
def _claim(transaction, ref, lease, now):
    data = ref.get(transaction=transaction).to_dict() or {}
    if data.get('pushStatus') in ('sent', 'no_devices', 'inactive', 'obsolete'):
        return False
    if data.get('pushStatus') == 'sending' and data.get('pushLeaseAt', now) > now - timedelta(minutes=2):
        raise RuntimeError('Notification delivery is in progress; retry later.')
    transaction.update(ref, {'pushStatus': 'sending', 'pushLease': lease, 'pushLeaseAt': now})
    return True


@retrying_firestore_trigger(firestore_fn.on_document_created(document='supportTickets/{ticketId}/messages/{messageId}'))
def notify_support_reply(event: firestore_fn.Event[firestore_fn.DocumentSnapshot | None]) -> None:
    if event.data is None:
        return
    ticket = _db().collection('supportTickets').document(event.params['ticketId']).get().to_dict() or {}
    message = event.data.to_dict() or {}
    owner = ticket.get('userId')
    if not owner:
        return
    if message.get('senderId') == owner:
        recipients = [doc.id for doc in _db().collection('users').where(filter=FieldFilter('role', '==', 'admin')).stream()]
    else:
        recipients = [owner]
    for uid in recipients:
        ref = _db().collection('users').document(uid).collection('notifications').document('support_' + event.params['ticketId'] + '_' + event.params['messageId'])
        if ref.get().exists:
            continue
        _create_notification_once(_db().transaction(), ref, {'senderId': message.get('senderId'), 'read': False, 'title': 'Support message', 'body': 'Open the app to read a help message.', 'createdAt': firestore.SERVER_TIMESTAMP,
                 'data': {'type': 'support', 'ticketId': event.params['ticketId']}})


@firestore.transactional
def _create_notification_once(transaction, ref, payload):
    if not ref.get(transaction=transaction).exists:
        transaction.set(ref, payload)


@retrying_firestore_trigger(firestore_fn.on_document_updated(document='users/{userId}'))
def synchronize_patient_transfer(event: firestore_fn.Event[firestore_fn.Change[firestore_fn.DocumentSnapshot]]) -> None:
    before, after = event.data.before.to_dict() or {}, event.data.after.to_dict() or {}
    if before.get('doctorId') == after.get('doctorId'):
        return
    uid = event.params['userId']
    # Use current ownership, so an older retry cannot undo a newer transfer.
    for session in _db().collection('assessmentSessions').where(filter=FieldFilter('patientId', '==', uid)).stream():
        _route_session(_db().transaction(), session.reference, uid)
    for schedule in _db().collection('exerciseSchedules').where(filter=FieldFilter('patientId', '==', uid)).where(filter=FieldFilter('status', '==', 'scheduled')).stream():
        _cancel_old_schedule(_db().transaction(), schedule.reference, uid)


@firestore.transactional
def _route_session(transaction, ref, patient_id):
    patient = _db().collection('users').document(patient_id).get(transaction=transaction).to_dict() or {}
    session = ref.get(transaction=transaction).to_dict()
    if session and session.get('doctorId') != patient.get('doctorId'):
        transaction.update(ref, {'originalDoctorId': session.get('originalDoctorId', session.get('doctorId')), 'doctorId': patient.get('doctorId')})


@firestore.transactional
def _cancel_old_schedule(transaction, ref, patient_id):
    patient = _db().collection('users').document(patient_id).get(transaction=transaction).to_dict() or {}
    schedule = ref.get(transaction=transaction).to_dict() or {}
    if schedule.get('status') == 'scheduled' and schedule.get('doctorId') != patient.get('doctorId'):
        transaction.update(ref, {'status': 'cancelled', 'updatedAt': firestore.SERVER_TIMESTAMP})


@retrying_firestore_trigger(firestore_fn.on_document_written(document='assessmentSessions/{sessionId}'))
def generate_session_report(event: firestore_fn.Event[firestore_fn.Change[firestore_fn.DocumentSnapshot | None]]) -> None:
    after = event.data.after
    if after is None or not after.exists or after.to_dict().get('status') not in ('paused', 'completed'):
        return
    _refresh_report(_db().transaction(), after.reference)


@retrying_firestore_trigger(firestore_fn.on_document_created(document='users/{patientId}/assessments/{repId}'))
def refresh_report_after_rep(event: firestore_fn.Event[firestore_fn.DocumentSnapshot | None]) -> None:
    if event.data is None:
        return
    session_id = (event.data.to_dict() or {}).get('sessionId')
    if session_id:
        _refresh_report(_db().transaction(), _db().collection('assessmentSessions').document(session_id))


@firestore.transactional
def _refresh_report(transaction, ref):
    session = ref.get(transaction=transaction).to_dict() or {}
    if session.get('status') not in ('paused', 'completed') or not session.get('patientId'):
        return
    rows = [rep.to_dict() for rep in _db().collection('users').document(session['patientId']).collection('assessments').where(filter=FieldFilter('sessionId', '==', ref.id)).stream(transaction=transaction)]
    report = build_session_report(session, rows)
    # This equality guard prevents the report write from triggering a loop.
    if session.get('report') != report:
        transaction.update(ref, {'report': report, 'reportGeneratedAt': firestore.SERVER_TIMESTAMP})
