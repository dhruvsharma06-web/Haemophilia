"""Fresh original-video decode, per-frame raw image AND world pose, no labels used."""
import os
os.environ['TF_CPP_MIN_LOG_LEVEL']='2'
os.environ['OMP_NUM_THREADS']='1'
from pathlib import Path
import sys, json, subprocess, time, hashlib, traceback
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from common import ROOT, DATA, canonical, config, verify_config, sha, dump, write_csv
import numpy as np
from concurrent.futures import ProcessPoolExecutor, as_completed

def read_exact(pipe,n):
    parts=[]; remaining=n
    while remaining:
        block=pipe.read(remaining)
        if not block: break
        parts.append(block); remaining-=len(block)
    return b''.join(parts)

def extract(job):
    import mediapipe as mp
    rows, inv, cfg = job
    vid=rows[0]['video_id']; out=ROOT/'preprocessing/raw_landmarks'/f'{vid}.npz'
    audit_path=ROOT/'preprocessing'/f'{vid}_audit.json'
    source=rows[0]['source_video']; source_hash=rows[0]['source_sha256']
    started=time.perf_counter()
    try:
        assert sha(source)==source_hash, 'Original video hash mismatch'
        timing_path=DATA/'frame_audit'/f'{vid}_source_times.json'
        timing=json.loads(timing_path.read_text()); n=len(timing)
        starts=np.array([x['start'] for x in timing]); ends=np.array([x['end'] for x in timing])
        assert np.all(np.diff(starts)>0)
        needed=np.zeros(n,dtype=bool)
        for r in rows:
            a,b=int(r['start_frame']),int(r['end_frame']); assert 0<=a<=b<n
            needed[a:b+1]=True
        indices=np.flatnonzero(needed); lookup={int(k):i for i,k in enumerate(indices)}
        image=np.full((len(indices),33,4),np.nan,dtype=np.float32); world=image.copy()
        # Sources currently have no rotation; refuse an unhandled display-coordinate change.
        assert int(float(inv['rotation_degrees'] or 0))==0, 'Unexpected source rotation'
        width=cfg['decode']['width']; height=round(int(inv['height'])*width/int(inv['width'])/2)*2
        cmd=['ffmpeg','-hide_banner','-loglevel','warning','-threads','2','-i',source,'-map','0:v:0','-vf',f'scale={width}:{height}:flags=bilinear','-fps_mode','passthrough','-threads','1','-f','rawvideo','-pix_fmt','rgb24','pipe:1']
        log=ROOT/'preprocessing'/f'{vid}_ffmpeg.log'
        pose=None; replica=None; repeat_frames=0; max_delta=0.0; mismatch_masks=0; decoder_count=0; input_hash=hashlib.sha256(); graph_resets=0
        with log.open('wb') as err:
            proc=subprocess.Popen(cmd,stdout=subprocess.PIPE,stderr=err,bufsize=10**7)
            try:
                while True:
                    raw=read_exact(proc.stdout,width*height*3)
                    if not raw: break
                    assert len(raw)==width*height*3, 'Partial decoded frame'
                    i=decoder_count; decoder_count+=1
                    assert i<n,'More decoded frames than verified presentation timestamps'
                    if not needed[i]:
                        if pose is not None: pose.close(); pose=None
                        if replica is not None: replica.close(); replica=None
                        continue
                    if pose is None:
                        pose=mp.solutions.pose.Pose(**cfg['pose']); graph_resets+=1
                        if repeat_frames==0: replica=mp.solutions.pose.Pose(**cfg['pose'])
                    frame=np.frombuffer(raw,dtype=np.uint8).reshape(height,width,3); frame.flags.writeable=False
                    input_hash.update(raw); result=pose.process(frame); j=lookup[i]
                    for field,dest in [('pose_landmarks',image),('pose_world_landmarks',world)]:
                        points=getattr(result,field)
                        if points: dest[j]=[[p.x,p.y,p.z,p.visibility] for p in points.landmark]
                    if replica is not None:
                        other=replica.process(frame)
                        for field,dest in [('pose_landmarks',image),('pose_world_landmarks',world)]:
                            points=getattr(other,field)
                            compare=np.array([[p.x,p.y,p.z,p.visibility] for p in points.landmark],dtype=np.float32) if points else np.full((33,4),np.nan)
                            mismatch_masks+=int(not np.array_equal(np.isnan(compare),np.isnan(dest[j])))
                            if np.isfinite(compare).any(): max_delta=max(max_delta,float(np.nanmax(abs(compare-dest[j]))))
                        repeat_frames+=1
                        if repeat_frames>=32: replica.close(); replica=None
                assert proc.wait()==0,'ffmpeg decode failed'
                assert decoder_count==n, f'Decoded {decoder_count} versus {n} timestamps'
            finally:
                if pose is not None:pose.close()
                if replica is not None:replica.close()
                if proc.poll() is None:proc.kill();proc.wait()
                proc.stdout.close()
        np.savez_compressed(out,frame_indices=indices,source_times=starts[indices],source_end_times=ends[indices],image_landmarks=image,world_landmarks=world,source_sha256=source_hash,source_timing_sha256=sha(timing_path),image_size=np.array([width,height]))
        audit={'video_id':vid,'source_sha256':source_hash,'source_video':source,'status':'success','canonical_repetitions':len(rows),'original_decoded_frames':decoder_count,'canonical_union_frames':len(indices),'raw_pose_available_frames':int(np.isfinite(world[:,:,0]).all(axis=1).sum()),'graph_resets':graph_resets,'timing_sha256':sha(timing_path),'resized_selected_rgb_sha256':input_hash.hexdigest(),'raw_landmarks_sha256':sha(out),'repeatability_frames':repeat_frames,'repeatability_max_absolute_delta':max_delta,'repeatability_missing_mask_mismatches':mismatch_masks,'decode_command':cmd,'seconds':time.perf_counter()-started}
        dump(audit_path,audit)
        return audit
    except Exception as e:
        audit={'video_id':vid,'status':'failed','error':repr(e),'traceback':traceback.format_exc()};dump(audit_path,audit);return audit

def main():
    import csv
    verify_config(); rows,_=canonical(); cfg=config()
    with (DATA/'video_inventory.csv').open(newline='',encoding='utf-8') as f:inventory={r['video_id']:r for r in csv.DictReader(f)}
    groups={}
    for r in rows:groups.setdefault(r['video_id'],[]).append(r)
    completed=[]; jobs=[]
    for vid,rs in sorted(groups.items()):
        audit_path=ROOT/'preprocessing'/f'{vid}_audit.json'; raw=ROOT/'preprocessing/raw_landmarks'/f'{vid}.npz'
        if audit_path.exists() and raw.exists():
            a=json.loads(audit_path.read_text())
            if a['status']=='success' and sha(raw)==a['raw_landmarks_sha256']:
                completed.append(a);continue
        jobs.append((rs,inventory[vid],cfg))
    with ProcessPoolExecutor(max_workers=cfg['decode']['workers']) as pool:
        futures=[pool.submit(extract,job) for job in jobs]
        for future in as_completed(futures):
            a=future.result();completed.append(a)
            print(json.dumps({k:a[k] for k in ['video_id','status','canonical_union_frames','seconds','error'] if k in a}),flush=True)
    dump(ROOT/'preprocessing/source_extraction_audit.json',sorted(completed,key=lambda r:r['video_id']))
    assert all(a['status']=='success' for a in completed),'See explicit extraction failures; no training allowed'
    assert all(a['repeatability_missing_mask_mismatches']==0 and a['repeatability_max_absolute_delta']<=1e-6 for a in completed), 'Raw extraction repeatability audit failed'
    audit=[]
    for vid,rs in groups.items():
        with np.load(ROOT/'preprocessing/raw_landmarks'/f'{vid}.npz') as data:
            for r in rs:
                a,b=int(r['start_frame']),int(r['end_frame']); mask=(data['frame_indices']>=a)&(data['frame_indices']<=b)
                raw=data['world_landmarks'][mask]; vis=raw[:,[11,12,13,14,15,16,23,24],3]
                assert len(raw)==b-a+1
                audit.append({'repetition_id':r['repetition_id'],'video_id':vid,'source_sha256':r['source_sha256'],'start_frame':a,'end_frame':b,'expected_frames':b-a+1,'extracted_frames':len(raw),'pose_available_frames':int(np.isfinite(raw[:,:,0]).all(axis=1).sum()),'core_joint_visibility_mean':float(np.nanmean(vis)),'core_joint_visibility_min':float(np.nanmin(vis)),'core_joint_below_0_5_fraction':float(np.mean(~np.isfinite(vis)|(vis<0.5))),'status':'success'})
    write_csv(ROOT/'preprocessing/repetition_extraction_audit.csv',audit)
    print(f'COMPLETE: {len(audit)} canonical repetitions / {len(groups)} original sources',flush=True)

if __name__=='__main__':main()
