"""Post-experiment explanatory diagnostics; no model choices or refits."""
import json
import numpy as np
import pandas as pd
from scipy.stats import chi2_contingency
from phase2_utils import P2,MODELS,inputs,verify_inputs,metrics,eta_squared,dump,sha

def main():
    verify_inputs();df,d,_=inputs();sources=pd.read_csv(P2/'source_failure_analysis.csv')
    both=sources[(sources.Correct>0)&(sources.Incorrect>0)].video_id.tolist();mixed=df.video_id.isin(both).to_numpy()
    table=pd.crosstab(df.source_sha256,df.label);chi2=chi2_contingency(table,correction=False)[0];v=float(np.sqrt(chi2/len(df)))
    model_rows=[]
    for name in MODELS:
        pred=pd.read_csv(P2/'predictions'/f'{name}.csv')
        for subset,mask in [('mixed_class_sources',mixed),('single_class_sources',~mixed)]:
            model_rows.append({'model':name,'subset':subset,'source_count':int(df[mask].source_sha256.nunique()),'Correct':int((pred.y_true[mask]==0).sum()),'Incorrect':int((pred.y_true[mask]==1).sum()),**metrics(pred.y_true[mask],pred.y_pred[mask])})
    pd.DataFrame(model_rows).to_csv(P2/'audits/mixed_source_quality_analysis.csv',index=False)
    x=d['scalar'];y=(df.label=='Incorrect').astype(float).to_numpy();centered_y=y.copy()
    for _,g in df.groupby('source_sha256'):centered_y[g.index]-=y[g.index].mean()
    rows=[]
    for j,n in enumerate(d['scalar_names']):
        xx=x[:,j].copy()
        for _,g in df.groupby('source_sha256'):xx[g.index]-=np.nanmean(xx[g.index])
        valid=mixed&np.isfinite(xx)
        corr=float(np.corrcoef(xx[valid],centered_y[valid])[0,1]) if xx[valid].std()>0 else 0.
        rows.append({'feature':str(n),'source_centered_feature_quality_correlation_in_5_mixed_sources':corr,'finite_repetitions':int(valid.sum()),'interpretation':'Descriptive within-video association; five groups only; hand, execution/view changes, estimation and label composition still confound causality'})
    pd.DataFrame(rows).to_csv(P2/'audits/within_source_feature_quality_associations.csv',index=False)
    errors=pd.read_csv(P2/'error_analysis.csv')
    tags=errors.descriptive_mechanism_tags.str.split(';').explode().value_counts().rename_axis('tag').reset_index(name='errors_flagged')
    tags.to_csv(P2/'audits/error_multitag_counts.csv',index=False)
    # Observable scene descriptions from the 29 source contact images, inspected
    # after experiments. No identity verification or quality relabeling.
    descriptions={
        'person1':'Blue top; curtain backdrop with treatment-table foreground; relatively large framing',
        'person2':'Black patterned top; curtain/window backdrop with treatment table; more distant framing than some other sources',
        'person3':'Purple top; curtain/window backdrop with treatment table; relatively distant framing',
        'person4':'White coat over blue top; mostly plain wall/curtain background; relatively large framing',
        'person5':'Dark blue top; wall/curtain backdrop and desk foreground; relatively large framing',
    }
    visual=[]
    for _,r in sources.iterrows():
        visual.append({'video_id':r.video_id,'inherited_subject_id':r.inherited_subject_id,'scene_observation_from_one_original_frame':descriptions.get(r.inherited_subject_id,'See thumbnail'),'standing_upper_body_view':True,'appearance_or_identity_verified':False,'quality_or_error_cause_inferred':False,'limits':'One source thumbnail plus saved error strips; not a full-motion visual review or independent participant identity evidence'})
    pd.DataFrame(visual).to_csv(P2/'audits/source_scene_observations.csv',index=False)
    dump(P2/'audits/supplemental_summary.json',{'source_label_cramers_v':v,'mixed_class_sources':len(both),'mixed_repetitions':int(mixed.sum()),'within_video_majority_purity_mixed_descriptive_oracle_only':float(sum(max((g.label=='Correct').sum(),(g.label=='Incorrect').sum()) for _,g in df[mixed].groupby('video_id'))/mixed.sum()),'supplemental_diagnostics_influenced_experiments_or_selection':False,'script_sha256':sha(__file__)})
    print(pd.DataFrame(model_rows)[['model','subset','n','balanced_accuracy','incorrect_recall']].to_string(index=False))

if __name__=='__main__':main()
