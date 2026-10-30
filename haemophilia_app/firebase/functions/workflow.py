"""Pure workflow decisions, independent of Firebase and the movement models."""
from datetime import datetime, timedelta
import math
import re

# Mirrors haemophilia_app/lib/utils/account_validation.dart. Keep both in step.
PASSWORD_MIN_LENGTH = 8
PASSWORD_MAX_LENGTH = 128
_KEYBOARD_ROWS = ('qwertyuiop', 'asdfghjkl', 'zxcvbnm', '1234567890')
_COMMON_WORDS = ('password', 'passw0rd', 'welcome', 'letmein', 'iloveyou', 'admin', 'qwerty', 'monkey',
                 'dragon', 'sunshine', 'princess', 'football', 'baseball', 'haemophilia', 'hemophilia',
                 'haemophysio', 'hemophysio', 'somaiya', 'physio', 'doctor', 'patient')
_LEET = str.maketrans({'0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '@': 'a', '$': 's'})


def _sequential_run(value, run=3):
    lower = value.lower()
    up = down = 1
    for prev, cur in zip(lower, lower[1:]):
        same = (prev.isdigit() and cur.isdigit()) or ('a' <= prev <= 'z' and 'a' <= cur <= 'z')
        up = up + 1 if same and ord(cur) - ord(prev) == 1 else 1
        down = down + 1 if same and ord(prev) - ord(cur) == 1 else 1
        if up >= run or down >= run:
            return True
    return False


def _repeated_run(value, run=3):
    count = 1
    for prev, cur in zip(value.lower(), value.lower()[1:]):
        count = count + 1 if prev == cur else 1
        if count >= run:
            return True
    return False


def _keyboard_run(value, run=4):
    lower = value.lower()
    for row in _KEYBOARD_ROWS:
        for line in (row, row[::-1]):
            if any(line[i:i + run] in lower for i in range(len(line) - run + 1)):
                return True
    return False


def password_problem(password, email=None, name=None):
    """Return None for an acceptable password, otherwise a short reason."""
    if not isinstance(password, str) or len(password) < PASSWORD_MIN_LENGTH or not re.search(r'[A-Za-z]', password) or not re.search(r'[0-9]', password):
        return 'Use at least 8 characters, including a letter and a number.'
    if len(password) > PASSWORD_MAX_LENGTH:
        return 'Use no more than 128 characters.'
    if _repeated_run(password):
        return 'Do not repeat the same character three or more times in a row.'
    if _sequential_run(password) or _keyboard_run(password):
        return 'Avoid consecutive sequences such as "abc", "123", "cba" or "qwer".'
    lower = password.lower()
    if any(word in lower or word in lower.translate(_LEET) for word in _COMMON_WORDS):
        return 'Avoid common words such as "password" or the app name.'
    personal = []
    if isinstance(email, str):
        local = email.strip().lower().split('@')[0]
        personal += [local] + [part for part in re.split(r'[^a-z]+', local) if part]
    if isinstance(name, str):
        personal += [part for part in re.split(r'[^a-z]+', name.lower()) if part]
    if any(len(part) >= 4 and part in lower for part in personal):
        return 'Do not include your name or email address in the password.'
    return None


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


def session_expiry(data):
    start, stored = data.get('scheduledAt') or data.get('createdAt') or data.get('startedAt'), data.get('expiresAt')
    if start is None:
        return stored
    limit = start + timedelta(hours=1)
    return min(stored, limit) if stored is not None else limit


def assignment_key(data):
    identifier = data.get('assignmentId') or data.get('scheduleId') or data.get('sourceScheduleId')
    if identifier:
        return str(identifier)
    start = data.get('scheduledAt') or data.get('createdAt')
    if isinstance(start, datetime):
        delta = start - datetime(1970, 1, 1, tzinfo=start.tzinfo)
        return 'legacy_' + str((delta.days * 86400 + delta.seconds) * 1000000 + delta.microseconds)
    return str(data.get('sessionId') or 'legacy')


def activation_decision(schedule, patient, doctor, assignment, now: datetime):
    if schedule.get('status') != 'scheduled':
        return 'ignore'
    if not patient or patient.get('doctorId') != schedule.get('doctorId'):
        return 'cancelled'
    if not doctor or doctor.get('role') != 'doctor' or doctor.get('isApproved') is False or doctor.get('accountActive') is False:
        return 'cancelled'
    if patient.get('accountActive') is False:
        return 'cancelled'
    if session_expiry(schedule) is None or session_expiry(schedule) <= now:
        return 'missed'
    if schedule['scheduledAt'] > now:
        return 'ignore'
    if assignment and assignment.get('status') in ('assigned', 'active', 'in_progress', 'paused') and session_expiry(assignment) is not None and session_expiry(assignment) > now:
        return 'wait'
    return 'activate'


REMINDER_LEAD = timedelta(minutes=15)


def _pair_valid(patient, doctor, doctor_id):
    return bool(patient and patient.get('doctorId') == doctor_id and patient.get('accountActive') is not False
                and doctor and doctor.get('role') == 'doctor' and doctor.get('isApproved') is not False
                and doctor.get('accountActive') is not False)


def reminder_due(schedule, patient, doctor, now, lead=REMINDER_LEAD):
    """True when a scheduled session starts within ``lead`` and no reminder was sent."""
    if not schedule or schedule.get('status') != 'scheduled' or schedule.get('reminderSentAt') is not None:
        return False
    start = schedule.get('scheduledAt')
    if not isinstance(start, datetime) or start <= now or start - now > lead:
        return False
    return _pair_valid(patient, doctor, schedule.get('doctorId'))


def reminder_is_current(data, recipient, patient, doctor, schedule, now):
    """A queued reminder is only pushed while its session is still upcoming."""
    if data.get('type') != 'session_reminder' or recipient != data.get('patientId'):
        return False
    if not schedule or schedule.get('status') != 'scheduled' or schedule.get('patientId') != recipient:
        return False
    start = schedule.get('scheduledAt')
    if not isinstance(start, datetime) or start <= now:
        return False
    return _pair_valid(patient, doctor, data.get('doctorId'))


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
                    and (not data.get('assignmentId') or assignment.get('assignmentId') == data.get('assignmentId'))
                    and assignment.get('status') == 'assigned'
                    and session_expiry(assignment) is not None and session_expiry(assignment) > now)
    return True


def notification_copy(kind, language):
    if language == 'hi':
        return {
            'new_patient': ('नया मरीज़ पंजीकृत हुआ', 'ऐप खोलकर नए मरीज़ की जानकारी देखें।'),
            'session_assigned': ('व्यायाम सत्र उपलब्ध है', 'ऐप खोलकर अपना निर्धारित सत्र देखें।'),
            'new_message': ('नया संदेश', 'आपको एक नया संदेश मिला है। ऐप खोलकर देखें।'),
            'support': ('सहायता संदेश', 'आपके सहायता अनुरोध में नया संदेश है।'),
            'session_completed': ('सत्र पूरा हुआ', 'एक रोगी का सत्र समीक्षा के लिए उपलब्ध है।'),
            'session_reminder': ('व्यायाम सत्र जल्द शुरू होगा', 'आपका निर्धारित सत्र 15 मिनट के भीतर शुरू होगा।'),
            'support_resolved': ('सहायता अनुरोध हल हुआ', 'आपका सहायता अनुरोध हल के रूप में चिह्नित किया गया है।'),
        }.get(kind, ('Somaiya HemoPhysio', 'ऐप में नया अपडेट देखें।'))
    return {
        'new_patient': ('New patient registered', 'Open the app to review the new patient.'),
        'session_assigned': ('Exercise session available', 'Open the app to view your scheduled session.'),
        'new_message': ('New message', 'You have a new message. Open the app to read it.'),
        'support': ('Support message', 'Your help request has a new message.'),
        'session_completed': ('Session completed', 'A patient session is available for review.'),
        'session_reminder': ('Exercise session starting soon', 'Your scheduled session starts within 15 minutes.'),
        'support_resolved': ('Help request resolved', 'Your help request was marked as resolved.'),
    }.get(kind, ('Somaiya HemoPhysio', 'Open the app to view an update.'))
