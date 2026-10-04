"""One predeclared evaluation of fixed models on immutable source-grouped folds."""
from pathlib import Path
import sys, json, argparse, time, random, os
os.environ.setdefault('OMP_NUM_THREADS','4')
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from common import ROOT, canonical, config, verify_config, dump, sha
import numpy as np
import pandas as pd
import joblib
from sklearn.preprocessing import StandardScaler
from sklearn.impute import SimpleImputer
from sklearn.pipeline import make_pipeline
from sklearn.linear_model import LogisticRegression
from sklearn.ensemble import RandomForestClassifier, HistGradientBoostingClassifier
from sklearn.svm import SVC
from sklearn.metrics import confusion_matrix, accuracy_score, f1_score

METRICS=['accuracy','balanced_accuracy','macro_f1','correct_recall','incorrect_recall']

def metrics(y,p):
    cm=confusion_matrix(y,p,labels=[0,1]);counts=cm.sum(axis=1)
    recalls=[float(cm[i,i]/counts[i]) if counts[i] else None for i in range(2)]
    return {'n':len(y),'accuracy':float(accuracy_score(y,p)),'balanced_accuracy':float(np.mean(recalls)) if all(r is not None for r in recalls) else None,'macro_f1':float(f1_score(y,p,labels=[0,1],average='macro',zero_division=0)), 'correct_recall':recalls[0],'incorrect_recall':recalls[1],'confusion_matrix':cm.tolist()}

def load_inputs():
    lock=verify_config();rows,check=canonical();df=pd.DataFrame(rows)
    raw_validation=json.loads((ROOT/'preprocessing/raw_validation.json').read_text())
    independent_validation=json.loads((ROOT/'features/independent_validation.json').read_text())
    assert raw_validation['all_structural_and_timing_checks_passed'] and raw_validation['canonical_repetitions']==280
    assert independent_validation['all_passed'] and independent_validation['canonical_examples']==280
    fold=pd.read_csv(ROOT/'splits/fold_assignments.csv')
    assert fold.repetition_id.tolist()==df.repetition_id.tolist()
    check(rows,dict(zip(fold.repetition_id,fold.fold.astype(str))))
    df['fold']=fold.fold
    validation=json.loads((ROOT/'features/feature_validation.json').read_text())
    assert validation['successful']==280 and validation['failed']==0
    assert validation['model_ready_sha256']==sha(ROOT/'features/model_ready.npz')
    d=dict(np.load(ROOT/'features/model_ready.npz'))
    assert d['repetition_ids'].tolist()==df.repetition_id.tolist()
    assert not np.isinf(d['scalar']).any() and not np.isinf(d['sequence']).any()
    assert str(d['manifest_sha256'])==lock['manifest_sha256']
    y=(df.label=='Incorrect').astype(int).to_numpy()
    for f in range(5):
        tr=df.fold!=f;va=~tr
        assert not set(df.loc[tr,'source_sha256']) & set(df.loc[va,'source_sha256'])
    return df,d,y

def persist_model_results(name,df,y,pred,scores,fold_metrics,training):
    out=ROOT/'baselines'/name;out.mkdir(exist_ok=True)
    table=df[['repetition_id','source_sha256','video_id','subject_id','hand','label','fold']].copy()
    table['y_true']=y;table['y_pred']=pred;table['predicted_label']=np.where(pred==0,'Correct','Incorrect');table['incorrect_score']=scores
    table['is_correct']=pred==y
    table.to_csv(out/'out_of_fold_predictions.csv',index=False)
    pd.DataFrame(fold_metrics).to_csv(out/'fold_metrics.csv',index=False)
    per_source=[]
    for vid,g in table.groupby('video_id',sort=True):
        m=metrics(g.y_true,g.y_pred)
        per_source.append({'video_id':vid,'source_sha256':g.source_sha256.iloc[0],'fold':int(g.fold.iloc[0]),'Correct':int((g.y_true==0).sum()),'Incorrect':int((g.y_true==1).sum()),**m})
    pd.DataFrame(per_source).to_csv(out/'per_source_metrics.csv',index=False)
    hand={h:metrics(g.y_true,g.y_pred) for h,g in table.groupby('hand')}
    dump(out/'per_hand_metrics.json',hand)
    summary={'model':name,'pooled_oof':metrics(y,pred),'fold_mean':{m:float(np.mean([r[m] for r in fold_metrics])) for m in METRICS},'fold_sample_std':{m:float(np.std([r[m] for r in fold_metrics],ddof=1)) for m in METRICS},'source_accuracy_mean':float(np.mean([r['accuracy'] for r in per_source])),'source_accuracy_sample_std':float(np.std([r['accuracy'] for r in per_source],ddof=1)),'per_hand':hand,'training':training,'manifest_sha256':verify_config()['manifest_sha256'],'fold_assignments_sha256':sha(ROOT/'splits/fold_assignments.csv'),'config_sha256':sha(ROOT/'config.json'),'model_ready_sha256':sha(ROOT/'features/model_ready.npz'),'benchmark_script_sha256':sha(__file__)}
    dump(out/'summary.json',summary)
    print(json.dumps({'model':name,'pooled_oof':summary['pooled_oof'],'fold_mean':summary['fold_mean'],'fold_sample_std':summary['fold_sample_std']}),flush=True)

def classical():
    assert not (ROOT/'baselines/classical_complete.json').exists(),'Classical evaluation already complete; do not inspect and retune'
    df,d,y=load_inputs();cfg=config();x=d['scalar'];completion=[]
    classes={'LogisticRegression':LogisticRegression,'RandomForest':RandomForestClassifier,'HistGradientBoosting':HistGradientBoostingClassifier,'SVM':SVC}
    for name,cls in classes.items():
        assert not (ROOT/'baselines'/name/'summary.json').exists(),'Existing evaluation requires separate explicit experiment, not overwrite'
        pred=np.full(len(y),-1);scores=np.full(len(y),np.nan);fold_metrics=[];training=[]
        for f in range(5):
            tr=df.fold.to_numpy()!=f;va=~tr
            assert not set(df.loc[tr,'source_sha256']) & set(df.loc[va,'source_sha256'])
            model=cls(**cfg['models'][name])
            imputer=SimpleImputer(strategy='mean',keep_empty_features=True)
            model=make_pipeline(imputer,StandardScaler(),model) if name in ['LogisticRegression','SVM'] else make_pipeline(imputer,model)
            start=time.perf_counter();model.fit(x[tr],y[tr]);p=model.predict(x[va]);pred[va]=p
            scores[va]=model.decision_function(x[va]) if name=='SVM' else model.predict_proba(x[va])[:,1]
            m={'fold':f,**metrics(y[va],p)};fold_metrics.append(m)
            fit_audit={'fold':f,'train_n':int(tr.sum()),'validation_n':int(va.sum()),'source_intersection':[],'fit_seconds':time.perf_counter()-start,'resubstitution_train_metrics':metrics(y[tr],model.predict(x[tr])),'train_repetition_ids':df.loc[tr,'repetition_id'].tolist(),'validation_repetition_ids':df.loc[va,'repetition_id'].tolist()}
            fit_audit['imputer']={'strategy':'mean','statistics':imputer.statistics_.tolist(),'fit_rows':int(tr.sum()),'training_missing_values':int(np.isnan(x[tr]).sum()),'validation_missing_values':int(np.isnan(x[va]).sum()),'no_indicators':True}
            assert np.isfinite(imputer.transform(x[tr])).all() and np.isfinite(imputer.transform(x[va])).all()
            if name in ['LogisticRegression','SVM']:
                scaler=model.named_steps['standardscaler'];fit_audit['scaler']={'mean':scaler.mean_.tolist(),'scale':scaler.scale_.tolist(),'n_samples_seen':int(scaler.n_samples_seen_)}
                assert int(scaler.n_samples_seen_)==int(tr.sum())
            training.append(fit_audit)
            path=ROOT/'checkpoints'/name;path.mkdir(exist_ok=True)
            joblib.dump(model,path/f'fold_{f}.joblib')
            print(f'{name} fold {f}: {m}',flush=True)
        assert (pred>=0).all() and np.isfinite(scores).all()
        persist_model_results(name,df,y,pred,scores,fold_metrics,training);completion.append(name)
    dump(ROOT/'baselines/classical_complete.json',{'models':completion,'completed_at_unix':time.time(),'config_sha256':sha(ROOT/'config.json')})

def temporal():
    assert (ROOT/'baselines/classical_complete.json').exists(),'Classical baselines must finish before temporal training'
    assert not (ROOT/'baselines/UniLSTM/summary.json').exists(),'Temporal baseline already evaluated; no repeated model selection'
    import torch
    from torch import nn
    from torch.utils.data import DataLoader, TensorDataset
    torch.set_num_threads(4);torch.set_num_interop_threads(1);torch.use_deterministic_algorithms(True)
    # CPU avoids CUDA nondeterministic backend/environment requirements.
    class UniLSTM(nn.Module):
        def __init__(self,channels,params):
            super().__init__();self.rnn=nn.LSTM(channels,params['hidden_size'],num_layers=params['num_layers'],batch_first=True,bidirectional=False,dropout=0.0);self.head=nn.Linear(params['hidden_size'],2)
        def forward(self,x):
            _,(h,_)=self.rnn(x);return self.head(h[-1])
    df,d,y=load_inputs();x=d['sequence'];cfg=config();hp=cfg['models']['UniLSTM']
    pred=np.full(len(y),-1);scores=np.full(len(y),np.nan);fold_metrics=[];training=[];history=[]
    path=ROOT/'checkpoints/UniLSTM';path.mkdir(exist_ok=True)
    for f in range(5):
        tr=df.fold.to_numpy()!=f;va=~tr
        assert not set(df.loc[tr,'source_sha256']) & set(df.loc[va,'source_sha256'])
        seed=cfg['seed']+f;random.seed(seed);np.random.seed(seed);torch.manual_seed(seed)
        imputer=SimpleImputer(strategy='mean',keep_empty_features=True).fit(x[tr].reshape(-1,x.shape[-1]))
        scaler=StandardScaler().fit(imputer.transform(x[tr].reshape(-1,x.shape[-1])))
        transform=lambda a:torch.tensor(scaler.transform(imputer.transform(a.reshape(-1,x.shape[-1]))).reshape(a.shape),dtype=torch.float32)
        train_x=transform(x[tr]);val_x=transform(x[va]);train_y=torch.tensor(y[tr],dtype=torch.long)
        assert torch.isfinite(train_x).all() and torch.isfinite(val_x).all()
        assert scaler.n_samples_seen_==int(tr.sum())*128
        generator=torch.Generator().manual_seed(seed)
        loader=DataLoader(TensorDataset(train_x,train_y),batch_size=hp['batch_size'],shuffle=True,generator=generator,num_workers=0)
        model=UniLSTM(x.shape[-1],hp);optimizer=torch.optim.Adam(model.parameters(),lr=hp['learning_rate'],weight_decay=hp['weight_decay']);loss_fn=nn.CrossEntropyLoss()
        start=time.perf_counter()
        for epoch in range(hp['epochs']):
            model.train();loss_sum=0.0
            for bx,by in loader:
                optimizer.zero_grad();loss=loss_fn(model(bx),by);loss.backward();nn.utils.clip_grad_norm_(model.parameters(),hp['gradient_clip']);optimizer.step();loss_sum+=loss.item()*len(by)
            history.append({'fold':f,'epoch':epoch+1,'train_cross_entropy':loss_sum/int(tr.sum())})
        # Evaluate the held-out sources exactly once, after the fixed final epoch.
        model.eval()
        with torch.no_grad():
            probs=torch.softmax(model(val_x),dim=1).numpy();train_p=model(train_x).argmax(1).numpy()
        p=probs.argmax(1);pred[va]=p;scores[va]=probs[:,1]
        m={'fold':f,**metrics(y[va],p)};fold_metrics.append(m)
        fit_audit={'fold':f,'seed':seed,'epochs':hp['epochs'],'parameter_count':sum(p.numel() for p in model.parameters()),'train_n':int(tr.sum()),'validation_n':int(va.sum()),'source_intersection':[],'fit_seconds':time.perf_counter()-start,'resubstitution_train_metrics':metrics(y[tr],train_p),'train_repetition_ids':df.loc[tr,'repetition_id'].tolist(),'validation_repetition_ids':df.loc[va,'repetition_id'].tolist(),'scaler':{'mean':scaler.mean_.tolist(),'scale':scaler.scale_.tolist(),'n_samples_seen':int(scaler.n_samples_seen_)}}
        fit_audit['imputer']={'strategy':'mean','statistics':imputer.statistics_.tolist(),'fit_rows':int(tr.sum())*128,'training_missing_values':int(np.isnan(x[tr]).sum()),'validation_missing_values':int(np.isnan(x[va]).sum()),'no_indicators':True}
        training.append(fit_audit)
        torch.save({'state_dict':model.state_dict(),'hyperparameters':hp,'temporal_names':d['temporal_names'].tolist(),'imputer_statistics':imputer.statistics_.tolist(),'scaler_mean':scaler.mean_.tolist(),'scaler_scale':scaler.scale_.tolist(),'seed':seed,'fold':f,'feature_version':cfg['feature_version'],'manifest_sha256':verify_config()['manifest_sha256'],'fold_assignments_sha256':sha(ROOT/'splits/fold_assignments.csv')},path/f'fold_{f}.pth')
        print(f'UniLSTM fold {f}: {m}',flush=True)
    assert (pred>=0).all() and np.isfinite(scores).all()
    persist_model_results('UniLSTM',df,y,pred,scores,fold_metrics,training)
    pd.DataFrame(history).to_csv(ROOT/'baselines/UniLSTM/training_loss.csv',index=False)
    dump(ROOT/'baselines/phase1_training_complete.json',{'completed_at_unix':time.time(),'models':['LogisticRegression','RandomForest','HistGradientBoosting','SVM','UniLSTM'],'no_production_fit':True,'config_sha256':sha(ROOT/'config.json')})

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('stage',choices=['classical','temporal']);args=parser.parse_args()
    classical() if args.stage=='classical' else temporal()
