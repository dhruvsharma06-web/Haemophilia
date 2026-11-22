/// Translates measured values without changing the assessment's thresholds.
String? hindiExerciseFeedback(String text) {
  const number = r'([\d.]+)';
  final patterns = <(String, String Function(RegExpMatch))>[
    (
      '^Keep both elbows bent between $number and $number degrees\\.\$',
      (m) => 'दोनों कोहनियां ${m[1]} से ${m[2]} डिग्री के बीच मोड़कर रखें।',
    ),
    (
      '^Keep your upper arms within $number degrees of your torso\\.\$',
      (m) => 'ऊपरी बांहें धड़ से ${m[1]} डिग्री के भीतर रखें।',
    ),
    (
      '^Keep your torso upright; lean stayed over $number degrees\\.\$',
      (m) => 'धड़ सीधा रखें; झुकाव ${m[1]} डिग्री से अधिक रहा।',
    ),
    (
      '^Keep your torso steady front to back; lean changed by more than $number degrees\\.\$',
      (m) =>
          'धड़ को आगे-पीछे स्थिर रखें; झुकाव में ${m[1]} डिग्री से अधिक बदलाव हुआ।',
    ),
    (
      '^Do not twist your torso; shoulder line turned more than $number degrees\\.\$',
      (m) => 'धड़ न घुमाएं; कंधों की रेखा ${m[1]} डिग्री से अधिक घूमी।',
    ),
    (
      '^Keep the wand level; it tilted more than $number degrees\\.\$',
      (m) => 'छड़ी समतल रखें; यह ${m[1]} डिग्री से अधिक झुकी।',
    ),
    (
      '^Move both arms together; they differed by more than $number degrees\\.\$',
      (m) =>
          'दोनों बांहें साथ हिलाएं; उनके कोणों में ${m[1]} डिग्री से अधिक अंतर था।',
    ),
    (
      '^(Left|Right) elbow did not hold at or below $number deg for 0\\.2s\\.\$',
      (m) =>
          '${m[1] == 'Left' ? 'बाईं' : 'दाईं'} कोहनी ${m[2]} डिग्री या उससे कम पर 0.2 सेकंड नहीं रुकी।',
    ),
    (
      '^(Left|Right) elbow range was below $number deg\\.\$',
      (m) =>
          '${m[1] == 'Left' ? 'बाईं' : 'दाईं'} कोहनी की गति की सीमा ${m[2]} डिग्री से कम थी।',
    ),
    (
      '^(Left|Right) elbow must return to at least $number deg and within $number deg of its start, held 0\\.2s\\.\$',
      (m) =>
          '${m[1] == 'Left' ? 'बाईं' : 'दाईं'} कोहनी कम से कम ${m[2]} डिग्री और शुरुआती कोण से ${m[3]} डिग्री के भीतर वापस लाएं और 0.2 सेकंड रुकें।',
    ),
    (
      '^Arm angle difference exceeded $number deg\\.\$',
      (m) => 'बांहों के कोणों का अंतर ${m[1]} डिग्री से अधिक था।',
    ),
    (
      '^Arm range difference exceeded $number deg\\.\$',
      (m) => 'बांहों की गति की सीमाओं का अंतर ${m[1]} डिग्री से अधिक था।',
    ),
  ];
  for (final (pattern, translate) in patterns) {
    final match = RegExp(pattern).firstMatch(text);
    if (match != null) return translate(match);
  }
  return null;
}
