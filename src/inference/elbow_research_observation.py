"""Conservative research assessment with external camera roll and support QC.

This layer returns research suggestions, never verified clinical pass/fail.
Its camera reference must come from camera-aligned orientation measurements or
an externally verified fixed setup. A neutral patient pose is not a gravity
reference. It does not establish contact force, observed arm identity, camera
yaw suitability, or clinician-approved range completion.
"""
from dataclasses import dataclass
import numpy as np
from src.features import elbow_research_v5 as form
from src.features import elbow_research_v7 as quality

@dataclass(frozen=True)
class CameraCalibration:
    roll_degrees:float | None=None
    verified:bool=False
    source:str='unavailable'

def observation_guard(raw,image,width,height,times,hand,mask):
    """Experimental evidence gate; never a movement correctness threshold.

    Phase location uses the independently visible active arm, so hiding the
    support arm cannot move the peak to a better-observed part of the cycle.
    """
    observed=np.isfinite(raw[:,quality.REQUIRED_IMAGE_CHANNELS]).all(axis=1)
    seen=observed[mask];local_times=times[mask]
    padded=np.r_[False,~seen,False].astype(int)
    starts=np.flatnonzero(np.diff(padded)==1)
    ends=np.flatnonzero(np.diff(padded)==-1)-1
    dt=float(np.median(np.diff(local_times)))
    longest=max((local_times[b]-local_times[a]+dt for a,b in zip(starts,ends)),default=0.)
    s,e,w=(11,13,15) if hand=='Left' else (12,14,16)
    xy=np.asarray(image,float)[:,:,:2]*[width,height]
    active=quality._angle_2d(xy[:,s],xy[:,e],xy[:,w])
    visible=quality.valid_points(image,[s,e,w],minimum=.5)
    visible &= ((image[:,[s,e,w],:2]>=0.)&(image[:,[s,e,w],:2]<=1.)).all(axis=(1,2))
    active[~visible]=np.nan
    measured=quality.causal_trace(active[:,None],times)[mask,0]
    if not np.isfinite(measured).any():return {'reason':'active_phase_unavailable'}
    peak=int(np.flatnonzero(np.isfinite(measured)&(measured<=np.nanmin(measured)+1e-5))[0])
    stage_masks={'start':local_times-local_times[0]<=.2,
                 'peak':abs(local_times-local_times[peak])<=.2,
                 'end':local_times[-1]-local_times<=.2}
    for name,stage in stage_masks.items():
        if stage.sum()<3:
            anchor={'start':0,'peak':peak,'end':len(stage)-1}[name]
            stage[np.argsort(abs(np.arange(len(stage))-anchor))[:3]]=True
    coverage={name:float(seen[stage].mean()) for name,stage in stage_masks.items()}
    reason='required_arm_tracking_gap' if longest>.30+1e-9 else (
        'critical_stage_support_visibility' if min(coverage.values())<.8 else None)
    return {'reason':reason,'longest_required_arm_gap_seconds':float(longest),
            'independent_active_peak_time':float(local_times[peak]),
            'critical_stage_both_arm_coverage':coverage}

def canonical_camera_pose(world,image,width,height,roll_degrees):
    """Derotate into a padded virtual canvas without clipping observations.

    Input x/y coordinates use normalized image units; width/height are pixels.
    Positive supplied roll rotates a rightward pixel vector toward increasing
    image y (clockwise on a y-down screen). Caller must map phone-sensor axes
    and timestamps to this exact convention. Visibility is preserved here;
    assess_cycle carries original-frame observation validity through padding.
    """
    if not np.isfinite(roll_degrees) or abs(roll_degrees)>30.:
        raise ValueError('Camera roll is outside this research supported range')
    if min(width,height)<=0 or not np.isfinite([width,height]).all():raise ValueError('Invalid dimensions')
    world=np.asarray(world,float).copy();image=np.asarray(image,float).copy()
    angle=np.deg2rad(-float(roll_degrees));c,s=np.cos(angle),np.sin(angle)
    R=np.array([[c,-s],[s,c]])
    new_width=abs(c)*width+abs(s)*height;new_height=abs(s)*width+abs(c)*height
    xy=image[:,:,:2]*[width,height]-[width/2,height/2]
    image[:,:,:2]=(xy@R.T+[new_width/2,new_height/2])/[new_width,new_height]
    # A rigid x/y rotation leaves world joint angles/lengths unchanged. No claim
    # that this supplies a correct world-camera extrinsic calibration is made.
    world[:,:,:2]=world[:,:,:2]@R.T
    return world,image,new_width,new_height

def assess_cycle(model,world,image,width,height,times,hand,start,end,calibration=None):
    """Full-video causal measurements, then completed-cycle research suggestion."""
    calibration=calibration or CameraCalibration()
    times=np.asarray(times,float);mask=(times>=start)&(times<=end)
    result={'status':'unassessed','research_label':None,'hand_hypothesis':hand,
        'observed_arm_verified':False,'clinical_pass_fail_verified':False,
        'support_contact_verified':False,'probability_calibrated':False}
    if mask.sum()<8:return {**result,'reason':'insufficient_cycle_samples'}
    # Check original observed image before geometric derotation/padding.
    raw=quality.channels(world,image,width,height,hand);trace=quality.causal_trace(raw,times)
    feature,qc=quality.rep_features(trace[mask],times[mask]);result['observation_qc']=qc
    if feature is None:return {**result,'reason':qc['reason']}
    stage_qc=observation_guard(raw,image,width,height,times,hand,mask)
    result['observation_qc']={**qc,**stage_qc}
    if stage_qc['reason']:return {**result,'reason':stage_qc['reason']}
    allowed_sources={'imu_camera_aligned','fixed_view_verified'}
    if not calibration.verified or calibration.roll_degrees is None or calibration.source not in allowed_sources:
        return {**result,'status':'review_required','reason':'external_camera_reference_required'}
    try:w,img,W,H=canonical_camera_pose(world,image,width,height,calibration.roll_degrees)
    except ValueError as error:return {**result,'reason':'unsupported_camera_calibration','detail':str(error)}
    # Padding is a coordinate operation, never new observation evidence. A
    # high-confidence extrapolated joint outside the ORIGINAL frame must stay
    # unavailable even if its rotated coordinates lie inside the padded canvas.
    observed=np.isfinite(raw[:,quality.REQUIRED_IMAGE_CHANNELS]).all(axis=1)
    for corrected in (w,img):
        corrected[np.ix_(~observed,[11,12,13,14,15,16],[3])]=0.
    result['original_unobserved_cycle_frames']=int((~observed[mask]).sum())
    features,qc_form=form.rep_features(form.causal_trace(form.channels(w,img,W,H,hand),times)[mask],times[mask])
    if features is None:return {**result,'reason':qc_form['reason']}
    prediction=int(model.predict(features[None])[0])
    return {**result,'status':'research_suggestion','reason':'not_validated_for_clinical_pass_fail',
        'research_label':['Correct','Incorrect'][prediction],
        'camera_reference':{'roll_degrees':calibration.roll_degrees,'source':calibration.source},
        'measured_image_excursion_degrees':float(feature[quality.NAMES.index('active_angle_excursion')]),
        'support_segment_distance_ratio':float(feature[quality.NAMES.index('support_segment_median')]),
        'support_wrist_distance_ratio':float(feature[quality.NAMES.index('support_wrist_median')]),
        'limitations':['Projected support proximity is not physical contact or assistance force.',
            'This hand hypothesis is not independent observed-arm confirmation.',
            'Therapeutic angle targets require clinician-approved metadata and validation.']}
