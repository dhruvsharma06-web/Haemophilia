"""Compatibility for retry-enabled Firestore events in firebase-functions 0.6.

That SDK emits retry=False and does not expose a retry keyword on Firestore
decorators. Set the retry field in its generated deployment manifest, which is
the same manifest consumed by the Firebase CLI. A manifest test protects this
adapter when upgrading the pinned SDK.
"""
def retrying_firestore_trigger(trigger):
    def decorate(function):
        wrapped = trigger(function)
        endpoint = getattr(wrapped, '__firebase_endpoint__', None)
        if endpoint is None or endpoint.eventTrigger is None:
            raise RuntimeError('The Firebase SDK no longer exposes the expected Firestore event manifest.')
        endpoint.eventTrigger['retry'] = True
        return wrapped
    return decorate
