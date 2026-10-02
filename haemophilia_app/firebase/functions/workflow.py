"""Pure workflow decisions, independent of Firebase and the movement models."""
from datetime import datetime
import math


def build_session_report(session, rows):
    """Use saved cumulative totals and immutable rep evidence across all resumes."""
    def number(value, fallback=0):
        return value if isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value) else fallback

    unique = {}
    for index, row in enumerate(rows):
        unique[row.get('repNumber') or ('legacy', index)] = row
    rows = list(unique.values())
    total = max(len(rows), int(number(session.get('totalReps', session.get('totalCompletedReps', session.get('currentRepCount', 0))))))
    counted_correct = sum(str(row.get('form', '')).lower() == 'correct' for row in rows)
    correct = min(total, max(counted_correct, int(number(session.get('totalCorrectReps', session.get('completedCorrectReps', 0))))))
    scores = [row['score'] for row in rows if number(row.get('score'), -1) >= 0 and number(row.get('score'), 101) <= 100]
    angles = [row['rangeOfMotion'] for row in rows if number(row.get('rangeOfMotion'), -1) >= 0 and number(row.get('rangeOfMotion'), 361) <= 360]
    return {
        'version': 1, 'totalReps': total, 'correctReps': correct,
        'incorrectReps': total - correct, 'recordedReps': len(rows),
        'correctRepRate': round(correct / total * 100, 1) if total else 0,
        'averageScore': round(sum(scores) / len(scores), 1) if scores else None,
        'averageRangeOfMotion': round(sum(angles) / len(angles), 1) if angles else None,
    }


def activation_decision(schedule, patient, doctor, assignment, now: datetime):
    if schedule.get('status') != 'scheduled':
        return 'ignore'
    if not patient or patient.get('doctorId') != schedule.get('doctorId'):
        return 'cancelled'
    if not doctor or doctor.get('role') != 'doctor' or doctor.get('isApproved') is False or doctor.get('accountActive') is False:
        return 'cancelled'
    if patient.get('accountActive') is False:
        return 'cancelled'
    if schedule['expiresAt'] <= now:
        return 'missed'
    if schedule['scheduledAt'] > now:
        return 'ignore'
    if assignment and assignment.get('status') in ('in_progress', 'paused'):
        return 'wait'
    if assignment and assignment.get('status') == 'assigned' and (assignment.get('expiresAt') is None or assignment['expiresAt'] > now):
        return 'wait'
    return 'activate'


def notification_is_current(data, recipient, patient, doctor, assignment, now):
    kind = data.get('type')
    if kind not in ('new_message', 'session_assigned', 'session_completed'):
        return True
    patient_id, doctor_id = data.get('patientId'), data.get('doctorId')
    if recipient not in (patient_id, doctor_id) or not patient or patient.get('doctorId') != doctor_id or patient.get('accountActive') is False:
        return False
    if not doctor or doctor.get('role') != 'doctor' or doctor.get('isApproved') is False or doctor.get('accountActive') is False:
        return False
    if kind == 'session_assigned':
        return bool(assignment and recipient == patient_id and assignment.get('scheduleId') == data.get('scheduleId')
                    and assignment.get('status') in ('assigned', 'in_progress', 'paused')
                    and (assignment.get('status') != 'assigned' or assignment.get('expiresAt', now) > now))
    return True


def notification_copy(kind, language):
    if language == 'hi':
        return {
            'session_assigned': ('व्यायाम सत्र उपलब्ध है', 'ऐप खोलकर अपना निर्धारित सत्र देखें।'),
            'new_message': ('नया संदेश', 'आपको एक नया संदेश मिला है। ऐप खोलकर देखें।'),
            'support': ('सहायता संदेश', 'आपके सहायता अनुरोध में नया संदेश है।'),
            'session_completed': ('सत्र पूरा हुआ', 'एक रोगी का सत्र समीक्षा के लिए उपलब्ध है।'),
        }.get(kind, ('Somaiya HemoPhysio', 'ऐप में नया अपडेट देखें।'))
    return {
        'session_assigned': ('Exercise session available', 'Open the app to view your scheduled session.'),
        'new_message': ('New message', 'You have a new message. Open the app to read it.'),
        'support': ('Support message', 'Your help request has a new message.'),
        'session_completed': ('Session completed', 'A patient session is available for review.'),
    }.get(kind, ('Somaiya HemoPhysio', 'Open the app to view an update.'))
