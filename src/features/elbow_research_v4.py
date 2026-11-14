"""Upper-body-only features; avoid estimated hips hidden behind the table."""
import numpy as np
from sklearn.base import BaseEstimator,TransformerMixin
from src.features.elbow_research_v3 import angle,valid_points,CausalSmoother,causal_trace,quantile
NAMES=[name+'_'+stat for name in ['angle_2d','angle_3d'] for stat in ['low','high','range','return_fraction','closure']]
NAMES += [name+'_'+stat for name in ['upper_image','upper_world','elbow_vertical','elbow_lateral']
          for stat in ['median','p90','variation','flex_change','end_change']]
NAMES += ['support_image_median','support_image_p90','support_world_median','support_world_p90','duration','flexion_fraction']

class FeatureView(TransformerMixin,BaseEstimator):
    def __init__(self,view='all'):self.view=view
    def fit(self,X,y=None):self.n_features_in_=X.shape[1];return self
    def transform(self,X):
        if self.view=='all':return X
        if self.view=='image':indices=[i for i,n in enumerate(NAMES) if 'world' not in n and '3d' not in n]
        elif self.view=='compact':indices=[i for i,n in enumerate(NAMES) if 'world' not in n and '3d' not in n and 'median' not in n and 'p90' not in n]
        else:raise ValueError('Invalid view')
        return X[:,indices]

def channels(world,image,width=960,height=540,hand='Left'):
    s,e,w=(11,13,15) if hand=='Left' else (12,14,16)
    ow=16 if hand=='Left' else 15
    xy=image[:,:,:2]*[width,height];xyz=world[:,:,:3]
    upper=xy[:,e]-xy[:,s];upper_world=xyz[:,e]-xyz[:,s]
    length=np.linalg.norm(upper,axis=1);length=np.where(length>1e-5,length,np.nan)
    forearm=np.linalg.norm(xy[:,w]-xy[:,e],axis=1);forearm=np.where(forearm>1e-5,forearm,np.nan)
    forearm_world=np.linalg.norm(xyz[:,w]-xyz[:,e],axis=1);forearm_world=np.where(forearm_world>1e-5,forearm_world,np.nan)
    sign=1. if hand=='Left' else -1.
    values=np.column_stack([angle(xy[:,s],xy[:,e],xy[:,w]),angle(xyz[:,s],xyz[:,e],xyz[:,w]),
        np.degrees(np.arctan2(abs(upper[:,0]),upper[:,1])),
        np.degrees(np.arctan2(np.linalg.norm(upper_world[:,[0,2]],axis=1),upper_world[:,1])),
        upper[:,1]/length,sign*upper[:,0]/length,
        np.linalg.norm(xy[:,ow]-xy[:,w],axis=1)/forearm,
        np.linalg.norm(xyz[:,ow]-xyz[:,w],axis=1)/forearm_world])
    specifications=[(image,[s,e,w]),(world,[s,e,w]),(image,[s,e]),(world,[s,e]),
                    (image,[s,e]),(image,[s,e]),(image,[e,w,ow]),(world,[e,w,ow])]
    for i,(source,indices) in enumerate(specifications):values[~valid_points(source,indices),i]=np.nan
    values[~np.isfinite(values)]=np.nan
    return values

def rep_features(trace,times):
    if len(times)<8:raise ValueError('Too few frames')
    observed=np.isfinite(trace[:,1]);coverage=float(observed.mean())
    if coverage<.8:return None,{'reason':'insufficient_active_arm_visibility'}
    peak=int(np.nanargmin(trace[:,1]));duration=float(times[-1]-times[0]);edge=max(3,int(len(times)*.12))
    result=[]
    for i in range(2):
        x=trace[:,i];low,high=quantile(x,.1),quantile(x,.9)
        start,end=quantile(x[:edge],.5),quantile(x[-edge:],.5)
        result.extend([low,high,high-low,(end-low)/max(start-low,5.),abs(end-start)/max(high-low,5.)])
    for i in range(2,6):
        x=trace[:,i];start=quantile(x[:edge],.5);end=quantile(x[-edge:],.5)
        middle=quantile(x[max(0,peak-edge):min(len(x),peak+edge+1)],.5)
        result.extend([quantile(x,.5),quantile(x,.9),quantile(x,.9)-quantile(x,.1),middle-start,end-start])
    for i in range(6,8):result.extend([quantile(trace[:,i],.5),quantile(trace[:,i],.9)])
    result.extend([duration,(times[peak]-times[0])/duration])
    value=np.asarray(result);value[~np.isfinite(value)]=np.nan
    assert len(value)==len(NAMES)
    return value,{'reason':None,'active_coverage':coverage,'phase_peak_index':peak,'peak_at_endpoint':peak in (0,len(times)-1)}
