"""Fixed world-coordinate biomechanics; labels never influence feature construction."""
from pathlib import Path
import sys,json
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from common import ROOT, canonical, config, verify_config, dump, sha, write_csv
import numpy as np
import pandas as pd

BASE=['active_angle','opposing_angle','active_flare','opposing_flare','torso_lean','shoulder_depth_ratio']
CHANNELS=BASE+['active_velocity','opposing_velocity','angle_asymmetry','flare_asymmetry','elapsed_seconds']
SCALARS=['active_min_angle','active_max_angle','active_rom','opposing_min_angle','opposing_max_angle','opposing_rom','duration',
 'active_peak_abs_velocity','active_mean_abs_velocity','opposing_peak_abs_velocity','opposing_mean_abs_velocity',
 'active_mean_flare','active_max_flare','opposing_mean_flare','opposing_max_flare','mean_angle_asymmetry','max_angle_asymmetry','mean_flare_asymmetry','max_flare_asymmetry',
 'mean_torso_lean','max_torso_lean','range_torso_lean','mean_shoulder_depth_ratio','max_shoulder_depth_ratio','range_shoulder_depth_ratio',
 'flexion_duration','extension_duration','flexion_fraction','active_start_angle','active_end_angle','flexion_excursion','extension_excursion','flexion_net_speed','extension_net_speed']

def angle(a,b,c):
    u=a-b;v=c-b;den=np.linalg.norm(u,axis=1)*np.linalg.norm(v,axis=1)
    out=np.degrees(np.arccos(np.clip(np.sum(u*v,axis=1)/np.where(den>1e-8,den,np.nan),-1,1)))
    return out

def base_features(world,hand,visibility_threshold):
    xyz=world[:,:,:3];vis=world[:,:,3]
    active=(11,13,15) if hand=='Left' else (12,14,16)
    other=(12,14,16) if hand=='Left' else (11,13,15)
    shoulder=xyz[:,12]-xyz[:,11];width=np.linalg.norm(shoulder,axis=1)
    unit=shoulder/np.where(width>1e-8,width,np.nan)[:,None]
    midshoulder=(xyz[:,11]+xyz[:,12])/2;midhip=(xyz[:,23]+xyz[:,24])/2
    torso=midshoulder-midhip
    values=np.column_stack([
      angle(*(xyz[:,i] for i in active)),angle(*(xyz[:,i] for i in other)),
      np.abs(np.sum((xyz[:,active[1]]-xyz[:,active[0]])*unit,axis=1))/width,
      np.abs(np.sum((xyz[:,other[1]]-xyz[:,other[0]])*unit,axis=1))/width,
      np.degrees(np.arctan2(np.linalg.norm(torso[:,[0,2]],axis=1),np.abs(torso[:,1]))),
      np.abs(shoulder[:,2])/width])
    joints=[active,other,(11,12,active[1]),(11,12,other[1]),(11,12,23,24),(11,12)]
    for j,indices in enumerate(joints):
        valid=(vis[:,indices]>=visibility_threshold).all(axis=1)&np.isfinite(xyz[:,indices,:]).all(axis=(1,2))
        if j==4:valid&=np.linalg.norm(torso,axis=1)>1e-8
        values[~valid,j]=np.nan
    values[~np.isfinite(values)]=np.nan
    return values

def repair_channel(values,times,policy):
    """Only local, bounded interpolation/endpoint holds; return every repaired run."""
    x=values.copy();valid=np.isfinite(x);events=[]
    if valid.mean()<policy['minimum_valid_fraction']:
        return x,events,f'valid_fraction={valid.mean():.6f} below {policy["minimum_valid_fraction"]}'
    n=len(x);i=0
    while i<n:
        if valid[i]:i+=1;continue
        a=i
        while i<n and not valid[i]:i+=1
        b=i-1
        if a>0 and b<n-1:
            gap=times[b+1]-times[a-1]
            if gap>policy['max_internal_gap_seconds']:return x,events,f'internal_gap_seconds={gap:.6f}'
            x[a:b+1]=np.interp(times[a:b+1],[times[a-1],times[b+1]],[x[a-1],x[b+1]])
            kind='linear_internal'
        else:
            anchor=b+1 if a==0 else a-1
            if not 0<=anchor<n:return x,events,'no_valid_anchor'
            gap=max(abs(times[a]-times[anchor]),abs(times[b]-times[anchor]))
            if gap>policy['max_endpoint_hold_seconds']:return x,events,f'endpoint_gap_seconds={gap:.6f}'
            x[a:b+1]=x[anchor];kind='endpoint_hold'
        events.append({'start_index':a,'end_index':b,'frames':b-a+1,'support_gap_seconds':float(gap),'operation':kind})
    return x,events,None

def derive(base,t):
    return np.column_stack([base,np.gradient(base[:,0],t,edge_order=1),np.gradient(base[:,1],t,edge_order=1),np.abs(base[:,0]-base[:,1]),np.abs(base[:,2]-base[:,3]),t-t[0]])

def summarize(z,t,duration):
    span=t[-1]-t[0]
    avg=lambda x:float(np.trapezoid(x,t)/span)
    a,o,af,of,lean,depth,av,ov,aa,fa,_=z.T
    phase_valid=np.isfinite(a).all()
    peak=int(np.argmin(a)) if phase_valid else -1
    flex=t[peak]-t[0] if phase_valid else np.nan
    extension=t[-1]-t[peak] if phase_valid else np.nan
    flex_exc=a[0]-a[peak] if phase_valid else np.nan
    ext_exc=a[-1]-a[peak] if phase_valid else np.nan
    vals=[a.min(),a.max(),np.ptp(a),o.min(),o.max(),np.ptp(o),duration,
      abs(av).max(),avg(abs(av)),abs(ov).max(),avg(abs(ov)),
      avg(af),af.max(),avg(of),of.max(),avg(aa),aa.max(),avg(fa),fa.max(),
      avg(lean),lean.max(),np.ptp(lean),avg(depth),depth.max(),np.ptp(depth),
      flex,extension,flex/span,a[0],a[-1],flex_exc,ext_exc,(flex_exc/flex if flex>0 else 0) if phase_valid else np.nan,(ext_exc/extension if extension>0 else 0) if phase_valid else np.nan]
    assert len(vals)==len(SCALARS)==34
    return np.array(vals),peak

def distributions(values,names,representation):
    stats=[]
    for j,name in enumerate(names):
        x=values[:,j];finite=x[np.isfinite(x)]
        q1,median,q3=np.quantile(finite,[.25,.5,.75]);iqr=q3-q1
        stats.append({'representation':representation,'feature':name,'count':len(x),'finite':len(finite),'nan':int(np.isnan(x).sum()),'inf':int(np.isinf(x).sum()),'min':float(finite.min()),'p01':float(np.quantile(finite,.01)),'q25':float(q1),'median':float(median),'q75':float(q3),'p99':float(np.quantile(finite,.99)),'max':float(finite.max()),'mean':float(finite.mean()),'std':float(finite.std()),'iqr_low':float(q1-1.5*iqr),'iqr_high':float(q3+1.5*iqr),'outside_1_5_iqr':int(((finite<q1-1.5*iqr)|(finite>q3+1.5*iqr)).sum())})
    return stats

def main():
    lock=verify_config();rows,_=canonical();cfg=config();out=ROOT/'features'
    (out/'per_repetition').mkdir(exist_ok=True)
    raw_by_video={}
    audits=[];repair_events=[];scalar_rows=[];sequences=[];all_scalars=[];failures=[]
    for r in rows:
        vid=r['video_id'];rid=r['repetition_id']
        if vid not in raw_by_video:
            p=ROOT/'preprocessing/raw_landmarks'/f'{vid}.npz'
            a=json.loads((ROOT/'preprocessing'/f'{vid}_audit.json').read_text())
            assert a['status']=='success' and a['raw_landmarks_sha256']==sha(p)
            raw_by_video[vid]=dict(np.load(p))
        d=raw_by_video[vid];a,b=int(r['start_frame']),int(r['end_frame'])
        mask=(d['frame_indices']>=a)&(d['frame_indices']<=b);frames=d['frame_indices'][mask]
        assert np.array_equal(frames,np.arange(a,b+1))
        assert str(d['source_sha256'])==r['source_sha256']
        t=d['source_times'][mask];end=d['source_end_times'][mask][-1];duration=end-t[0]
        assert abs(duration-float(r['duration_sec']))<2e-5
        raw=base_features(d['world_landmarks'][mask],r['hand'],cfg['quality']['minimum_joint_visibility'])
        base=raw.copy();errors=[];repaired=0
        for j,name in enumerate(BASE):
            base[:,j],events,error=repair_channel(raw[:,j],t,cfg['quality'])
            for e in events:
                repair_events.append({'repetition_id':rid,'channel':name,'start_frame':int(frames[e['start_index']]),'end_frame':int(frames[e['end_index']]),**e})
                repaired+=e['frames']
            if error:errors.append(f'{name}: {error}')
        audit={'repetition_id':rid,'video_id':vid,'n_frames':len(t),'duration_sec':duration,'raw_missing_values':int(np.isnan(raw).sum()),'raw_missing_fraction':float(np.isnan(raw).mean()),'repaired_values':repaired,'remaining_missing_values':int(np.isnan(base).sum()),'status':'partial_requires_fold_imputation' if errors else 'success','errors':'; '.join(errors)}
        for j,name in enumerate(BASE):audit[f'{name}_valid_fraction']=float(np.isfinite(raw[:,j]).mean())
        if errors:
            failures.append(dict(audit))
        z=derive(base,t);scalars,peak=summarize(z,t,duration)
        grid=np.linspace(t[0],t[-1],cfg['representation']['temporal_length'])
        sequence=np.column_stack([np.interp(grid,t,z[:,j]) for j in range(z.shape[1])]).astype(np.float32)
        assert not np.isinf(sequence).any() and not np.isinf(scalars).any()
        audit.update({'phase_minimum_frame':int(frames[peak]) if peak>=0 else None,'phase_minimum_at_endpoint':peak in [0,len(t)-1],'phase_unavailable':peak<0,'active_peak_abs_velocity':float(scalars[7]),'opposing_peak_abs_velocity':float(scalars[9])})
        audits.append(audit);all_scalars.append(scalars);sequences.append(sequence)
        scalar_rows.append({'repetition_id':rid,**dict(zip(SCALARS,scalars))})
        np.savez_compressed(out/'per_repetition'/f'{rid}.npz',frame_indices=frames,source_times=t,raw_base_features=raw,repaired_base_features=base,kinematics=z,resample_times=grid,sequence=sequence)
    # Uniform columns for failed and successful records.
    pd.DataFrame(audits).to_csv(out/'feature_quality_audit.csv',index=False)
    pd.DataFrame(repair_events,columns=['repetition_id','channel','start_frame','end_frame','start_index','end_index','frames','support_gap_seconds','operation']).to_csv(out/'repair_operations.csv',index=False)
    # Unsupported intervals remain NaN. Training-fold mean imputation is explicit,
    # never a fabricated landmark/movement repair and never fit on held-out rows.
    dump(out/'partial_feature_records.json',failures)
    scalar=np.array(all_scalars);seq=np.array(sequences)
    assert scalar.shape==(280,34) and seq.shape==(280,128,11)
    pd.DataFrame(scalar_rows).to_csv(out/'scalar_features.csv',index=False)
    np.savez_compressed(out/'model_ready.npz',repetition_ids=np.array([r['repetition_id'] for r in rows]),scalar=scalar,sequence=seq,scalar_names=np.array(SCALARS),temporal_names=np.array(CHANNELS),manifest_sha256=lock['manifest_sha256'],feature_version=cfg['feature_version'])
    stats=distributions(scalar,SCALARS,'scalar')+distributions(seq.reshape(-1,11),CHANNELS,'temporal_resampled')
    write_csv(out/'feature_distributions.csv',stats)
    dump(out/'feature_validation.json',{'canonical_examples':280,'successful':280,'fully_supported':280-len(failures),'partial_requires_fold_imputation':len(failures),'failed':0,'scalar_shape':list(scalar.shape),'temporal_shape':list(seq.shape),'nan':int(np.isnan(scalar).sum()+np.isnan(seq).sum()),'scalar_nan':int(np.isnan(scalar).sum()),'temporal_nan':int(np.isnan(seq).sum()),'inf':int(np.isinf(scalar).sum()+np.isinf(seq).sum()),'missing_policy':'Explicit pre-fold NaNs; mean imputation fit only on each outer training fold, with finite checks after transformation. No QC indicators as predictors. Scalar summaries involving unsupported intervals stay NaN, including unavailable phases.','repetitions_repaired':sum(a['repaired_values']>0 for a in audits),'values_repaired':sum(a['repaired_values'] for a in audits),'endpoint_phase_minimum_count':sum(a['phase_minimum_at_endpoint'] for a in audits),'phase_unavailable_count':sum(a['phase_unavailable'] for a in audits),'outliers_policy':'Descriptive 1.5 IQR counts only; no removal/clipping or feature selection','model_ready_sha256':sha(out/'model_ready.npz'),'build_script_sha256':sha(__file__),'raw_landmark_files':{vid:sha(ROOT/'preprocessing/raw_landmarks'/f'{vid}.npz') for vid in raw_by_video}})
    print(json.dumps({'success':280,'shape_scalar':list(scalar.shape),'shape_temporal':list(seq.shape),'repaired_values':sum(a['repaired_values'] for a in audits)}))

if __name__=='__main__':main()
