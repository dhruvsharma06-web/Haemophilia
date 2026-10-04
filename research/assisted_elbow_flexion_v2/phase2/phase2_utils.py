"""Read-only Phase 1 inputs; all Phase 2 outputs stay in this directory."""
from pathlib import Path
import sys, json, hashlib
import numpy as np
import pandas as pd
P2=Path(__file__).resolve().parent
P1=P2.parent
sys.path.insert(0,str(P1))
from common import canonical, verify_config, sha, dump, REPO, DATA

MODELS=['FrozenPhase1SVM','VelocityP95','WithoutViewProxies','BalancedSVM','RobustScalerSVM','InnerSelectedProcedure']
METRICS=['accuracy','balanced_accuracy','macro_f1','correct_recall','incorrect_recall']

def inputs():
    verify_config()
    rows,check=canonical()
    df=pd.DataFrame(rows)
    folds=pd.read_csv(P1/'splits/fold_assignments.csv')
    assert folds.repetition_id.tolist()==df.repetition_id.tolist()
    check(rows,dict(zip(folds.repetition_id,folds.fold.astype(str))))
    df['fold']=folds.fold
    d=dict(np.load(P1/'features/model_ready.npz'))
    assert d['repetition_ids'].tolist()==df.repetition_id.tolist()
    preds=pd.read_csv(P1/'baselines/SVM/out_of_fold_predictions.csv')
    assert preds.repetition_id.tolist()==df.repetition_id.tolist()
    assert preds.fold.tolist()==df.fold.tolist()
    assert preds.y_true.tolist()==(df.label=='Incorrect').astype(int).tolist()
    assert int((~preds.is_correct).sum())==36
    return df,d,preds

def frozen_hashes():
    files=[P1/'config.json',P1/'protocol_lock.json',P1/'splits/fold_assignments.csv',P1/'features/model_ready.npz',P1/'features/scalar_features.csv',P1/'baselines/SVM/summary.json',P1/'baselines/SVM/out_of_fold_predictions.csv']
    files+=list((P1/'checkpoints/SVM').glob('*.joblib'))
    return {str(f):sha(f) for f in files}

def verify_inputs():
    expected=json.loads((P2/'provenance/frozen_input_hashes.json').read_text())
    assert all(sha(p)==h for p,h in expected.items()),'Phase 1 input changed'

def metrics(y,p):
    from sklearn.metrics import confusion_matrix,accuracy_score,f1_score
    cm=confusion_matrix(y,p,labels=[0,1]);ns=cm.sum(axis=1)
    recalls=[float(cm[i,i]/ns[i]) if ns[i] else None for i in [0,1]]
    return {'n':len(y),'accuracy':float(accuracy_score(y,p)),'balanced_accuracy':float(np.mean(recalls)) if all(x is not None for x in recalls) else None,'macro_f1':float(f1_score(y,p,labels=[0,1],average='macro',zero_division=0)),'correct_recall':recalls[0],'incorrect_recall':recalls[1],'confusion_matrix':cm.tolist()}

def eta_squared(values,groups):
    t=pd.DataFrame({'x':values,'g':np.asarray(groups)}).dropna()
    ss=float(((t.x-t.x.mean())**2).sum())
    if ss<=1e-12:return 0.0
    between=sum(len(g)*(g.x.mean()-t.x.mean())**2 for _,g in t.groupby('g'))
    return float(between/ss)

def finite_summary(x):
    x=np.asarray(x);x=x[np.isfinite(x)]
    if not len(x):return {'mean':None,'std':None,'min':None,'p25':None,'median':None,'p75':None,'p95':None,'max':None}
    return {k:float(v) for k,v in zip(['mean','std','min','p25','median','p75','p95','max'],[x.mean(),x.std(),x.min(),*np.quantile(x,[.25,.5,.75,.95]),x.max()])}

def initialize():
    assert not (P2/'provenance/frozen_input_hashes.json').exists(),'Already initialized'
    for folder in ['provenance','audits','plots/errors','media','experiments','predictions']:(P2/folder).mkdir(parents=True,exist_ok=True)
    df,d,pred=inputs()
    inventory=json.loads((P1/'provenance/output_inventory.json').read_text())
    changed=[p for p,h in inventory.items() if sha(P1/p)!=h]
    assert not changed,changed
    protected=json.loads((P1/'provenance/protected_files_before.json').read_text())
    protected.update({str(P1/p):h for p,h in inventory.items()})
    protected[str(P1/'provenance/output_inventory.json')]=sha(P1/'provenance/output_inventory.json')
    dump(P2/'provenance/protected_files_before.json',protected)
    dump(P2/'provenance/frozen_input_hashes.json',frozen_hashes())
    import shutil
    shutil.copyfile(Path(r'<local_path_redacted>,P2/'provenance/user_authorization.txt')
    print('Initialized Phase 2: 280 canonical rows; 36 frozen SVM errors; Phase 1 artifact hashes verified.')

if __name__=='__main__':initialize()
