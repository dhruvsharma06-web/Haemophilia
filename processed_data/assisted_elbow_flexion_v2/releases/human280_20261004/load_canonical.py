"""Read and validate this release only; this module does not train any model."""
from pathlib import Path
import csv,json,hashlib,collections

RELEASE=Path(__file__).resolve().parent

def validate_rows(rows,contract,review):
    ids=[r['repetition_id'] for r in rows]
    approved={d['repetition_id']:d for d in review['decisions']}
    expected=set(contract['allowed_repetition_ids'])
    if len(ids)!=contract['expected_count'] or len(set(ids))!=len(ids) or set(ids)!=expected or expected!=set(approved):
        raise ValueError('Canonical membership must be exactly the 280 current human-reviewed IDs')
    if set(ids)&set(contract['excluded_repetition_ids']):raise ValueError('Excluded candidate included')
    if contract['target_column']!='label' or contract['classes']!=['Correct','Incorrect']:raise ValueError('Only binary quality is a supervised target')
    ranges=set()
    for r in rows:
        d=approved[r['repetition_id']]
        if r['hand'] not in ['Left','Right'] or r['label'] not in ['Correct','Incorrect']:raise ValueError('Invalid hand/quality value')
        if r['hand']!=d['hand'] or r['label']!=d['label']:raise ValueError('Human hand/label decision was altered')
        if r['source_sha256']!=d['source_sha256'] or r['video_id']!=d['video_id']:raise ValueError('Source provenance mismatch')
        a,b=int(r['start_frame']),int(r['end_frame'])
        if (a,b)!=(d['start_frame'],d['end_frame']) or not 0<=a<=b:raise ValueError('Human range revision was not preserved')
        if r['source_group']!=r['source_sha256']:raise ValueError('Wrong source grouping key')
        if r['human_review_status']!='authoritative_user_confirmed':raise ValueError('Missing current human-review authority')
        if str(r['supervised_eligible']).lower()!='true' or str(r['excluded']).lower()!='false':raise ValueError('Unexpected exclusion in canonical manifest')
        key=(r['source_sha256'],a,b)
        if key in ranges:raise ValueError('Duplicate source/frame range')
        ranges.add(key)
    return rows

def load_canonical(release=RELEASE):
    release=Path(release)
    contract=json.loads((release/'CANONICAL_CONTRACT.json').read_text())
    p=release/contract['canonical_manifest']
    if hashlib.sha256(p.read_bytes()).hexdigest()!=contract['canonical_manifest_sha256']:raise ValueError('Canonical manifest checksum mismatch')
    reviewpath=release/contract['authoritative_review_file']
    if hashlib.sha256(reviewpath.read_bytes()).hexdigest()!=contract['authoritative_review_sha256']:raise ValueError('Review export checksum mismatch')
    with p.open(newline='',encoding='utf-8') as f:rows=list(csv.DictReader(f))
    return validate_rows(rows,contract,json.loads(reviewpath.read_text()))

def assert_source_grouping(rows,split_by_repetition):
    if set(split_by_repetition)!={r['repetition_id'] for r in rows}:raise ValueError('Split membership must match the canonical allowlist exactly')
    groups=collections.defaultdict(set)
    for r in rows:
        split=split_by_repetition[r['repetition_id']]
        if not isinstance(split,str) or not split.strip():raise ValueError('Missing split assignment')
        groups[r['source_sha256']].add(split)
    if any(len(s)>1 for s in groups.values()):raise ValueError('Source-video leakage: one original video spans multiple splits')
    return True

if __name__=='__main__':
    rows=load_canonical()
    print(f'Validated {len(rows)} canonical human-reviewed repetitions. No training performed or authorized.')
