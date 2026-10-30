"""Stage-aware research features shared by replay and candidate training.

No clinical angle prescriptions. Image landmark x/y use equal pixel units.
Only causal smoothing is used; invalid observations remain missing.
"""
import numpy as np
from sklearn.base import BaseEstimator, TransformerMixin

ANGLE_NAMES = ['angle_2d','angle_3d','opposing_angle_2d']
FORM_NAMES = ['upper_arm_2d','elbow_lateral','support_wrist','support_forearm',
              'torso_lean','shoulder_tilt']
NAMES = [name+'_'+summary for name in ANGLE_NAMES
         for summary in ['p10','p90','rom','start','end','return_fraction','closure_fraction','peak_fraction']]
NAMES += [name+'_'+summary for name in FORM_NAMES
          for summary in ['p50','p90','variation','flex_p50','return_p50']]
NAMES += ['duration','flexion_fraction','monotonic_flex_fraction','monotonic_return_fraction']

class FeatureView(TransformerMixin,BaseEstimator):
    def __init__(self,view='all'):self.view=view
    def fit(self,X,y=None):self.n_features_in_=X.shape[1];return self
    def transform(self,X):
        if self.view=='all':return X
        if self.view=='compact':
            indices=[0,1,2,5,6,8,9,10,13,14,24,25,26,29,30,34,35,39,40,44,45,49,50,55,56,57]
        elif self.view=='image':indices=list(range(8))+list(range(16,len(NAMES)))
        else:raise ValueError('Unknown feature view')
        return X[:,indices]

def angle(a,b,c):
    u,v=a-b,c-b
    den=np.linalg.norm(u,axis=-1)*np.linalg.norm(v,axis=-1)
    return np.degrees(np.arccos(np.clip(np.sum(u*v,axis=-1)/np.where(den>1e-8,den,np.nan),-1,1)))

def valid_points(a,indices,minimum=.5):
    return np.isfinite(a[:,indices,:]).all(axis=(1,2)) & (a[:,indices,3]>=minimum).all(axis=1)

def channels(world,image,width=960,height=540,hand='Left'):
    if hand not in ('Left','Right'):raise ValueError('Invalid active side')
    s,e,w=(11,13,15) if hand=='Left' else (12,14,16)
    os,oe,ow=(12,14,16) if hand=='Left' else (11,13,15)
    xy=image[:,:,:2]*np.array([width,height])
    xyz=world[:,:,:3]
    shoulder=(xy[:,11]+xy[:,12])/2
    hips=(xy[:,23]+xy[:,24])/2
    torso=hips-shoulder
    torso_len=np.linalg.norm(torso,axis=1)
    torso_len=np.where(torso_len>1e-5,torso_len,np.nan)
    forearm=xy[:,w]-xy[:,e]
    forearm_len=np.linalg.norm(forearm,axis=1)
    forearm_len=np.where(forearm_len>1e-5,forearm_len,np.nan)
    fraction=np.clip(np.sum((xy[:,ow]-xy[:,e])*forearm,axis=1)/forearm_len**2,0,1)
    support_projected=xy[:,e]+fraction[:,None]*forearm
    # Cross product in image plane, divided by body lengths, is scale independent.
    upper=xy[:,e]-xy[:,s]
    lateral=np.abs(upper[:,0]*torso[:,1]-upper[:,1]*torso[:,0])/torso_len**2
    shoulders=xy[:,12]-xy[:,11]
    values=np.column_stack([
        angle(xy[:,s],xy[:,e],xy[:,w]),angle(xyz[:,s],xyz[:,e],xyz[:,w]),
        angle(xy[:,os],xy[:,oe],xy[:,ow]),angle(xy[:,e],xy[:,s],xy[:,s]+torso),lateral,
        np.linalg.norm(xy[:,ow]-xy[:,w],axis=1)/forearm_len,
        np.linalg.norm(xy[:,ow]-support_projected,axis=1)/forearm_len,
        np.abs(np.degrees(np.arctan2(torso[:,0],torso[:,1]))),
        np.degrees(np.arctan2(np.abs(shoulders[:,1]),np.abs(shoulders[:,0])))])
    requirements=[(image,[s,e,w],.5),(world,[s,e,w],.5),(image,[os,oe,ow],.5),
        (image,[s,e,11,12,23,24],.35),(image,[s,e,11,12,23,24],.35),
        (image,[e,w,ow],.5),(image,[e,w,ow],.5),(image,[11,12,23,24],.35),(image,[11,12],.5)]
    for j,(source,indices,threshold) in enumerate(requirements):
        values[~valid_points(source,indices,threshold),j]=np.nan
    values[~np.isfinite(values)]=np.nan
    return values

class CausalSmoother:
    def __init__(self,time_constant=.12,max_gap=.30):
        self.tau=time_constant;self.max_gap=max_gap;self.reset()
    def reset(self):
        self.previous=None;self.previous_time=None;self.last_valid=None
    def update(self,row,t):
        row=np.asarray(row,dtype=float)
        if self.previous_time is not None and t<=self.previous_time:
            raise ValueError('Timestamps must strictly increase')
        if self.previous is None:
            self.previous=row.copy();self.last_valid=np.where(np.isfinite(row),t,np.nan)
        else:
            dt=t-self.previous_time
            alpha=1-np.exp(-dt/self.tau)
            seen=np.isfinite(row)
            fresh=seen&(~np.isfinite(self.previous)|~np.isfinite(self.last_valid)|(t-self.last_valid>self.max_gap))
            smooth=seen&~fresh
            self.previous[fresh]=row[fresh]
            self.previous[smooth]+=alpha*(row[smooth]-self.previous[smooth])
            self.last_valid[seen]=t
        self.previous_time=t
        # Never present hidden/occluded points as observations.
        return np.where(np.isfinite(row),self.previous,np.nan)

def causal_trace(raw,times):
    smoother=CausalSmoother()
    return np.asarray([smoother.update(row,float(t)) for row,t in zip(raw,times)])

def quantile(x,p):
    good=np.asarray(x);good=good[np.isfinite(good)]
    return float(np.quantile(good,p)) if len(good)>=3 else np.nan

def rep_features(trace,times):
    if len(times)<8 or len(trace)!=len(times):raise ValueError('Insufficient window')
    primary=trace[:,1] # Estimated 3D elbow angle determines shared movement phases.
    finite=np.isfinite(primary)
    if finite.mean()<.8:return None,{'reason':'insufficient_active_arm_visibility'}
    peak=int(np.nanargmin(primary))
    duration=float(times[-1]-times[0]);phase_fraction=(times[peak]-times[0])/duration
    edge=max(2,int(len(times)*.10))
    result=[]
    for j in range(3):
        x=trace[:,j];low,high=quantile(x,.1),quantile(x,.9);rom=high-low
        start,end=quantile(x[:edge],.5),quantile(x[-edge:],.5)
        local_peak=int(np.nanargmin(x)) if np.isfinite(x).any() else 0
        minimum=quantile(x,.05)
        result.extend([low,high,rom,start,end,(end-minimum)/max(start-minimum,5.),
                       abs(end-start)/max(rom,5.),(times[local_peak]-times[0])/duration])
    for j in range(3,9):
        x=trace[:,j]
        result.extend([quantile(x,.5),quantile(x,.9),quantile(x,.9)-quantile(x,.1),
                       quantile(x[:peak+1],.5),quantile(x[peak:],.5)])
    # Ignore sub-degree frame changes instead of learning camera noise spikes.
    def direction_fraction(a,expected):
        d=np.diff(a);d=d[np.isfinite(d)&(abs(d)>1.)]
        return float(np.mean(d*expected>0)) if len(d) else np.nan
    result.extend([duration,phase_fraction,direction_fraction(primary[:peak+1],-1),
                   direction_fraction(primary[peak:],1)])
    features=np.asarray(result,dtype=float)
    assert len(features)==len(NAMES)
    features[~np.isfinite(features)]=np.nan
    return features,{'reason':None,'active_coverage':float(finite.mean()),'phase_peak_index':peak,
                     'peak_at_endpoint':peak in (0,len(times)-1)}
