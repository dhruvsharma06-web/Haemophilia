const _movementErrors = <String, (String, String)>{
  'TARGET_NOT_HELD': ('Target not held', 'लक्ष्य पर नहीं रुके'),
  'INSUFFICIENT_ROM': ('Limited range of motion', 'गतिविधि की सीमा अधूरी'),
  'INSUFFICIENT_FLEXION': ('Insufficient elbow flexion', 'कोहनी का मोड़ अधूरा'),
  'INCOMPLETE_RETURN': ('Incomplete return', 'अधूरी वापसी'),
  'TOO_FAST': ('Movement too fast', 'गतिविधि बहुत तेज़'),
  'ARM_ASYMMETRY': ('Arms moving unevenly', 'दोनों हाथों की गतिविधि असमान'),
  'RIGHT_ARM_LOW': ('Right arm too low', 'दायां हाथ बहुत नीचे'),
  'LEFT_ARM_LOW': ('Left arm too low', 'बायां हाथ बहुत नीचे'),
  'BODY_TILT': ('Torso movement', 'धड़ की गतिविधि'),
  'UPPER_ARM_POSITION': ('Upper arm position', 'ऊपरी बांह की स्थिति'),
  'SUPPORT_MISSING': (
    'Opposite-hand support missing',
    'दूसरे हाथ का सहारा नहीं दिया',
  ),
  'ELBOW_POSITION': ('Elbow position', 'कोहनी की स्थिति'),
  'ROTATION_DIRECTION': ('Rotation direction', 'घुमाने की दिशा'),
  'ELBOW_FLARE': ('Elbow moved away from torso', 'कोहनी धड़ से दूर हुई'),
  'ELBOW_FLARE_DETECTED': (
    'Elbow moved away from torso',
    'कोहनी धड़ से दूर हुई',
  ),
  'TORSO_ROTATION': ('Torso rotation', 'धड़ घूमा'),
  'TORSO_ROTATION_DETECTED': ('Torso rotation', 'धड़ घूमा'),
  'KNEE_BENT': ('Lifting knee bent', 'उठाते समय घुटना मुड़ा'),
  'HIP_LIFT': ('Hip lifted', 'कूल्हा उठा'),
  'HEEL_LIFT': ('Heel lifted', 'एड़ी उठी'),
  'KNEE_ALIGNMENT': ('Knee alignment', 'घुटने की दिशा'),
  'SQUAT_TOO_DEEP': ('Squat too deep', 'स्क्वाट बहुत गहरा है'),
  'THIGH_MOVEMENT': ('Thigh moved', 'जांघ हिली'),
  'GENERAL_FORM_ERROR': (
    'Movement form needs adjustment',
    'गतिविधि की मुद्रा में सुधार ज़रूरी',
  ),
  'MOVEMENT_RULE': ('Movement needs adjustment', 'गतिविधि में सुधार ज़रूरी'),
};

String movementErrorLabel(String? code, {bool hindi = false}) {
  final value = code?.trim() ?? '';
  final label = _movementErrors[value.toUpperCase()];
  if (label != null) return hindi ? label.$2 : label.$1;
  return value.replaceAll('_', ' ');
}

String? movementCorrection(String? code, {bool hindi = false}) {
  final correction = switch (code?.toUpperCase()) {
    'TARGET_NOT_HELD' || 'INSUFFICIENT_ROM' || 'INSUFFICIENT_FLEXION' => (
      'Review the shown target and brief hold. Use your prescribed comfortable range; ask your doctor if the target is beyond it.',
      'दिखाए गए लक्ष्य और थोड़ी देर रुकने का चरण देखें। डॉक्टर द्वारा बताई आरामदायक सीमा में रहें; लक्ष्य उससे बाहर हो तो डॉक्टर से पूछें।',
    ),
    'INCOMPLETE_RETURN' => (
      'Return gently to your own starting angle and pause before the next repetition.',
      'धीरे से अपने शुरुआती कोण तक लौटें और अगली पुनरावृत्ति से पहले रुकें।',
    ),
    'TOO_FAST' => (
      'Use a steady pace through the outward and return stages.',
      'आगे की गतिविधि और वापसी दोनों चरणों में गति स्थिर रखें।',
    ),
    'SQUAT_TOO_DEEP' => (
      'Use a supported mini squat within your comfortable range. Keep your heels down and knees aligned with your feet.',
      'अपनी आरामदायक सीमा में सहारा लेकर मिनी स्क्वाट करें। एड़ियां नीचे और घुटने पैरों की दिशा में रखें।',
    ),
    'SUPPORT_MISSING' => (
      'Keep the opposite hand supporting the working forearm. Retry the same side when ready.',
      'व्यायाम वाली अग्रबाहु को दूसरे हाथ से सहारा दें। तैयार होने पर उसी हाथ से फिर प्रयास करें।',
    ),
    'ROTATION_DIRECTION' => (
      'Keep your elbows beside your torso and rotate the forearms outward, then return to neutral.',
      'कोहनियां धड़ के पास रखते हुए अग्रबाहुओं को बाहर की ओर घुमाएं, फिर शुरुआती स्थिति में लौटें।',
    ),
    'BODY_TILT' => (
      'Keep your torso steady and review your camera position.',
      'धड़ स्थिर रखें और कैमरे की स्थिति देखें।',
    ),
    'ARM_ASYMMETRY' => (
      'Move both arms together so each reaches the shown target.',
      'दोनों हाथ एक साथ चलाएं ताकि हर हाथ दिखाए गए लक्ष्य तक पहुंचे।',
    ),
    'UPPER_ARM_POSITION' || 'ELBOW_FLARE' || 'ELBOW_FLARE_DETECTED' => (
      'Keep the upper arms beside the torso while the forearms move.',
      'अग्रबाहु चलाते समय ऊपरी बांहें धड़ के पास रखें।',
    ),
    'KNEE_BENT' => (
      'Keep the lifting knee straight within your prescribed comfortable range.',
      'पैर उठाते समय डॉक्टर द्वारा बताई आरामदायक सीमा में घुटना सीधा रखें।',
    ),
    'HEEL_LIFT' => (
      'Keep the heel on the support surface during this exercise.',
      'इस व्यायाम के दौरान एड़ी सहारे की सतह पर रखें।',
    ),
    'KNEE_ALIGNMENT' => (
      'Review the demonstration and keep the knees aligned with the feet.',
      'प्रदर्शन देखें और घुटने पंजों की दिशा में रखें।',
    ),
    _ => null,
  };
  return correction == null
      ? null
      : hindi
      ? correction.$2
      : correction.$1;
}
