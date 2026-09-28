import numpy as np


def calculate_score(
    range_of_motion,
    duration,
    prediction=None,
    confidence=None,
    smoothness=None,
    **kwargs
):
    """
    Calculate an overall exercise score from 0-100 based on movement quality.

    IMPORTANT:
    This is an engineering prototype scoring algorithm designed to provide
    meaningful feedback during rehabilitation exercises. It is NOT clinically
    validated.

    Scoring Weights:
      - Form Quality:      45% (LSTM classification / kinematic form integrity)
      - Range of Motion:   35% (angular excursion toward exercise target)
      - Speed / Duration:  20% (repetition cadence and control)

    Design Principles:
      - Clearly incorrect / compensatory movements receive substantial penalties (typically 20-55).
      - Mediocre movements stay in the middle (55-75).
      - Correct movements with strong ROM and controlled speed reach 90-100.
      - Smoothness is intentionally excluded as it degrades signal consistency.
    """
    # Support backward-compatible positional calling:
    # Legacy: calculate_score(rom, duration, smoothness, prediction, confidence)
    # New:    calculate_score(rom, duration, prediction, confidence)
    if isinstance(prediction, (int, float)) and confidence is not None:
        # Legacy caller passed smoothness as 3rd arg, prediction as 4th, confidence as 5th
        actual_pred = str(confidence)
        actual_conf = float(smoothness) if smoothness is not None else 80.0
    elif isinstance(prediction, str):
        actual_pred = prediction
        actual_conf = float(confidence) if confidence is not None else 80.0
    elif smoothness is not None and isinstance(smoothness, str):
        actual_pred = smoothness
        actual_conf = float(prediction) if prediction is not None else 80.0
    else:
        actual_pred = str(prediction or "correct")
        actual_conf = float(confidence or 80.0)

    pred_lower = actual_pred.strip().lower()
    is_correct = (
        "correct" in pred_lower
        or "normal" in pred_lower
        or "good" in pred_lower
    ) and "incorrect" not in pred_lower and "abnormal" not in pred_lower

    # ---------------------------------------------------------
    # 1. Form Quality Score (45% weight)
    # ---------------------------------------------------------
    # For correct form: reward high confidence up to 100.
    # For incorrect form: heavily penalize proportional to error confidence.
    if is_correct:
        # Confidence typically 50-100
        form_score = float(np.clip(actual_conf, 0.0, 100.0))
    else:
        # Form error detected. If model has high confidence in incorrect form,
        # form score drops sharply (e.g. 90% conf -> 10.0 pts).
        form_score = float(np.clip((100.0 - actual_conf) * 0.8, 0.0, 45.0))

    # ---------------------------------------------------------
    # 2. Range of Motion Score (35% weight)
    # ---------------------------------------------------------
    # Target shoulder flexion is ~150 degrees.
    rom = float(max(0.0, range_of_motion))
    if rom >= 155.0:
        rom_score = 100.0
    elif rom >= 145.0:
        rom_score = 90.0 + ((rom - 145.0) / 10.0) * 10.0
    elif rom >= 130.0:
        rom_score = 75.0 + ((rom - 130.0) / 15.0) * 15.0
    elif rom >= 100.0:
        rom_score = 50.0 + ((rom - 100.0) / 30.0) * 25.0
    else:
        rom_score = max(0.0, (rom / 100.0) * 50.0)

    # ---------------------------------------------------------
    # 3. Speed / Duration Score (20% weight)
    # ---------------------------------------------------------
    # Optimal rep duration for controlled shoulder flexion is 1.5s - 2.7s.
    dur = float(duration)
    if 1.5 <= dur <= 2.7:
        speed_score = 100.0
    elif 1.2 <= dur < 1.5:
        # Slightly fast
        speed_score = 80.0
    elif 2.7 < dur <= 3.5:
        # Slightly slow
        speed_score = 80.0
    elif dur < 1.2:
        # Rushed movement (<1.2s)
        speed_score = max(25.0, 70.0 - (1.2 - dur) * 50.0)
    else:
        # Slow / hesitation (>3.5s)
        speed_score = max(25.0, 70.0 - (dur - 3.5) * 20.0)

    # ---------------------------------------------------------
    # Weighted Final Score (0 - 100)
    # ---------------------------------------------------------
    raw_score = (
        0.45 * form_score +
        0.35 * rom_score +
        0.20 * speed_score
    )

    # For incorrect form, apply a meaningful penalty to ensure an incorrect
    # repetition cannot score high (clamped to at most 55.0).
    if not is_correct:
        final_score = min(raw_score, 55.0)
        # If error was severe (low form score), reduce further
        if form_score < 20.0:
            final_score = min(final_score, 45.0)
    else:
        final_score = raw_score

    return round(float(np.clip(final_score, 0.0, 100.0)), 1)


def get_feedback(
    range_of_motion,
    duration,
    prediction="correct",
    confidence=80.0,
    smoothness=None,
    **kwargs
):
    """
    Generate clear, explainable feedback based on form, ROM, and speed.
    (Smoothness is excluded).
    """
    # Handle legacy 5-argument ordering
    if isinstance(prediction, (int, float)) and confidence is not None:
        actual_pred = str(confidence)
        actual_conf = float(smoothness) if smoothness is not None else 80.0
    else:
        actual_pred = str(prediction or "correct")
        actual_conf = float(confidence or 80.0)

    feedback = []
    pred_lower = actual_pred.strip().lower()
    is_correct = (
        "correct" in pred_lower
        or "normal" in pred_lower
        or "good" in pred_lower
    ) and "incorrect" not in pred_lower and "abnormal" not in pred_lower

    # Form feedback
    if not is_correct:
        feedback.append("Form needs improvement. Maintain proper posture and symmetry.")
    elif actual_conf >= 85:
        feedback.append("Excellent form maintained.")
    else:
        feedback.append("Good form.")

    # Range of motion feedback
    if range_of_motion < 100:
        feedback.append("Range of motion is low. Work toward reaching higher if comfortable.")
    elif range_of_motion < 135:
        feedback.append("Moderate range of motion. Try to reach a bit further.")
    else:
        feedback.append("Great range of motion.")

    # Speed feedback
    if duration < 1.2:
        feedback.append("Movement was too fast. Slow down for better control.")
    elif duration > 3.5:
        feedback.append("Movement was slow. Try to maintain a continuous, steady pace.")
    else:
        feedback.append("Pace was steady and controlled.")

    return " ".join(feedback)


def analyze_rep(
    range_of_motion,
    duration,
    prediction="correct",
    confidence=80.0,
    smoothness=None,
    **kwargs
):
    """
    Complete analysis of one repetition without smoothness.
    """
    score = calculate_score(
        range_of_motion=range_of_motion,
        duration=duration,
        prediction=prediction,
        confidence=confidence,
    )

    feedback = get_feedback(
        range_of_motion=range_of_motion,
        duration=duration,
        prediction=prediction,
        confidence=confidence,
    )

    if duration < 1.2:
        speed = "Fast"
    elif duration <= 2.7:
        speed = "Good"
    else:
        speed = "Slow"

    return {
        "form": prediction,
        "confidence": round(float(confidence), 1),
        "range_of_motion": round(float(range_of_motion), 1),
        "duration": round(float(duration), 2),
        "speed": speed,
        "score": score,
        "feedback": feedback,
    }


if __name__ == "__main__":
    # Test cases
    # 1. Excellent rep: correct form, 152 deg ROM, 2.1s duration
    good = analyze_rep(range_of_motion=152, duration=2.1, prediction="correct", confidence=95)
    print("Good Rep:", good)

    # 2. Mediocre rep: correct form, 115 deg ROM, 2.0s duration
    med = analyze_rep(range_of_motion=115, duration=2.0, prediction="correct", confidence=78)
    print("Mediocre Rep:", med)

    # 3. Bad rep: incorrect form (asymmetry/tilt), 85 deg ROM, 0.8s duration
    bad = analyze_rep(range_of_motion=85, duration=0.8, prediction="incorrect", confidence=90)
    print("Bad Rep:", bad)