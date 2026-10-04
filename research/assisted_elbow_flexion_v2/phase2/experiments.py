"""Small locked experiments. Never persist a deployment/model checkpoint."""
import os
os.environ.setdefault('OMP_NUM_THREADS','4')
import json
import numpy as np
import pandas as pd
from sklearn.impute import SimpleImputer
from sklearn.preprocessing import StandardScaler,RobustScaler
from sklearn.pipeline import make_pipeline
from sklearn.svm import SVC
from sklearn.model_selection import StratifiedGroupKFold
from phase2_utils import P1,P2,MODELS,METRICS,inputs,verify_inputs,dump,sha,metrics

FIT_AUDIT=[]

def representations(df,d):
    names=d['scalar_names'].tolist();x=d['scalar'].copy()
    qc=pd.read_csv(P2/'audits/repetition_diagnostics.csv').set_index('repetition_id').loc[df.repetition_id]
    p95=x.copy();p95[:,names.index('active_peak_abs_velocity')]=qc.active_velocity_p95.to_numpy();p95[:,names.index('opposing_peak_abs_velocity')]=qc.opposing_velocity_p95.to_numpy()
    keep=[j for j,n in enumerate(names) if 'torso' not in n and 'shoulder_depth' not in n]
    return {'FrozenPhase1SVM':x,'VelocityP95':p95,'WithoutViewProxies':x[:,keep],'BalancedSVM':x,'RobustScalerSVM':x},{'VelocityP95':names,'WithoutViewProxies':[names[j] for j in keep]}

def fit_predict(name,features,df,y,tr,va,context):
    assert not set(df.iloc[tr].source_sha256)&set(df.iloc[va].source_sha256)
    assert set(y[tr])=={0,1}
    imputer=SimpleImputer(strategy='mean',keep_empty_features=True)
    scaler=RobustScaler(quantile_range=(25,75),unit_variance=False) if name=='RobustScalerSVM' else StandardScaler()
    svc=SVC(C=1.,kernel='rbf',gamma='scale',class_weight='balanced' if name=='BalancedSVM' else None,probability=False)
    model=make_pipeline(imputer,scaler,svc);model.fit(features[tr],y[tr])
    train_imputed=imputer.transform(features[tr]);val_imputed=imputer.transform(features[va]);assert np.isfinite(train_imputed).all() and np.isfinite(val_imputed).all()
    expected=np.nanmean(features[tr].astype(np.float64),axis=0);assert np.allclose(imputer.statistics_,expected,rtol=1e-7,atol=1e-8)
    if name=='RobustScalerSVM':
        assert np.allclose(scaler.center_,np.median(train_imputed,axis=0))
        center=scaler.center_;scale=scaler.scale_
    else:
        assert scaler.n_samples_seen_==len(tr)
        assert np.allclose(scaler.mean_,train_imputed.mean(axis=0))
        center=scaler.mean_;scale=scaler.scale_
    FIT_AUDIT.append({'context':context,'model':name,'train_n':len(tr),'validation_n':len(va),'train_ids':df.iloc[tr].repetition_id.tolist(),'validation_ids':df.iloc[va].repetition_id.tolist(),'source_intersection':[],'imputer_statistics':imputer.statistics_.tolist(),'scaler':type(scaler).__name__,'scaler_center':center.tolist(),'scaler_scale':scale.tolist(),'effective_gamma':float(svc._gamma),'effective_class_weights':svc.class_weight_.tolist(),'training_class_counts':np.bincount(y[tr],minlength=2).tolist()})
    return model.predict(features[va]),model.decision_function(features[va])

def summary(name,df,y,p,scores):
    frame=df[['repetition_id','video_id','source_sha256','subject_id','hand','label','fold']].copy();frame['y_true']=y;frame['y_pred']=p;frame['incorrect_score']=scores;frame['predicted_label']=np.where(p==1,'Incorrect','Correct');frame['is_correct']=y==p
    frame.to_csv(P2/'predictions'/f'{name}.csv',index=False)
    folds=[{'fold':int(f),**metrics(g.y_true,g.y_pred)} for f,g in frame.groupby('fold')]
    sources=[{'video_id':vid,'source_sha256':g.source_sha256.iloc[0],**metrics(g.y_true,g.y_pred)} for vid,g in frame.groupby('video_id')]
    pd.DataFrame(folds).to_csv(P2/'experiments'/f'{name}_fold_metrics.csv',index=False)
    pd.DataFrame(sources).to_csv(P2/'experiments'/f'{name}_source_metrics.csv',index=False)
    out={'name':name,'pooled':metrics(y,p),'fold_mean':{m:float(np.mean([r[m] for r in folds])) for m in METRICS},'fold_sample_std':{m:float(np.std([r[m] for r in folds],ddof=1)) for m in METRICS},'source_accuracy_mean':float(np.mean([r['accuracy'] for r in sources])),'source_accuracy_sample_std':float(np.std([r['accuracy'] for r in sources],ddof=1)),'source_accuracy_min':float(min(r['accuracy'] for r in sources)),'hand':{h:metrics(g.y_true,g.y_pred) for h,g in frame.groupby('hand')}}
    dump(P2/'experiments'/f'{name}_summary.json',out)
    return out

def main():
    verify_inputs();lock=json.loads((P2/'experiment_lock.json').read_text());assert sha(P2/'experiment_config.json')==lock['config_sha256'];assert sha(P2/'audits/repetition_diagnostics.csv')==lock['diagnostics_sha256']
    assert not (P2/'experiments/EXPERIMENTS_COMPLETE.json').exists(),'No repeated inspection/tuning'
    df,d,frozen=inputs();y=(df.label=='Incorrect').astype(int).to_numpy();reps,feature_names=representations(df,d)
    dump(P2/'experiments/feature_names.json',feature_names)
    summaries={};summaries['FrozenPhase1SVM']=summary('FrozenPhase1SVM',df,y,frozen.y_pred.to_numpy(),frozen.incorrect_score.to_numpy())
    for name in ['VelocityP95','WithoutViewProxies','BalancedSVM','RobustScalerSVM']:
        assert not (P2/'experiments'/f'{name}_summary.json').exists()
        p=np.full(280,-1);scores=np.full(280,np.nan)
        for f in range(5):
            tr=np.flatnonzero(df.fold.to_numpy()!=f);va=np.flatnonzero(df.fold.to_numpy()==f)
            p[va],scores[va]=fit_predict(name,reps[name],df,y,tr,va,f'controlled_outer_{f}')
        assert (p>=0).all() and np.isfinite(scores).all();summaries[name]=summary(name,df,y,p,scores)
        print(name,summaries[name]['pooled'],flush=True)
    # Selection strictly inside each outer training fold; never inspect outer
    # predictions to choose candidate/parameters. Outer candidate results above
    # are written only; no selection branch reads them.
    selections=[];selected_p=np.full(280,-1);selected_scores=np.full(280,np.nan)
    for f in range(5):
        outer_tr=np.flatnonzero(df.fold.to_numpy()!=f);outer_va=np.flatnonzero(df.fold.to_numpy()==f)
        inner=StratifiedGroupKFold(n_splits=3,shuffle=True,random_state=42+100*f)
        inner_splits=list(inner.split(np.zeros(len(outer_tr)),y[outer_tr],df.iloc[outer_tr].source_sha256))
        inner_predictions={name:np.full(len(outer_tr),-1) for name in reps}
        inner_scores={name:np.full(len(outer_tr),np.nan) for name in reps}
        for k,(itr,iva) in enumerate(inner_splits):
            tr=outer_tr[itr];va=outer_tr[iva]
            for name in reps:inner_predictions[name][iva],inner_scores[name][iva]=fit_predict(name,reps[name],df,y,tr,va,f'outer_{f}_inner_{k}')
        inner_metrics={}
        for name,p in inner_predictions.items():
            assert (p>=0).all()
            yy=y[outer_tr];ss=df.iloc[outer_tr].source_sha256.to_numpy();src=[np.mean(p[ss==s]==yy[ss==s]) for s in np.unique(ss)]
            inner_metrics[name]={**metrics(yy,p),'source_std':float(np.std(src,ddof=1))}
            out=df.iloc[outer_tr][['repetition_id','source_sha256']].copy();out['y_true']=yy;out['y_pred']=p;out['incorrect_score']=inner_scores[name];out.to_csv(P2/'experiments'/f'outer_{f}_inner_oof_{name}.csv',index=False)
        baseline=inner_metrics['FrozenPhase1SVM'];eligible=[n for n,m in inner_metrics.items() if n!='FrozenPhase1SVM' and all(m[k]>=baseline[k]-1e-12 for k in ['balanced_accuracy','macro_f1','incorrect_recall']) and m['source_std']<=baseline['source_std']+.02]
        chosen=max(eligible,key=lambda n:(inner_metrics[n]['balanced_accuracy'],inner_metrics[n]['macro_f1'],inner_metrics[n]['incorrect_recall'],-inner_metrics[n]['source_std'])) if eligible else 'FrozenPhase1SVM'
        if chosen=='FrozenPhase1SVM':selected_p[outer_va]=frozen.y_pred.to_numpy()[outer_va];selected_scores[outer_va]=frozen.incorrect_score.to_numpy()[outer_va]
        else:selected_p[outer_va],selected_scores[outer_va]=fit_predict(chosen,reps[chosen],df,y,outer_tr,outer_va,f'nested_selected_outer_{f}')
        selections.append({'outer_fold':f,'chosen_only_from_inner_grouped_predictions':chosen,'eligible_inner_candidates':eligible,'inner_metrics':inner_metrics,'outer_validation_sources_used_for_selection':False})
        print('Inner selection fold',f,chosen,flush=True)
    dump(P2/'experiments/inner_selections.json',selections)
    summaries['InnerSelectedProcedure']=summary('InnerSelectedProcedure',df,y,selected_p,selected_scores)
    reference=summaries['FrozenPhase1SVM'];baseline_source=pd.read_csv(P2/'experiments/FrozenPhase1SVM_source_metrics.csv').set_index('video_id')
    result_rows=[]
    for name,s in summaries.items():
        src=pd.read_csv(P2/'experiments'/f'{name}_source_metrics.csv').set_index('video_id');delta=src.accuracy-baseline_source.accuracy
        row={'model':name,**s['pooled'],'source_accuracy_mean':s['source_accuracy_mean'],'source_accuracy_sample_std':s['source_accuracy_sample_std'],'source_accuracy_min':s['source_accuracy_min'],'sources_nonnegative_accuracy_delta':int((delta>=-1e-12).sum()),'sources_improved':int((delta>1e-12).sum()),'sources_worsened':int((delta<-1e-12).sum()),**{'delta_'+m:s['pooled'][m]-reference['pooled'][m] for m in METRICS},**{'fold_mean_'+m:s['fold_mean'][m] for m in METRICS},**{'fold_std_'+m:s['fold_sample_std'][m] for m in METRICS}}
        row['descriptive_interesting_not_winner']=all(s['pooled'][k]>=reference['pooled'][k]-1e-12 for k in ['balanced_accuracy','macro_f1','incorrect_recall']) and s['source_accuracy_sample_std']<=reference['source_accuracy_sample_std']+.02 and s['source_accuracy_min']>=reference['source_accuracy_min']-.05 and (delta>=-1e-12).sum()>=15
        result_rows.append(row)
    result=pd.DataFrame(result_rows)
    result[result.model.isin(['FrozenPhase1SVM','VelocityP95','WithoutViewProxies'])].to_csv(P2/'feature_experiment_results.csv',index=False)
    result[result.model.isin(['FrozenPhase1SVM','BalancedSVM','RobustScalerSVM','InnerSelectedProcedure'])].to_csv(P2/'model_robustness_results.csv',index=False)
    result.to_csv(P2/'experiments/all_results.csv',index=False)
    hand=[]
    for name,s in summaries.items():
        for h,m in s['hand'].items():hand.append({'model':name,'hand':h,**m})
    pd.DataFrame(hand).to_csv(P2/'audits/hand_model_results.csv',index=False)
    loo_p=np.full(280,-1);loo_scores=np.full(280,np.nan);loo_rows=[]
    for vid in sorted(df.video_id.unique()):
        va=np.flatnonzero(df.video_id.to_numpy()==vid);tr=np.flatnonzero(df.video_id.to_numpy()!=vid)
        loo_p[va],loo_scores[va]=fit_predict('FrozenPhase1SVM',reps['FrozenPhase1SVM'],df,y,tr,va,'leave_one_source_out_'+vid)
        loo_rows.append({'video_id':vid,'source_sha256':df.iloc[va].source_sha256.iloc[0],'train_sources':28,'validation_sources':1,'source_intersection':[],'Correct':int((y[va]==0).sum()),'Incorrect':int((y[va]==1).sum()),**metrics(y[va],loo_p[va]),'frozen_five_fold_source_accuracy':float(np.mean(frozen.y_pred.to_numpy()[va]==y[va])),'prediction_changes_from_five_fold':int((loo_p[va]!=frozen.y_pred.to_numpy()[va]).sum())})
    pd.DataFrame(loo_rows).to_csv(P2/'source_leave_one_out_results.csv',index=False)
    loo=df[['repetition_id','video_id','source_sha256','hand','label']].copy();loo['y_true']=y;loo['y_pred']=loo_p;loo['incorrect_score']=loo_scores;loo.to_csv(P2/'predictions/source_leave_one_out.csv',index=False)
    dump(P2/'experiments/source_leave_one_out_summary.json',{'pooled':metrics(y,loo_p),'source_accuracy_mean':float(np.mean([r['accuracy'] for r in loo_rows])),'source_accuracy_sample_std':float(np.std([r['accuracy'] for r in loo_rows],ddof=1)),'prediction_changes_from_frozen_five_fold':int((loo_p!=frozen.y_pred.to_numpy()).sum()),'partitions':29,'model_specification':'Unchanged original SVM; fresh 28-source diagnostic fits, no model selection','independent_test':False})
    dump(P2/'experiments/fit_audit.json',FIT_AUDIT)
    dump(P2/'experiments/EXPERIMENTS_COMPLETE.json',{'controlled_candidates':4,'nested_inner_selection':True,'source_leave_one_out_folds':29,'total_new_fits':len(FIT_AUDIT),'config_sha256':sha(P2/'experiment_config.json'),'experiment_script_sha256':sha(__file__),'no_models_serialized':True})
    print(result[['model','accuracy','balanced_accuracy','macro_f1','incorrect_recall','source_accuracy_sample_std','descriptive_interesting_not_winner']].to_string(index=False),flush=True)

if __name__=='__main__':main()
