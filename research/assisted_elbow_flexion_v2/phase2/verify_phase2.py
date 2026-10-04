"""Independent verification of canonical membership, fit boundaries and preservation."""
import json
import numpy as np
import pandas as pd
from sklearn.model_selection import StratifiedGroupKFold
from phase2_utils import P1,P2,MODELS,inputs,verify_inputs,dump,sha,metrics
from experiments import representations

def main():
    verify_inputs();df,d,frozen=inputs();features,_=representations(df,d)
    lock=json.loads((P2/'experiment_lock.json').read_text());assert sha(P2/'experiment_config.json')==lock['config_sha256']
    expected=set(df.repetition_id);index={r:i for i,r in enumerate(df.repetition_id)};y=(df.label=='Incorrect').astype(int).to_numpy()
    for name in MODELS:
        pred=pd.read_csv(P2/'predictions'/f'{name}.csv');assert len(pred)==280 and set(pred.repetition_id)==expected;assert pred.repetition_id.tolist()==df.repetition_id.tolist();assert pred.fold.tolist()==df.fold.tolist();assert pred.y_true.tolist()==y.tolist()
        s=json.loads((P2/'experiments'/f'{name}_summary.json').read_text());assert s['pooled']==metrics(y,pred.y_pred)
    baseline=pd.read_csv(P2/'predictions/FrozenPhase1SVM.csv');assert baseline.y_pred.tolist()==frozen.y_pred.tolist();assert np.allclose(baseline.incorrect_score,frozen.incorrect_score)
    errors=pd.read_csv(P2/'error_analysis.csv');assert len(errors)==36 and set(errors.repetition_id)==set(frozen[~frozen.is_correct].repetition_id)
    assert len(pd.read_csv(P2/'source_failure_analysis.csv'))==29
    robust=pd.read_csv(P2/'feature_robustness.csv');assert len(robust)==45 and set(robust[robust.representation=='scalar'].feature)==set(d['scalar_names'])
    inner={}
    for f in range(5):
        tr=np.flatnonzero(df.fold.to_numpy()!=f)
        splits=StratifiedGroupKFold(n_splits=3,shuffle=True,random_state=42+100*f).split(np.zeros(len(tr)),y[tr],df.iloc[tr].source_sha256)
        for k,(itr,iva) in enumerate(splits):inner[f'outer_{f}_inner_{k}']=(set(df.iloc[tr[itr]].repetition_id),set(df.iloc[tr[iva]].repetition_id))
    fits=json.loads((P2/'experiments/fit_audit.json').read_text())
    for fit in fits:
        tr=np.array([index[r] for r in fit['train_ids']]);va=np.array([index[r] for r in fit['validation_ids']]);context=fit['context']
        assert not set(tr)&set(va);assert not set(df.iloc[tr].source_sha256)&set(df.iloc[va].source_sha256)
        if context in inner:assert (set(fit['train_ids']),set(fit['validation_ids']))==inner[context]
        elif context.startswith('leave_one_source_out_'):
            vid=context.removeprefix('leave_one_source_out_');assert set(fit['validation_ids'])==set(df[df.video_id==vid].repetition_id);assert len(set(df.iloc[tr].source_sha256))==28
        else:
            f=int(context.rsplit('_',1)[1]);assert set(fit['train_ids'])==set(df[df.fold!=f].repetition_id);assert set(fit['validation_ids'])==set(df[df.fold==f].repetition_id)
        x=features[fit['model']][tr];means=np.nanmean(x,axis=0);assert np.allclose(means,fit['imputer_statistics']);imputed=np.where(np.isnan(x),means,x)
        if fit['scaler']=='StandardScaler':
            center=imputed.mean(axis=0);scale=imputed.std(axis=0);scale[scale==0]=1
        else:
            center=np.median(imputed,axis=0);scale=np.quantile(imputed,.75,axis=0)-np.quantile(imputed,.25,axis=0);scale[scale==0]=1
        assert np.allclose(center,fit['scaler_center']) and np.allclose(scale,fit['scaler_scale'])
        assert fit['training_class_counts']==np.bincount(y[tr],minlength=2).tolist()
    selections=json.loads((P2/'experiments/inner_selections.json').read_text())
    for row in selections:
        f=row['outer_fold'];stats=row['inner_metrics'];b=stats['FrozenPhase1SVM'];eligible=[n for n,m in stats.items() if n!='FrozenPhase1SVM' and all(m[k]>=b[k]-1e-12 for k in ['balanced_accuracy','macro_f1','incorrect_recall']) and m['source_std']<=b['source_std']+.02]
        chosen=max(eligible,key=lambda n:(stats[n]['balanced_accuracy'],stats[n]['macro_f1'],stats[n]['incorrect_recall'],-stats[n]['source_std'])) if eligible else 'FrozenPhase1SVM'
        assert chosen==row['chosen_only_from_inner_grouped_predictions'];assert not row['outer_validation_sources_used_for_selection']
        for name in stats:
            ip=pd.read_csv(P2/'experiments'/f'outer_{f}_inner_oof_{name}.csv');assert set(ip.repetition_id)==set(df[df.fold!=f].repetition_id)
            for k,v in metrics(ip.y_true,ip.y_pred).items():assert stats[name][k]==v
    loo=pd.read_csv(P2/'predictions/source_leave_one_out.csv');assert len(loo)==280 and set(loo.repetition_id)==expected
    assert len(pd.read_csv(P2/'source_leave_one_out_results.csv'))==29
    assert not [p for p in P2.rglob('*') if p.suffix in ['.pth','.joblib','.pkl','.pt']]
    protected=json.loads((P2/'provenance/protected_files_before.json').read_text());changed=[p for p,h in protected.items() if sha(p)!=h]
    dump(P2/'provenance/preservation_audit.json',{'protected_files_checked':len(protected),'changed':changed,'all_unchanged':not changed});assert not changed
    dump(P2/'provenance/verification.json',{'all_passed':True,'canonical_examples':280,'individually_audited_frozen_errors':36,'scalar_and_temporal_features_audited':45,'fit_boundaries_and_preprocessing_checked':len(fits),'inner_selection_folds_verified':5,'leave_one_source_out_groups':29,'protected_files_unchanged':len(protected),'no_deployment_or_model_checkpoint_created':True,'script_sha256':sha(__file__)})
    print('PASS:',len(fits),'new fits verified;',len(protected),'protected files unchanged.')

if __name__=='__main__':main()
