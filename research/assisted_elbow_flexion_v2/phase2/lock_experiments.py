"""Lock four audit-justified experiments before their outcomes are observed."""
from datetime import datetime,timezone
from phase2_utils import P2,P1,inputs,verify_inputs,dump,sha
import json

def main():
    verify_inputs()
    assert not (P2/'experiment_lock.json').exists()
    audit=json.loads((P2/'audits/AUDIT_COMPLETE.json').read_text())
    for p,h in audit['audit_outputs_hashes'].items():assert sha(P2/p)==h
    plan={
      'seed':42,'target':{'Correct':0,'Incorrect':1},'dataset':'human280_20261004','examples':280,
      'fold_assignments_sha256':sha(P1/'splits/fold_assignments.csv'),
      'reference':'Read-only frozen Phase 1 SVM OOF predictions, 34 features; no outer refit or checkpoint replacement',
      'feature_candidates':{
        'VelocityP95':{'change':'Replace only active/opposing peak_abs_velocity scalars with empirical original-frame p95 absolute velocity. Velocity already uses actual PTS. No smoothing or augmentation. Incomplete channel remains NaN.','reason':f'Active peak/p95 median {audit["active_peak_to_p95_ratio_median"]:.3f}, max {audit["active_peak_to_p95_ratio_max"]:.3f}; extreme differentiation sensitivity','dimensions':34},
        'WithoutViewProxies':{'change':'Remove six scalar mean/max/range torso_lean and shoulder_depth_ratio features; retain all other 28 features unchanged','reason':'Explicit camera-axis formulas plus mean torso lean source eta-squared 0.933 after class-mean subtraction. Association alone does not prove artifacts.','dimensions':28}},
      'model_candidates':{
        'BalancedSVM':{'change':'Original 34 features and StandardScaler; SVC class_weight=balanced fitted from training-fold class counts only','reason':'Frozen baseline has 26 Incorrect->Correct errors and lower Incorrect recall; fixed standard weighting is a controlled diagnostic, not tuned weights'},
        'RobustScalerSVM':{'change':'Original 34 features; replace StandardScaler by median/IQR RobustScaler(quantile_range=(25,75), unit_variance=False)','reason':'Audited derivative/extreme and source-distribution sensitivity; no outlier removal'}},
      'svm_fixed':{'C':1.0,'kernel':'rbf','gamma':'scale','class_weight':None,'probability':False},
      'imputation':{'strategy':'mean','keep_empty_features':True,'add_indicator':False,'fit':'training portion of each fit only'},
      'inner_selection':{'type':'StratifiedGroupKFold','n_splits':3,'shuffle':True,'random_state':'42+100*outer_fold','group':'source_sha256','candidates':['FrozenPhase1SVM','VelocityP95','WithoutViewProxies','BalancedSVM','RobustScalerSVM'],'eligibility':'Inner pooled balanced accuracy, macro-F1 and Incorrect recall each >= inner reference; per-source accuracy sample std <= reference+0.02','ranking':'Among eligible candidates, maximize inner balanced accuracy, then macro-F1, then Incorrect recall, then smaller source std. Default to reference if none qualify.','purpose':'Select only inside outer training groups; evaluate selected procedure once on outer held-out sources; no pooled outer tuning'},
      'descriptive_outer_interesting_rule':{'metrics':'Pooled balanced accuracy, macro-F1 and Incorrect recall all >= frozen reference','stability':'Per-source accuracy sample std no greater than reference+0.02; lowest-source accuracy no more than 0.05 below reference; non-negative per-source accuracy delta on at least half of 29 sources','meaning':'Diagnostic screening only, not a selected winner or deployment rule'},
      'leave_one_source_out':{'model':'Fresh diagnostic fits of the unchanged Phase 1 SVM specification','folds':29,'group':'source_sha256','selection':'none','note':'More training sources than five-fold evaluation; partition sensitivity diagnostic, not independent confirmation or verified subject validation'},
      'reused_outer_fold_caveat':'Phase 2 follows inspection of Phase 1 outer predictions and data. Matched-fold candidate comparisons are development evidence, not untouched-test confirmation. Inner grouping constrains fitting/selection but does not erase audit-driven representation development.',
      'no_probability_calibration':True,'no_C_gamma_sweep':True,'no_data_augmentation_relabeling_or_deployment_checkpoints':True,
      'stop':'After Phase 2 report and preservation audit; no Phase 3 or production changes',
    }
    dump(P2/'experiment_config.json',plan)
    dump(P2/'experiment_lock.json',{'locked_at_utc':datetime.now(timezone.utc).isoformat(),'config_sha256':sha(P2/'experiment_config.json'),'audit_complete_sha256':sha(P2/'audits/AUDIT_COMPLETE.json'),'diagnostics_sha256':sha(P2/'audits/repetition_diagnostics.csv'),'frozen_phase1_input_hashes_sha256':sha(P2/'provenance/frozen_input_hashes.json')})
    print('Locked two feature experiments, two model experiments, grouped inner selection and 29-source diagnostic.')

if __name__=='__main__':main()
