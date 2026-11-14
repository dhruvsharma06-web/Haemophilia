"""Upper-body candidate plus measured support-arm and shoulder context."""
import numpy as np
from sklearn.base import BaseEstimator,TransformerMixin
from src.features import elbow_research_v4 as base
from src.features.elbow_research_v3 import angle,valid_points,quantile,causal_trace,CausalSmoother
CONTEXT=['opposing_angle_range','angle_asymmetry_median','angle_asymmetry_p90',
         'shoulder_tilt_p90','shoulder_tilt_variation','shoulder_depth_variation',
         'head_center_variation','head_center_flex_change']
NAMES=base.NAMES+CONTEXT
class FeatureView(TransformerMixin,BaseEstimator):
    def __init__(self,view='all'):self.view=view
    def fit(self,X,y=None):self.n_features_in_=X.shape[1];return self
    def transform(self,X):
        if self.view=='all':return X
        if self.view=='image':indices=[i for i,n in enumerate(NAMES) if 'world' not in n and '3d' not in n and 'depth' not in n]
        elif self.view=='compact':indices=[i for i,n in enumerate(NAMES) if 'world' not in n and '3d' not in n and 'depth' not in n and ('median' not in n and 'p90' not in n or n in CONTEXT)]
        else:raise ValueError('Invalid view')
        return X[:,indices]
def channels(world,image,width=960,height=540,hand='Left'):
    existing=base.channels(world,image,width,height,hand)
    os,oe,ow=(12,14,16) if hand=='Left' else (11,13,15)
    xy=image[:,:,:2]*[width,height];xyz=world[:,:,:3]
    shoulder=xy[:,12]-xy[:,11];width_image=np.linalg.norm(shoulder,axis=1)
    shoulder_world=xyz[:,12]-xyz[:,11];width_world=np.linalg.norm(shoulder_world,axis=1)
    middle=(xy[:,11]+xy[:,12])/2
    # Head position is a descriptive context measurement, not a diagnosed torso fault.
    head=(xy[:,0,0]-middle[:,0])/np.where(width_image>1e-5,width_image,np.nan)
    context=np.column_stack([angle(xy[:,os],xy[:,oe],xy[:,ow]),
        np.degrees(np.arctan2(abs(shoulder[:,1]),abs(shoulder[:,0]))),
        abs(shoulder_world[:,2])/np.where(width_world>1e-5,width_world,np.nan),head])
    for i,(source,joints) in enumerate([(image,[os,oe,ow]),(image,[11,12]),(world,[11,12]),(image,[0,11,12])]):
        context[~valid_points(source,joints),i]=np.nan
    context[~np.isfinite(context)]=np.nan
    return np.c_[existing,context]
def rep_features(trace,times):
    existing,qc=base.rep_features(trace[:,:8],times)
    if existing is None:return None,qc
    peak=qc['phase_peak_index'];edge=max(3,int(len(times)*.12))
    opposing=trace[:,8];asymmetry=abs(trace[:,0]-opposing)
    tilt,depth,head=trace[:,9],trace[:,10],trace[:,11]
    extras=[quantile(opposing,.9)-quantile(opposing,.1),quantile(asymmetry,.5),quantile(asymmetry,.9),
        quantile(tilt,.9),quantile(tilt,.9)-quantile(tilt,.1),quantile(depth,.9)-quantile(depth,.1),
        quantile(head,.9)-quantile(head,.1),
        abs(quantile(head[max(0,peak-edge):min(len(head),peak+edge+1)],.5)-quantile(head[:edge],.5))]
    result=np.r_[existing,extras];result[~np.isfinite(result)]=np.nan
    return result,qc
