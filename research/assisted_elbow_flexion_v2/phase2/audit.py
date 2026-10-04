"""Diagnostic audits of frozen predictions and fresh Phase 1 measurements."""
import json
import numpy as np
import pandas as pd
import joblib
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from phase2_utils import P1,P2,DATA,inputs,verify_inputs,dump,sha,eta_squared,finite_summary,metrics

def interpretation(name):
    phase=any(k in name for k in ['flexion','extension'])
    velocity='velocity' in name or 'speed' in name
    view='torso' in name or 'shoulder_depth' in name
    flare='flare' in name
    elapsed=name in ['duration','elapsed_seconds']
    asym='asymmetry' in name
    if view:
        desc='Camera-axis torso orientation proxy' if 'torso' in name else 'Absolute shoulder depth / 3D shoulder width'
        inv='Not rotation-invariant to camera/view; estimated world coordinate frame is camera-dependent'
    elif flare:
        desc='Anatomical shoulder-axis elbow displacement / shoulder width; arm difference for asymmetry'
        inv='Ideal 3D rigid-rotation and scale invariant; monocular depth, occlusion and width estimates remain view-sensitive'
    elif elapsed:
        desc='Reviewed interval duration or elapsed presentation time'
        inv='Geometrically invariant; segmentation and execution/recording pace dependent'
    elif phase:
        desc='Operational first-global-minimum phase timing, excursion or excursion/time'
        inv='Ideal angle invariant; depends on reviewed boundaries, multiple cycles and depth estimates'
    elif velocity:
        desc='Elbow angle derivative using original PTS, absolute peak or time-weighted mean'
        inv='Ideal angle invariant; view-sensitive estimated 3D joints, timing and pose jitter'
    else:
        desc='3D elbow angle summary or bilateral angle difference'
        inv='Ideal rigid-rotation/scale invariant; monocular joint estimation may change with view/occlusion'
    units='deg/s' if velocity else 'ratio' if flare or 'shoulder_depth' in name or name=='flexion_fraction' else 's' if elapsed or name.endswith('_duration') else 'deg'
    jitter='High: differentiation amplifies frame noise; extrema especially sensitive' if velocity else 'High: unstable global minimum changes phase' if phase else 'Moderate/high for extrema and endpoints' if ('max' in name or 'min' in name or 'start' in name or 'end' in name or 'rom' in name or 'range' in name) else 'Moderate: temporal averages reduce isolated spikes' if not elapsed else 'Low landmark sensitivity; boundary timing remains relevant'
    duration='Direct duration dependence' if elapsed or name.endswith('_duration') else 'Inverse phase-time dependence and unstable short denominator' if name.endswith('_speed') else 'Execution pace directly affects velocity' if velocity else 'Longer intervals offer more chances for extrema / change phase or endpoints' if phase or any(k in name for k in ['max','min','start','end','rom']) else 'Indirect: movement content and temporal weighting'
    missing='Timestamp-based; no pose imputation needed' if elapsed else 'Invalid participating joints become NaN; bounded recorded repairs; unsupported dependent summaries use training-fold imputation'
    return {'physical_interpretation':desc,'units':units,'expected_camera_view_invariance':inv,'jitter_sensitivity':jitter,'missing_landmark_sensitivity':missing,'duration_sensitivity':duration,'potential_recording_style_proxy':'Direct view/setup proxy' if view else 'Pace/boundary proxy possible' if elapsed or phase or velocity else 'Possible through monocular view, participant anatomy/pose estimation and task composition'}

def main():
    verify_inputs();df,d,pred=inputs();names=d['scalar_names'].tolist();x=d['scalar'];y=(df.label=='Incorrect').astype(int).to_numpy()
    qc=pd.read_csv(P1/'features/feature_quality_audit.csv')
    ext=pd.read_csv(P1/'preprocessing/repetition_extraction_audit.csv')
    repairs=pd.read_csv(P1/'features/repair_operations.csv')
    rep_records=[];kin={};raws={}
    for i,r in df.iterrows():
        z=dict(np.load(P1/'features/per_repetition'/f'{r.repetition_id}.npz'));kin[r.repetition_id]=z
        v=z['kinematics'][:,6];ov=z['kinematics'][:,7]
        # A complete-channel variant must not pretend an incomplete interval was observed.
        p95=float(np.quantile(abs(v),.95)) if np.isfinite(v).all() else np.nan
        op95=float(np.quantile(abs(ov),.95)) if np.isfinite(ov).all() else np.nan
        a=z['kinematics'][:,0];t=z['source_times'];veldiff=np.diff(v)/np.diff(t)
        q=qc.loc[qc.repetition_id==r.repetition_id].iloc[0]
        events=repairs[repairs.repetition_id==r.repetition_id]
        rep_records.append({'repetition_id':r.repetition_id,'video_id':r.video_id,'source_sha256':r.source_sha256,'subject_id':r.subject_id,'hand':r.hand,'label':r.label,'active_velocity_p95':p95,'opposing_velocity_p95':op95,'active_peak_to_p95_ratio':float(np.nanmax(abs(v))/p95) if p95>0 else np.nan,'active_max_adjacent_angle_jump':float(np.nanmax(abs(np.diff(a)))),'active_median_abs_acceleration':float(np.nanmedian(abs(veldiff))),'repair_operations':len(events),'repair_support_max_seconds':float(events.support_gap_seconds.max()) if len(events) else 0.,'repair_channels':';'.join(sorted(events.channel.unique())),'repair_operations_detail':events.to_json(orient='records'),'feature_qc_status':q.status,'raw_missing_fraction':q.raw_missing_fraction,'repaired_values':int(q.repaired_values),'remaining_missing_values':int(q.remaining_missing_values),'phase_minimum_at_endpoint':bool(q.phase_minimum_at_endpoint),'phase_unavailable':bool(q.phase_unavailable),'phase_minimum_frame':q.phase_minimum_frame,'n_frames':int(q.n_frames),'duration_sec':q.duration_sec})
    rep=pd.DataFrame(rep_records);rep.to_csv(P2/'audits/repetition_diagnostics.csv',index=False)
    scalar=pd.DataFrame(x,columns=names);scalar.insert(0,'repetition_id',df.repetition_id)
    # Train references are from each frozen outer fold. They are descriptive,
    # not invented medical cutoffs or replacement quality labels.
    refs={}
    for f in range(5):
        tr=df.fold.to_numpy()!=f;correct=tr&(y==0);incorrect=tr&(y==1)
        refs[f]={n:{'correct_p10':float(np.nanquantile(x[correct,j],.1)),'correct_p90':float(np.nanquantile(x[correct,j],.9)),'overlap_low':max(float(np.nanquantile(x[correct,j],.25)),float(np.nanquantile(x[incorrect,j],.25))),'overlap_high':min(float(np.nanquantile(x[correct,j],.75)),float(np.nanquantile(x[incorrect,j],.75)))} for j,n in enumerate(names)}
    dump(P2/'audits/training_fold_feature_references.json',refs)
    joined=df.merge(pred[['repetition_id','predicted_label','incorrect_score','is_correct']],on='repetition_id').merge(scalar,on='repetition_id').merge(rep.drop(columns=['video_id','source_sha256','subject_id','hand','label']),on='repetition_id').merge(ext[['repetition_id','pose_available_frames','core_joint_visibility_mean','core_joint_visibility_min','core_joint_below_0_5_fraction']],on='repetition_id')
    errors=[]
    for _,r in joined[~joined.is_correct].iterrows():
        ref=refs[int(r.fold)];tags=[];evidence=[]
        if r.raw_missing_fraction>0 or r.repaired_values>0:
            tags.append('visibility_or_repair');evidence.append(f'raw missing fraction={r.raw_missing_fraction:.4f}; repaired values={r.repaired_values}; remaining={r.remaining_missing_values}')
        if r.phase_minimum_at_endpoint or r.phase_unavailable:
            tags.append('phase_definition_issue');evidence.append('endpoint minimum or unavailable phase')
        if r.active_peak_to_p95_ratio>3 and r.active_max_adjacent_angle_jump>10:
            tags.append('jitter_like_angular_spike');evidence.append(f'peak/p95={r.active_peak_to_p95_ratio:.2f}, adjacent angle jump={r.active_max_adjacent_angle_jump:.2f} deg; possible fast motion or estimation spike, not confirmed pose failure')
        for feature,condition,tag in [('active_min_angle','high','shallow_measured_flexion'),('active_rom','low','small_measured_excursion'),('active_mean_flare','high','high_flare_proxy'),('active_mean_abs_velocity','high','high_mean_angular_speed'),('mean_torso_lean','high','high_torso_view_proxy')]:
            value=r[feature];bound=ref[feature]['correct_p90' if condition=='high' else 'correct_p10']
            if np.isfinite(value) and ((value>bound) if condition=='high' else (value<bound)):
                tags.append(tag);evidence.append(f'{feature}={value:.4f} {condition} relative to training Correct reference={bound:.4f}; descriptive only')
        overlaps=[n for n in ['active_min_angle','active_rom','active_mean_flare','active_mean_abs_velocity','mean_torso_lean'] if ref[n]['overlap_low']<=r[n]<=ref[n]['overlap_high']]
        if overlaps:tags.append('overlapping_biomechanical_signal');evidence.append('inside training class-IQR intersection: '+','.join(overlaps))
        if not tags:tags=['weak_or_unexplained_measured_signal'];evidence=['No prespecified descriptive QC/reference flag; cause unresolved']
        row=r.to_dict();row.update({'svm_score_type':'signed uncalibrated decision_function; positive=Incorrect','svm_near_boundary_abs_score_le_0_25':abs(r.incorrect_score)<=.25,'biomechanical_decision_boundary_status':'Not established: no validated biomechanical quality cutoffs for these world-coordinate features','training_class_iqr_overlap_features':';'.join(overlaps),'descriptive_mechanism_tags':';'.join(tags),'primary_descriptive_category':tags[0],'mechanism_evidence':' | '.join(evidence),'clinical_cause_established':False,'source_appearance_or_setup_cause':'Not established; see source profiles and recording thumbnails'})
        errors.append(row)
        z=kin[r.repetition_id];t=z['source_times']-z['source_times'][0]
        fig,axes=plt.subplots(3,1,figsize=(9,7),sharex=True,constrained_layout=True)
        for j,label in [(0,'active'),(1,'opposing')]:
            axes[0].plot(t,z['raw_base_features'][:,j],label=label+' raw',alpha=.65)
            axes[0].plot(t,z['repaired_base_features'][:,j],label=label+' repaired',ls='--',alpha=.65)
        axes[0].set_ylabel('Elbow angle (deg)');axes[0].legend(ncol=2,fontsize=8)
        axes[1].plot(t,z['kinematics'][:,6],label='active');axes[1].plot(t,z['kinematics'][:,7],label='opposing');axes[1].set_ylabel('Velocity (deg/s)');axes[1].legend()
        axes[2].plot(t,z['kinematics'][:,2],label='active flare');axes[2].plot(t,z['kinematics'][:,3],label='opposing flare');axes[2].set_ylabel('Flare ratio');axes[2].set_xlabel('Seconds from reviewed start');axes[2].legend()
        fig.suptitle(f'{r.repetition_id}\n{r.hand}: human {r.label} / predicted {r.predicted_label}; score {r.incorrect_score:.3f}')
        fig.savefig(P2/'plots/errors'/f'{r.repetition_id}.png',dpi=130);plt.close(fig)
    error=pd.DataFrame(errors);assert len(error)==36
    error.to_csv(P2/'error_analysis.csv',index=False)
    feature_rows=[]
    for representation,values,fs in [('scalar',x,names),('temporal',np.nanmean(d['sequence'],axis=1),d['temporal_names'].tolist())]:
        for j,n in enumerate(fs):
            v=values[:,j];residual=v.copy()
            for label in [0,1]:residual[y==label]-=np.nanmean(v[y==label])
            feature_rows.append({'representation':representation,'feature':n,**interpretation(n),'source_eta_squared':eta_squared(v,df.source_sha256),'source_eta_squared_after_class_mean_subtraction':eta_squared(residual,df.source_sha256),'hand_eta_squared':eta_squared(v,df.hand),'finite_repetitions':int(np.isfinite(v).sum()),'missing_repetitions':int(np.isnan(v).sum()),**finite_summary(v),'recommendation':'Test removal as a single view-proxy ablation; do not assume signal is spurious' if ('torso' in n or 'shoulder_depth' in n) else 'Test time-weighted p95 replacement for isolated extrema' if 'peak' in n else 'Retain for now; outliers or source association alone do not establish artifact','causal_artifact_established':False})
    robustness=pd.DataFrame(feature_rows);robustness.to_csv(P2/'feature_robustness.csv',index=False)
    inventory=pd.read_csv(DATA/'video_inventory.csv').set_index('video_id')
    global_median=np.nanmedian(x,axis=0);iqr=np.nanquantile(x,.75,axis=0)-np.nanquantile(x,.25,axis=0);iqr=np.where(iqr>1e-10,iqr/1.349,1.)
    source_rows=[];source_distributions=[]
    for vid,g in df.groupby('video_id',sort=True):
        idx=g.index.to_numpy();mask=pred.video_id==vid;pp=pred[mask];rp=rep[rep.video_id==vid];ee=ext[ext.video_id==vid]
        raw=dict(np.load(P1/'preprocessing/raw_landmarks'/f'{vid}.npz'));raws[vid]=raw
        img=raw['image_landmarks'];world=raw['world_landmarks'];w,h=raw['image_size'];mid_s=(img[:,11,:2]+img[:,12,:2])/2;mid_h=(img[:,23,:2]+img[:,24,:2])/2
        torso_px=np.linalg.norm((mid_s-mid_h)*np.array([w,h]),axis=1)
        sw=np.linalg.norm(world[:,12,:3]-world[:,11,:3],axis=1)
        source_med=np.nanmedian(x[idx],axis=0);shift=(source_med-global_median)/iqr
        largest=np.argsort(np.nan_to_num(abs(shift),nan=-1))[-5:][::-1]
        mm=finite_summary(rp.duration_sec)
        record={'video_id':vid,'source_video':g.source_video.iloc[0],'source_sha256':g.source_sha256.iloc[0],'inherited_subject_id':';'.join(sorted(g.subject_id.unique())),'subject_verified':False,'fold':int(g.fold.iloc[0]),'n_repetitions':len(g),'Correct':int((g.label=='Correct').sum()),'Incorrect':int((g.label=='Incorrect').sum()),'Left':int((g.hand=='Left').sum()),'Right':int((g.hand=='Right').sum()),**metrics(pp.y_true,pp.y_pred),'core_joint_visibility_mean':float(ee.core_joint_visibility_mean.mean()),'core_joint_visibility_min':float(ee.core_joint_visibility_min.min()),'core_joint_low_visibility_fraction_mean':float(ee.core_joint_below_0_5_fraction.mean()),'repetitions_repaired':int((rp.repaired_values>0).sum()),'repair_frequency':float((rp.repaired_values>0).mean()),'repaired_values':int(rp.repaired_values.sum()),'partial_representations':int((rp.remaining_missing_values>0).sum()),'phase_unavailable':int(rp.phase_unavailable.sum()),'phase_endpoint_minimum':int(rp.phase_minimum_at_endpoint.sum()),'active_peak_to_p95_ratio_median':float(rp.active_peak_to_p95_ratio.median()),'image_torso_length_px_at_640_mean':float(np.nanmean(torso_px)),'estimated_world_shoulder_width_m_mean':float(np.nanmean(sw)),'source_width':int(inventory.loc[vid,'width']),'source_height':int(inventory.loc[vid,'height']),'source_reported_fps':float(inventory.loc[vid,'fps']),'top_global_robust_median_shifts':'; '.join(f'{names[j]}={shift[j]:+.2f} robust SD' for j in largest),'setup_or_participant_cause_established':False}
        for k,v in mm.items():record['duration_'+k]=v
        for j,n in enumerate(names):
            record['mean_'+n]=float(np.nanmean(x[idx,j])) if np.isfinite(x[idx,j]).any() else np.nan
            source_distributions.append({'video_id':vid,'feature':n,**finite_summary(x[idx,j]),'global_robust_median_shift':float(shift[j])})
        source_rows.append(record)
    sources=pd.DataFrame(source_rows);sources.to_csv(P2/'source_failure_analysis.csv',index=False)
    pd.DataFrame(source_distributions).to_csv(P2/'audits/source_feature_distributions.csv',index=False)
    hand=[]
    for j,n in enumerate(names):
        l=x[df.hand=='Left',j];r=x[df.hand=='Right',j]
        hand.append({'feature':n,'Left_mean':float(np.nanmean(l)),'Right_mean':float(np.nanmean(r)),'Left_median':float(np.nanmedian(l)),'Right_median':float(np.nanmedian(r)),'median_difference_in_global_robust_sd':float((np.nanmedian(l)-np.nanmedian(r))/iqr[j]),'hand_eta_squared':eta_squared(x[:,j],df.hand)})
    pd.DataFrame(hand).to_csv(P2/'audits/hand_feature_distributions.csv',index=False)
    error.primary_descriptive_category.value_counts().rename_axis('category').reset_index(name='errors').to_csv(P2/'audits/error_category_counts.csv',index=False)
    fig,ax=plt.subplots(figsize=(10,6),constrained_layout=True)
    s=sources.sort_values('accuracy');ax.barh(s.video_id,s.accuracy*100,color=['#cc5555' if a<.8 else '#397d89' for a in s.accuracy]);ax.set_xlabel('Frozen SVM held-out accuracy (%)');ax.set_title('All 29 source videos; each evaluated in its frozen fold');fig.savefig(P2/'plots/source_accuracy.png',dpi=160);plt.close(fig)
    fig,axes=plt.subplots(1,2,figsize=(11,4),constrained_layout=True)
    axes[0].scatter(rep.active_velocity_p95,x[:,names.index('active_peak_abs_velocity')],c=(~pred.is_correct).astype(int),cmap='coolwarm');axes[0].set_xlabel('Active velocity p95 (deg/s)');axes[0].set_ylabel('Active peak (deg/s)');axes[0].set_title('Red: frozen SVM error; blue: correct')
    top=robustness[robustness.representation=='scalar'].sort_values('source_eta_squared_after_class_mean_subtraction').tail(10);axes[1].barh(top.feature,top.source_eta_squared_after_class_mean_subtraction);axes[1].set_xlabel('Source η² after class-mean subtraction');axes[1].set_title('Residual source association; not causal attribution')
    fig.savefig(P2/'plots/velocity_and_source_shift.png',dpi=160);plt.close(fig)
    summary={'canonical_examples':280,'errors':36,'source_count':29,'both_class_sources':int(((sources.Correct>0)&(sources.Incorrect>0)).sum()),'only_correct_sources':int(((sources.Correct>0)&(sources.Incorrect==0)).sum()),'only_incorrect_sources':int(((sources.Correct==0)&(sources.Incorrect>0)).sum()),'error_repaired_count':int((error.repaired_values>0).sum()),'error_partial_count':int((error.remaining_missing_values>0).sum()),'near_svm_margin_errors':int(error.svm_near_boundary_abs_score_le_0_25.sum()),'error_endpoint_or_unavailable_phase_count':int((error.phase_minimum_at_endpoint|error.phase_unavailable).sum()),'active_peak_to_p95_ratio_median':float(rep.active_peak_to_p95_ratio.median()),'active_peak_to_p95_ratio_max':float(rep.active_peak_to_p95_ratio.max()),'view_feature_source_eta_squared':robustness[(robustness.representation=='scalar')&robustness.feature.str.contains('torso|shoulder_depth')][['feature','source_eta_squared','source_eta_squared_after_class_mean_subtraction']].to_dict(orient='records'),'audit_script_sha256':sha(__file__),'audit_outputs_hashes':{str(p.relative_to(P2)):sha(p) for p in [P2/'error_analysis.csv',P2/'source_failure_analysis.csv',P2/'feature_robustness.csv',P2/'audits/repetition_diagnostics.csv']}}
    dump(P2/'audits/AUDIT_COMPLETE.json',summary)
    print(json.dumps(summary,indent=2))

if __name__=='__main__':main()
