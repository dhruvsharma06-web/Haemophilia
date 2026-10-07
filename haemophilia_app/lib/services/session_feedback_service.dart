/// Natural-language generation grounded in recorded metrics. A trained model
/// needs clinician-labelled examples; no synthetic medical conclusions are used.
class SessionFeedback {
  final String brief;
  final List<String> patientDetails;
  final List<String> doctorDetails;
  const SessionFeedback(this.brief, this.patientDetails, this.doctorDetails);
}

SessionFeedback generateSessionFeedback({
  required int total,
  required int correct,
  required int target,
  required String status,
  required Map<String, int> issues,
  required Map<String, (int, int)> exercises,
  bool hindi = false,
}) {
  final completed = total < 0 ? 0 : total;
  final good = correct.clamp(0, completed);
  String choose(String en, String hi) => hindi ? hi : en;
  if (completed == 0) {
    return SessionFeedback(
      choose(
        'No completed repetitions were recorded. There is not enough information to assess movement quality.',
        'कोई पूर्ण दोहराव रिकॉर्ड नहीं हुआ। गतिविधि की गुणवत्ता का आकलन करने के लिए पर्याप्त जानकारी नहीं है।',
      ),
      [
        choose(
          'Check camera positioning and review the demonstration before your next prescribed session.',
          'अगले निर्धारित सत्र से पहले कैमरे की स्थिति जाँचें और व्यायाम का प्रदर्शन देखें।',
        ),
      ],
      [
        choose(
          'No completed-repetition data is available. Review camera visibility and whether the patient stopped early.',
          'पूर्ण दोहराव का डेटा उपलब्ध नहीं है। कैमरे की दृश्यता और मरीज ने सत्र जल्दी रोका या नहीं, इसकी समीक्षा करें।',
        ),
      ],
    );
  }
  final rate = (100 * good / completed).round();
  final observation = choose(
    '$good of $completed recorded repetitions met the system’s form criteria ($rate%).',
    'रिकॉर्ड किए गए $completed दोहराव में से $good ने सिस्टम के सही रूप के मानदंड पूरे किए ($rate%)।',
  );
  final completion = target > 0
      ? good >= target
            ? choose(
                'The recorded correct-repetition target was reached.',
                'रिकॉर्ड किए गए सही दोहराव का लक्ष्य पूरा हुआ।',
              )
            : choose(
                'The recorded correct-repetition target was not reached ($good/$target).',
                'रिकॉर्ड किए गए सही दोहराव का लक्ष्य पूरा नहीं हुआ ($good/$target)।',
              )
      : choose(
          'No repetition target was recorded.',
          'दोहराव का लक्ष्य रिकॉर्ड नहीं किया गया।',
        );
  final patient = <String>[completion];
  if (completed > good) {
    patient.add(
      choose(
        'Some repetitions needed adjustment. Review the demonstration and your doctor’s instructions before the next session; do not add extra repetitions to compensate.',
        'कुछ दोहराव में सुधार की आवश्यकता थी। अगले सत्र से पहले प्रदर्शन और डॉक्टर के निर्देश देखें; इसकी भरपाई के लिए अतिरिक्त दोहराव न करें।',
      ),
    );
  }
  if (status == 'paused' || status == 'abandoned') {
    patient.add(
      choose(
        'This session was stopped or paused. The report covers only the activity recorded so far.',
        'यह सत्र रोका या विराम दिया गया था। रिपोर्ट में केवल अब तक रिकॉर्ड की गई गतिविधि शामिल है।',
      ),
    );
  }
  final doctor = <String>[
    observation,
    completion,
    choose(
      'Camera classifications describe observed movement and do not establish pain, bleeding, clinical improvement, or treatment safety.',
      'कैमरे के वर्गीकरण केवल देखी गई गतिविधि बताते हैं; वे दर्द, रक्तस्राव, चिकित्सकीय सुधार या उपचार की सुरक्षा की पुष्टि नहीं करते।',
    ),
  ];
  final ordered = issues.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final issue in ordered.take(3)) {
    doctor.add(
      choose(
        'Recorded form flag: ${issue.key} (${issue.value} repetitions). Review the relevant movements before changing the plan.',
        'रिकॉर्ड किया गया रूप संबंधी संकेत: ${issue.key} (${issue.value} दोहराव)। योजना बदलने से पहले संबंधित गतिविधियों की समीक्षा करें।',
      ),
    );
  }
  for (final e in exercises.entries) {
    doctor.add(
      choose(
        '${e.key}: ${e.value.$1} of ${e.value.$2} repetitions met the form criteria.',
        '${e.key}: ${e.value.$2} में से ${e.value.$1} दोहराव सही रूप के मानदंड पूरे करते हैं।',
      ),
    );
  }
  patient.add(
    choose(
      'If you experienced pain, swelling, or bleeding, tell your care team before continuing.',
      'यदि दर्द, सूजन या रक्तस्राव हुआ हो, तो जारी रखने से पहले अपनी चिकित्सा टीम को बताएँ।',
    ),
  );
  return SessionFeedback('$observation $completion', patient, doctor);
}
