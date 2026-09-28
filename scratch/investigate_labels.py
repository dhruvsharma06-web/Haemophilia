import pandas as pd
import numpy as np

df = pd.read_csv('processed_data/assisted_elbow_flexion/repetition_ground_truth_audit.csv')

print('=== 1. INCORRECT FOLDER REPETITIONS THAT APPEAR BIOMECHANICALLY GOOD ===')
inc_all = df[df['folder_label'] == 'incorrect']
# In Person 1 & 2:
inc_good = inc_all[(inc_all['rom'] >= 40.0) & (inc_all['min_elbow_angle'] <= 98.0) & (inc_all['elbow_flare'] <= 0.32)]
print(f"Count: {len(inc_good)} out of {len(inc_all)} incorrect reps ({len(inc_good)/len(inc_all)*100:.1f}%)")
for idx, r in inc_good.head(10).iterrows():
    print(f"  [{r['subject']}] {r['video']} rep {r['repetition_index']}: ROM={r['rom']:.1f}°, MinAngle={r['min_elbow_angle']:.1f}°, Flare={r['elbow_flare']:.3f}, Dur={r['duration']:.2f}s, Rot={r['torso_rotation']:.1f}°")

print('\n=== 2. CORRECT FOLDER REPETITIONS WITH POOR ROM OR DEFECTS ===')
corr_all = df[df['folder_label'] == 'correct']
corr_poor = corr_all[(corr_all['rom'] <= 32.0) | (corr_all['min_elbow_angle'] >= 105.0) | (corr_all['elbow_flare'] >= 0.35)]
print(f"Count: {len(corr_poor)} out of {len(corr_all)} correct reps ({len(corr_poor)/len(corr_all)*100:.1f}%)")
for idx, r in corr_poor.head(10).iterrows():
    print(f"  [{r['subject']}] {r['video']} rep {r['repetition_index']}: ROM={r['rom']:.1f}°, MinAngle={r['min_elbow_angle']:.1f}°, Flare={r['elbow_flare']:.3f}, Dur={r['duration']:.2f}s, Rot={r['torso_rotation']:.1f}°")

print('\n=== 3. REPETITIONS AFFECTED BY MEDIAPIPE CORRUPTION / ARTIFACTS ===')
manifest = pd.read_csv('processed_data/assisted_elbow_flexion/dataset_manifest.csv')
corrupt = manifest[manifest['clamped_pct'] > 0.0]
print(f"Videos with fallback clamping: {len(corrupt['video_name'].unique())} videos, {len(corrupt)} total reps")
for v, grp in corrupt.groupby(['video_name', 'subject_id']):
    print(f"  {v[0]} ({v[1]}): {len(grp)} reps, avg clamped pct = {grp['clamped_pct'].mean():.2f}%")

print('\n=== 4. AMBIGUOUS QUALITY (BORDERLINE ROM / ANGLE) ===')
ambig = df[(df['rom'].between(33.0, 42.0)) & (df['min_elbow_angle'].between(94.0, 102.0))]
print(f"Count of ambiguous reps: {len(ambig)} ({len(ambig)/len(df)*100:.1f}% of all {len(df)} reps)")
print("Breakdown by folder label:")
print(ambig['folder_label'].value_counts())
print("Breakdown by subject:")
print(ambig.groupby(['subject', 'folder_label']).size())
