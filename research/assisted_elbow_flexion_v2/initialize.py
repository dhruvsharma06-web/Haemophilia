"""One-time protocol freeze; run before extracting or viewing model outcomes."""
import json, shutil, subprocess, sys, platform
from datetime import datetime, timezone
from pathlib import Path
import numpy as np
import pandas as pd
from sklearn.model_selection import StratifiedGroupKFold
from common import ROOT, REPO, DATA, RELEASE, MANIFEST_SHA, sha, dump, canonical

def main():
    assert not (ROOT / 'protocol_lock.json').exists(), 'Protocol already frozen'
    for name in ['preprocessing/raw_landmarks','features','splits','baselines','reports','checkpoints','provenance']:
        (ROOT / name).mkdir(parents=True, exist_ok=True)
    rows, check = canonical(); df = pd.DataFrame(rows)
    config = {
      'release_id':'human280_20261004', 'manifest_sha256':MANIFEST_SHA,
      'feature_version':'world_kinematics_v1_2', 'seed':42,
      'authorization':'Explicit user authorization on 2026-10-04 for Phase 1 only; archived release authorization flag reflects earlier finalization stage. Canonical contract remains immutable.',
      'target':{'Correct':0,'Incorrect':1}, 'group_key':'source_sha256',
      'pose':{'model_complexity':1,'smooth_landmarks':False,'static_image_mode':False,'enable_segmentation':False,'min_detection_confidence':0.5,'min_tracking_confidence':0.5},
      'decode':{'width':640,'frame_policy':'Every original decoded presentation frame in union of inclusive canonical ranges; reset graph at each gap. No fps conversion.', 'workers':3},
      'quality':{'minimum_joint_visibility':0.5,'max_internal_gap_seconds':0.50,'minimum_valid_fraction':0.8,'max_endpoint_hold_seconds':0.1,'smoothing':'None; raw estimated angles, explicit interpolation only.'},
      'representation':{'temporal_length':128,'base_channels':['active_angle','opposing_angle','active_flare','opposing_flare','torso_lean','shoulder_depth_ratio'], 'extra_channels':['active_velocity','opposing_velocity','angle_asymmetry','flare_asymmetry','elapsed_seconds'], 'units':['deg','deg','ratio','ratio','deg','ratio','deg/s','deg/s','deg','ratio','s'], 'scalar_summary':'34 predeclared scalar summaries in features/build_features.py; no hand/subject/source/folder or QC flags as predictors.'},
      'folds':{'type':'StratifiedGroupKFold','n_splits':5,'shuffle':True,'random_state':42},
      'models':{
        'LogisticRegression':{'C':1.0,'max_iter':3000,'solver':'lbfgs','class_weight':None,'random_state':42},
        'RandomForest':{'n_estimators':500,'max_depth':None,'min_samples_leaf':2,'max_features':'sqrt','class_weight':None,'random_state':42,'n_jobs':4},
        'HistGradientBoosting':{'max_iter':100,'learning_rate':0.1,'max_leaf_nodes':7,'min_samples_leaf':10,'l2_regularization':1.0,'early_stopping':False,'random_state':42},
        'SVM':{'C':1.0,'kernel':'rbf','gamma':'scale','class_weight':None,'probability':False},
        'UniLSTM':{'hidden_size':32,'num_layers':1,'bidirectional':False,'dropout':0.0,'epochs':60,'batch_size':32,'learning_rate':0.001,'weight_decay':0.0,'gradient_clip':1.0,'optimizer':'Adam','loss':'unweighted CrossEntropyLoss','device':'cpu','seed_policy':'42 + fold', 'checkpoint':'Final fixed epoch only; no validation monitoring or selection'}
      },
      'scaling':'StandardScaler fit exclusively on outer training rows (temporal: training rows and timesteps). Tree models unscaled.',
      'selection':'No parameter/feature search, no threshold tuning, no inner split needed for fixed training schedule; no repeated outer evaluation for model changes.',
      'failure_policy':'Preserve raw missing values and bounded recorded repairs. Unsupported intervals and dependent summaries remain NaN; retain all canonical repetitions with training-fold mean imputation. Decode/provenance corruption still halts training. Never silently drop examples.',
      'class_balance':'Original 183/97; no weights or resampling',
      'stop':'After Phase 1 report; no production model, no full-data deployment fit, no Phase 2.',
      'fold_imputation':{'strategy':'mean','fit':'Outer training repetitions only; temporal uses training timesteps only','add_indicator':False,'keep_empty_features':True,'finite_model_input_required':True}}
    dump(ROOT / 'config.json', config)
    y = (df.label == 'Incorrect').astype(int).to_numpy()
    folds = np.full(len(df), -1)
    for fold, (tr, va) in enumerate(StratifiedGroupKFold(**{k:v for k,v in config['folds'].items() if k!='type'}).split(df,y,df.source_sha256)):
        assert not set(df.iloc[tr].source_sha256) & set(df.iloc[va].source_sha256)
        assert set(y[tr]) == set(y[va]) == {0,1}
        folds[va] = fold
    df['fold'] = folds
    check(rows, dict(zip(df.repetition_id, map(str,folds))))
    cols=['repetition_id','source_sha256','video_id','subject_id','hand','label','fold']
    df[cols].to_csv(ROOT/'splits/fold_assignments.csv',index=False)
    composition=[]
    for f in range(5):
        tr=df[df.fold!=f]; va=df[df.fold==f]
        composition.append({'fold':f,'train_n':len(tr),'validation_n':len(va),'train_sources':tr.source_sha256.nunique(),'validation_sources':va.source_sha256.nunique(),'Correct':int((va.label=='Correct').sum()),'Incorrect':int((va.label=='Incorrect').sum()),'Left':int((va.hand=='Left').sum()),'Right':int((va.hand=='Right').sum()),'source_intersection':[]})
    dump(ROOT/'splits/leakage_audit.json', composition)
    pd.DataFrame([{k:v for k,v in x.items() if k!='source_intersection'} for x in composition]).to_csv(ROOT/'splits/fold_composition.csv',index=False)
    shutil.copyfile(Path(r'<local_path_redacted>, ROOT/'provenance/phase1_user_authorization.txt')
    import cv2, scipy, sklearn, torch, mediapipe
    env={'python':sys.version,'platform':platform.platform(),'executable':sys.executable,'packages':{m.__name__:m.__version__ for m in [np,pd,cv2,scipy,sklearn,torch,mediapipe]},'cuda_available':torch.cuda.is_available(),'ffmpeg':subprocess.check_output(['ffmpeg','-version'],text=True).splitlines()[0]}
    assets=list(Path(mediapipe.__file__).parent.glob('modules/pose*/*.tflite'))
    env['mediapipe_model_assets']={str(p):sha(p) for p in assets}
    dump(ROOT/'provenance/environment.json',env)
    (ROOT/'provenance/pip_freeze.txt').write_text(subprocess.check_output([sys.executable,'-m','pip','freeze'],text=True))
    # Protect all prior snapshot members, the entire finalized V2 release, and tracked files.
    paths=set(json.loads((RELEASE/'evidence/protected_files_before.json').read_text()))
    paths.update(str(p.resolve()) for p in RELEASE.rglob('*') if p.is_file())
    tracked=subprocess.check_output(['git','ls-files'],cwd=REPO,text=True).splitlines()
    paths.update(str((REPO/p).resolve()) for p in tracked if (REPO/p).is_file())
    for folder in ['models','data','processed_data/assisted_elbow_flexion']:
        paths.update(str(p.resolve()) for p in (REPO/folder).rglob('*') if p.is_file())
    # Original videos are hashed again by extraction; include their expected hashes here too.
    protected={str(Path(p)):sha(p) for p in sorted(paths) if Path(p).is_file()}
    for r in rows: protected[r['source_video']]=r['source_sha256']
    dump(ROOT/'provenance/protected_files_before.json',protected)
    (ROOT/'provenance/git_status_before.txt').write_text(subprocess.check_output(['git','status','--porcelain','--untracked-files=all'],cwd=REPO,text=True))
    dump(ROOT/'protocol_lock.json', {'frozen_at_utc':datetime.now(timezone.utc).isoformat(),'config_sha256':sha(ROOT/'config.json'),'fold_assignments_sha256':sha(ROOT/'splits/fold_assignments.csv'),'manifest_sha256':MANIFEST_SHA})
    print(json.dumps({'canonical_n':len(rows),'sources':df.source_sha256.nunique(),'protected_files':len(protected),'folds':composition}), flush=True)

if __name__=='__main__':main()
