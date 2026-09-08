import numpy as np


def calculate_score(
    range_of_motion,
    duration,
    smoothness,
    prediction,
    confidence
):
    """
    Calculate an overall exercise score from 0-100.

    This is a prototype scoring system, not a clinical score.
    """

    # ---------------------------------------------------------
    # 1. Range of motion score
    # ---------------------------------------------------------
    # Full shoulder flexion target is approximately 150 degrees
    # for this prototype.

    rom_score = min(
        range_of_motion / 150.0,
        1.0
    ) * 100

    # ---------------------------------------------------------
    # 2. Speed score
    # ---------------------------------------------------------

    if 1.5 <= duration <= 2.5:
        speed_score = 100

    elif 1.0 <= duration < 1.5:
        speed_score = 85

    elif 2.5 < duration <= 3.5:
        speed_score = 80

    elif duration < 1.0:
        speed_score = 60

    else:
        speed_score = 60

    # ---------------------------------------------------------
    # 3. Smoothness score
    # ---------------------------------------------------------

    smoothness_score = np.clip(
        smoothness,
        0,
        1
    ) * 100

    # ---------------------------------------------------------
    # 4. Form score
    # ---------------------------------------------------------

    if prediction == "correct":
        form_score = confidence
    else:
        form_score = 100 - confidence

    # ---------------------------------------------------------
    # Weighted final score
    # ---------------------------------------------------------

    score = (
        0.35 * rom_score +
        0.20 * speed_score +
        0.20 * smoothness_score +
        0.25 * form_score
    )

    return round(
        float(np.clip(score, 0, 100)),
        1
    )


def get_feedback(
    range_of_motion,
    duration,
    smoothness,
    prediction,
    confidence
):
    """
    Generate simple human-readable feedback.
    """

    feedback = []

    # Form
    if prediction == "incorrect":

        feedback.append(
            "Form needs improvement."
        )

    elif confidence >= 80:

        feedback.append(
            "Good form."
        )

    else:

        feedback.append(
            "Form looks acceptable."
        )

    # Range of motion
    if range_of_motion < 90:

        feedback.append(
            "Try to increase your range of motion."
        )

    elif range_of_motion >= 120:

        feedback.append(
            "Good range of motion."
        )

    # Speed
    if duration < 1.0:

        feedback.append(
            "Movement is too fast."
        )

    elif duration > 3.5:

        feedback.append(
            "Try a slightly more controlled pace."
        )

    else:

        feedback.append(
            "Good movement speed."
        )

    # Smoothness
    if smoothness < 0.20:

        feedback.append(
            "Try to make the movement smoother."
        )

    elif smoothness >= 0.35:

        feedback.append(
            "Movement is smooth."
        )

    return " ".join(feedback)


def analyze_rep(
    range_of_motion,
    duration,
    smoothness,
    prediction,
    confidence
):
    """
    Complete analysis of one repetition.
    """

    score = calculate_score(
        range_of_motion,
        duration,
        smoothness,
        prediction,
        confidence
    )

    feedback = get_feedback(
        range_of_motion,
        duration,
        smoothness,
        prediction,
        confidence
    )

    # Speed label
    if duration < 1.0:
        speed = "Fast"

    elif duration <= 2.5:
        speed = "Good"

    else:
        speed = "Slow"

    return {
        "form": prediction,
        "confidence": round(confidence, 1),
        "range_of_motion": round(
            range_of_motion,
            1
        ),
        "duration": round(
            duration,
            2
        ),
        "speed": speed,
        "smoothness": round(
            smoothness * 100,
            1
        ),
        "score": score,
        "feedback": feedback
    }


if __name__ == "__main__":

    # Simple test
    result = analyze_rep(
        range_of_motion=135,
        duration=2.1,
        smoothness=0.45,
        prediction="correct",
        confidence=94
    )

    print("\nExample analysis:")
    print(result)