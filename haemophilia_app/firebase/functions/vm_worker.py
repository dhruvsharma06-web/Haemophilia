"""Run the notification handlers on the existing development VM.

No service-account keys are needed: this uses the VM's attached identity with
only datastore/firebase.messaging scopes. Firebase Spark does not host Cloud
Functions; this worker uses the already provisioned trial VM instead.
"""
import inspect
import logging
import os
from pathlib import Path
import signal
import sqlite3
import threading
import time
from datetime import datetime, timezone, timedelta
from types import SimpleNamespace

import google.auth
from firebase_admin import initialize_app, credentials

PROJECT = os.environ.get('HEMO_FIREBASE_PROJECT', 'haemophilia-physiotherapy-ai')
creds, _ = google.auth.default(scopes=[
    'https://www.googleapis.com/auth/datastore',
    'https://www.googleapis.com/auth/firebase.messaging',
])
class ScopedVMCredential(credentials.Base):
    def get_credential(self):
        return creds

initialize_app(ScopedVMCredential(), options={'projectId': PROJECT})

# main keeps the Cloud Functions entry points as well. The VM invokes their
# original handlers; it never starts their public HTTP/callable endpoints.
import main as handlers

STOP = threading.Event()
STATE = Path(os.environ.get('HEMO_WORKER_STATE', '/var/lib/haemophilia-notifications'))
STATE.mkdir(parents=True, exist_ok=True)
DB_LOCK = threading.Lock()
JOBS = sqlite3.connect(STATE / 'queue.sqlite3', check_same_thread=False)
JOBS.execute('PRAGMA journal_mode=WAL')
JOBS.execute('CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT)')
JOBS.execute('CREATE TABLE IF NOT EXISTS jobs (key TEXT PRIMARY KEY, kind TEXT, path TEXT, attempts INTEGER DEFAULT 0, due REAL DEFAULT 0)')
JOBS.execute('CREATE TABLE IF NOT EXISTS done (key TEXT PRIMARY KEY, finished REAL)')
row = JOBS.execute("SELECT value FROM metadata WHERE key='startedAt'").fetchone()
STARTED = datetime.fromisoformat(row[0]) if row else datetime.now(timezone.utc)
if not row:
    JOBS.execute('INSERT INTO metadata VALUES (?,?)', ('startedAt', STARTED.isoformat()))
    JOBS.commit()


def enqueue(kind, doc):
    if not doc.exists:
        return
    data = doc.to_dict() or {}
    if kind in ('chat', 'support', 'new_patient'):
        created = data.get('createdAt') or doc.create_time
        if not isinstance(created, datetime) or created < STARTED:
            return  # Starting a worker must not notify about old messages.
    if kind == 'push':
        if data.get('read') is True or data.get('pushStatus') in ('sent', 'no_devices', 'inactive', 'obsolete', 'read'):
            return
        created = data.get('createdAt') or doc.create_time
        if isinstance(created, datetime) and created < datetime.now(timezone.utc) - timedelta(days=1):
            return
    key = f'{kind}:{doc.reference.path}'
    if kind == 'patient_update':
        # Registration alerts are dismissed when ownership/account state changes.
        key += ':' + str(data.get('doctorId')) + ':' + str(data.get('accountActive', True))
    elif kind == 'assignment':
        key += ':' + str(data.get('assignmentId'))
    with DB_LOCK:
        if JOBS.execute('SELECT 1 FROM done WHERE key=?', (key,)).fetchone():
            return
        JOBS.execute('INSERT OR IGNORE INTO jobs (key,kind,path) VALUES (?,?,?)', (key, kind, doc.reference.path))
        JOBS.commit()


def on_users(docs, changes, read_time):
    for change in changes:
        if change.type.name == 'REMOVED':
            continue
        doc = change.document
        if (doc.to_dict() or {}).get('role') == 'patient':
            enqueue('new_patient', doc)
            enqueue('patient_update', doc)


def on_messages(docs, changes, read_time):
    for change in changes:
        if change.type.name == 'REMOVED':
            continue
        doc = change.document
        parts = doc.reference.path.split('/')
        if len(parts) == 4 and parts[2] == 'messages':
            if parts[0] == 'conversations':
                enqueue('chat', doc)
            elif parts[0] == 'supportTickets':
                enqueue('support', doc)


def on_notifications(docs, changes, read_time):
    for change in changes:
        if change.type.name != 'REMOVED':
            parts = change.document.reference.path.split('/')
            if len(parts) == 4 and parts[0] == 'users' and parts[2] == 'notifications':
                enqueue('push', change.document)


def on_assignments(docs, changes, read_time):
    for change in changes:
        if change.type.name != 'REMOVED':
            doc = change.document
            if (doc.to_dict() or {}).get('status') == 'assigned' and (doc.to_dict() or {}).get('assignmentId'):
                enqueue('assignment', doc)


def invoke(kind, path):
    doc = handlers._db().document(path).get()
    if not doc.exists:
        return
    parts = path.split('/')
    params = {}
    if kind == 'chat':
        params = {'conversationId': parts[1], 'messageId': parts[3]}
        fn = handlers.notify_chat_message
    elif kind == 'support':
        params = {'ticketId': parts[1], 'messageId': parts[3]}
        fn = handlers.notify_support_reply
    elif kind == 'push':
        params = {'userId': parts[1], 'notificationId': parts[3]}
        fn = handlers.dispatch_notification
    elif kind == 'new_patient':
        params = {'userId': parts[1]}
        fn = handlers.notify_admins_new_patient
    elif kind == 'patient_update':
        params = {'userId': parts[1]}
        fn = handlers.dismiss_processed_patient_alerts
        # Current state is authoritative; an old retry cannot undo a transfer.
        empty = SimpleNamespace(to_dict=lambda: {})
        doc = SimpleNamespace(before=empty, after=doc)
    elif kind == 'assignment':
        params = {'patientId': parts[1]}
        fn = handlers.notify_immediate_assignment
        doc = SimpleNamespace(after=doc)
    else:
        raise ValueError('Unknown notification job kind')
    inspect.unwrap(fn)(SimpleNamespace(data=doc, params=params))


def consume():
    while not STOP.is_set():
        with DB_LOCK:
            job = JOBS.execute('SELECT key,kind,path,attempts FROM jobs WHERE due<=? ORDER BY due LIMIT 1', (time.time(),)).fetchone()
        if job is None:
            STOP.wait(0.5)
            continue
        key, kind, path, attempts = job
        try:
            invoke(kind, path)
        except Exception as error:
            # Log error class, not chat content, tokens or exception response body.
            logging.warning('Notification job %s failed (%s); will retry', kind, type(error).__name__)
            with DB_LOCK:
                JOBS.execute('UPDATE jobs SET attempts=?,due=? WHERE key=?', (attempts + 1, time.time() + min(120, 2 ** min(attempts + 1, 7)), key))
                JOBS.commit()
        else:
            with DB_LOCK:
                JOBS.execute('DELETE FROM jobs WHERE key=?', (key,))
                JOBS.execute('INSERT OR REPLACE INTO done VALUES (?,?)', (key, time.time()))
                JOBS.commit()


def run():
    logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
    db = handlers._db()
    # Fail before starting if the attached VM identity cannot read this project.
    list(db.collection('users').limit(1).stream())
    watches = [
        db.collection('users').on_snapshot(on_users),
        db.collection_group('messages').on_snapshot(on_messages),
        db.collection_group('notifications').on_snapshot(on_notifications),
        db.collection('exerciseAssignments').on_snapshot(on_assignments),
    ]
    consumer = threading.Thread(target=consume, daemon=True)
    consumer.start()
    logging.info('Notification worker ready for project %s', PROJECT)
    try:
        while not STOP.is_set():
            try:
                inspect.unwrap(handlers.activate_scheduled_sessions)(None)
            except Exception as error:
                logging.warning('Schedule activation failed (%s); will retry', type(error).__name__)
            STOP.wait(30)
    finally:
        for watch in watches:
            watch.unsubscribe()
        consumer.join(timeout=30)
        JOBS.close()


if __name__ == '__main__':
    signal.signal(signal.SIGTERM, lambda *_: STOP.set())
    signal.signal(signal.SIGINT, lambda *_: STOP.set())
    run()
