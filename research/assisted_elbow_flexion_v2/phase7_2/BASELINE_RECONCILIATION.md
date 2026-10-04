# Strategy 2 Baseline Reconciliation: Phase 6 (66/82) vs. Canonical Evaluator (62/82)

## Executive Conclusion
**Verdict: A. The 62/82 canonical figure is the authoritative and physically correct figure.**

The previously reported Phase 6 figure of 66/82 (80.49%) was an artifact of two compounding implementation errors:
1. **Un-cleared Pre-Buffer on Hand Switches:** In the original Phase 6 `Strategy2Segmenter.set_hand()`, `self.pre_buffer.clear()` was only executed if `self.state == 'READY'`. If the hand was switched while the segmenter was in `POST_ROLL` or `FLEXING`, `reset()` was invoked, but `reset()` failed to empty `pre_buffer`. Stale lookback frames from the opposing arm lingered and formed giant cross-arm phantom segments spanning 463 to 1,111 frames.
2. **Permissive Many-to-One Matching:** Phase 6's evaluation matching policy marked any repetition with intersection > 0 as 'Completed', allowing a single 37-second phantom segment to simultaneously match multiple distinct repetitions with IoUs as low as 0.0244 and 0.0479!

## The 4 Discrepant Repetitions

| Repetition ID | Session | Hand | Manual Window | P6 Status | P6 IoU | Canonical Status | Root Cause |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| `rep_b59965fe88fa0c3f40` | `session_01_both_correct` | Left | [832, 1010] | Completed | 0.3815 | **Missed** | Cross-Arm Buffer Bleed (P6 phantom seg credited via multi-matching) |
| `rep_372c0410acd5099364` | `session_01_both_correct` | Left | [1265, 1480] | Completed | 0.0479 | **Missed** | Cross-Arm Buffer Bleed (P6 phantom seg credited via multi-matching) |
| `rep_ed4d23c464cf750af7` | `session_02_both_mix` | Left | [2144, 2320] | Completed | 0.1399 | **Missed** | Cross-Arm Buffer Bleed (P6 phantom seg credited via multi-matching) |
| `rep_5c39730111cd443d20` | `session_02_both_mix` | Left | [3242, 3432] | Completed | 0.0244 | **Missed** | Cross-Arm Buffer Bleed (P6 phantom seg credited via multi-matching) |

## Implementation Reconciliation Details

When cross-arm buffer contamination is eliminated and standard non-trivial temporal overlap is enforced, Strategy 2 genuinely only completes **62 / 82 repetitions (75.61%)**.
