import '../../widgets/app_text.dart';
import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../utils/app_localizations.dart';

/// Post-login screening using the existing 15-question, 16-feature model.
/// Results are informational and are saved only after the patient continues.
class HealthScreeningScreen extends StatefulWidget {
  final Future<void> Function(Map<String, dynamic>, Map<String, dynamic>)? onComplete;
  const HealthScreeningScreen({super.key, this.onComplete});

  @override
  State<HealthScreeningScreen> createState() => _HealthScreeningScreenState();
}

class _HealthScreeningScreenState extends State<HealthScreeningScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _ageController = TextEditingController();

  int _currentStep = 0;
  final Set<String> _answered = {};
  bool _isLoading = false;
  bool _savingResult = false;
  String? _errorMessage;
  Map<String, dynamic>? _screeningResult;

  // Answers model matching Physio-Project's exact feature set
  final Map<String, dynamic> _answers = {
    'age': 25,
    'sex': 'male',
    'prolonged_bleeding_minor_cut': 'never',
    'excessive_post_surgery_bleeding': 'no',
    'excessive_dental_bleeding': 'no',
    'easy_bruising': 'never',
    'muscle_hematoma': 'no',
    'recurrent_joint_bleeding': 'no',
    'joint_warmth': 'no',
    'joint_tightness': 'no',
    'reduced_joint_mobility': 'no',
    'hematuria': 'no',
    'hematochezia': 'no',
    'family_history_bleeding_disorder': 'no',
    'male_relative_with_hemophilia': 'no',
    'previous_factor_test': 'no',
  };

  final List<_ScreeningQuestion> _questions = [
    _ScreeningQuestion(
      key: 'demographics',
      titleEn: 'Your Age and Biological Sex',
      titleHi: 'आपकी आयु और जैविक लिंग',
      type: _QuestionType.demographics,
    ),
    _ScreeningQuestion(
      key: 'prolonged_bleeding_minor_cut',
      titleEn: 'Do you bleed longer than others after minor cuts?',
      titleHi:
          'क्या छोटे कट लगने पर आपको दूसरों की तुलना में अधिक समय तक रक्तस्राव होता है?',
      type: _QuestionType.frequency,
    ),
    _ScreeningQuestion(
      key: 'excessive_post_surgery_bleeding',
      titleEn:
          'Have you experienced excessive bleeding after surgery or stitches?',
      titleHi:
          'क्या आपको सर्जरी या टांके लगने के बाद अत्यधिक रक्तस्राव हुआ है?',
      type: _QuestionType.binary,
    ),
    _ScreeningQuestion(
      key: 'excessive_dental_bleeding',
      titleEn:
          'Have you experienced excessive bleeding after dental procedures?',
      titleHi:
          'क्या आपको दंत चिकित्सा प्रक्रियाओं के बाद अत्यधिक रक्तस्राव का अनुभव हुआ है?',
      type: _QuestionType.binary,
    ),
    _ScreeningQuestion(
      key: 'easy_bruising',
      titleEn: 'Do you develop large or unusual bruises easily?',
      titleHi: 'क्या आपको आसानी से बड़े या असामान्य नील पड़ जाते हैं?',
      type: _QuestionType.frequency,
    ),
    _ScreeningQuestion(
      key: 'muscle_hematoma',
      titleEn:
          'Have you experienced unexplained deep muscle swelling, pain, or tenderness?',
      titleHi:
          'क्या आपने बिना किसी बड़ी चोट के मांसपेशियों में सूजन, दर्द या कोमलता महसूस की है?',
      type: _QuestionType.binary,
    ),
    _ScreeningQuestion(
      key: 'recurrent_joint_bleeding',
      titleEn:
          'Have you experienced repeated joint swelling or bleeding episodes without major injury?',
      titleHi:
          'क्या आपको बिना किसी बड़ी चोट के जोड़ों में बार-बार सूजन या रक्तस्राव हुआ है?',
      type: _QuestionType.binary,
    ),
    _ScreeningQuestion(
      key: 'joint_warmth',
      titleEn:
          'During joint episodes, have you noticed warmth around the affected joint?',
      titleHi:
          'जोड़ों की समस्या के दौरान, क्या आपने प्रभावित जोड़ के आसपास गर्माहट महसूस की है?',
      type: _QuestionType.binary,
    ),
    _ScreeningQuestion(
      key: 'joint_tightness',
      titleEn:
          'During joint episodes, have you noticed tightness or stiffness in the joint?',
      titleHi: 'जोड़ों की समस्या के दौरान, क्या आपने जोड़ में जकड़न महसूस की है?',
      type: _QuestionType.binary,
    ),
    _ScreeningQuestion(
      key: 'reduced_joint_mobility',
      titleEn:
          'Have you experienced reduced mobility or difficulty moving the affected joint?',
      titleHi:
          'क्या आपको प्रभावित जोड़ को हिलाने-डुलाने में कठिनाई या गतिशीलता में कमी महसूस हुई है?',
      type: _QuestionType.binary,
    ),
    _ScreeningQuestion(
      key: 'hematuria',
      titleEn: 'Have you noticed blood in your urine (hematuria)?',
      titleHi: 'क्या आपने अपने मूत्र में रक्त (हेमट्यूरिया) देखा है?',
      type: _QuestionType.binary,
    ),
    _ScreeningQuestion(
      key: 'hematochezia',
      titleEn: 'Have you noticed blood in your stool (hematochezia)?',
      titleHi: 'क्या आपने अपने मल में रक्त देखा है?',
      type: _QuestionType.binary,
    ),
    _ScreeningQuestion(
      key: 'family_history_bleeding_disorder',
      titleEn:
          'Is there a known family history of hemophilia or bleeding disorders?',
      titleHi:
          'क्या आपके परिवार में हीमोफीलिया या रक्तस्राव विकारों का कोई इतिहास है?',
      type: _QuestionType.binary,
    ),
    _ScreeningQuestion(
      key: 'male_relative_with_hemophilia',
      titleEn: 'Do you have any male relatives diagnosed with hemophilia?',
      titleHi: 'क्या आपके किसी पुरुष रिश्तेदार को हीमोफीलिया का निदान हुआ है?',
      type: _QuestionType.binary,
    ),
    _ScreeningQuestion(
      key: 'previous_factor_test',
      titleEn: 'Have you ever had a previous clotting factor deficiency test?',
      titleHi: 'क्या आपने कभी पहले क्लॉटिंग फैक्टर की जाँच कराई है?',
      type: _QuestionType.binary,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _ageController.text = _answers['age'].toString();
  }

  @override
  void dispose() {
    _ageController.dispose();
    super.dispose();
  }

  Future<void> _submitScreening() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final payload = Map<String, dynamic>.from(_answers);
      payload['language'] = AppLocaleService.isHindi ? 'hi' : 'en';

      final res = await _apiService.predictHealthScreening(payload);
      if (mounted) {
        setState(() {
          _screeningResult = res;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _complete() async {
    if (_savingResult) return;
    setState(() => _savingResult = true);
    try {
      if (widget.onComplete != null) {
        await widget.onComplete!(Map<String, dynamic>.from(_answers), _screeningResult!);
      } else if (mounted) {
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Could not save. Please try again.'))));
    } finally { if (mounted) setState(() => _savingResult = false); }
  }

  void _nextStep() {
    FocusScope.of(context).unfocus();
    if (_currentStep == 0) {
      final parsedAge = int.tryParse(_ageController.text.trim());
      if (parsedAge == null || parsedAge < 1 || parsedAge > 120) {
        setState(()=>_errorMessage=tr('Please enter an age from 1 to 120.'));
        return;
      }
      _answers['age'] = parsedAge;
      if (!_answered.contains('sex')) {
        setState(()=>_errorMessage=tr('Please answer the question above before proceeding.'));
        return;
      }
    }
    _errorMessage=null;

    final question = _questions[_currentStep];
    if (question.type != _QuestionType.demographics && !_answered.contains(question.key)) {
      setState(()=>_errorMessage=tr('Please answer the question above before proceeding.'));
      return;
    }
    if (_currentStep < _questions.length - 1) {
      setState(() => _currentStep++);
    } else {
      _submitScreening();
    }
  }

  void _previousStep() {
    FocusScope.of(context).unfocus();
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  void _resetScreening() {
    setState(() {
      _currentStep = 0;
      _screeningResult = null;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr('Health Risk Screening'),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: const [
          LanguageToggleButton(),
          SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? _buildLoadingView()
            : _screeningResult != null
                ? _buildResultView(primary)
                : _buildQuestionFlow(primary),
      ),
    );
  }

  Widget _buildLoadingView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(strokeWidth: 3),
            const SizedBox(height: 20),
            Text(
              tr('Analyzing your responses...'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionFlow(Color primary) {
    final currentQ = _questions[_currentStep];
    final totalSteps = _questions.length;
    final progress = (_currentStep + 1) / totalSteps;

    return Column(
      children: [
        // Progress bar
        LinearProgressIndicator(
          value: progress,
          minHeight: 4,
          backgroundColor: primary.withValues(alpha: 0.12),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: AppText(
                  '${tr('Step')} ${_currentStep + 1} ${tr('of')} $totalSteps',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  tr('Screening Guidance'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.red.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],

                // Question card
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocaleService.isHindi
                              ? currentQ.titleHi
                              : currentQ.titleEn,
                          style: const TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 20),
                        _buildInputForQuestion(currentQ, primary),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Medical safety disclaimer
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.amber.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 20,
                        color: Colors.amber.shade900,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          tr('This screening is informational and does not replace a medical diagnosis.'),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.amber.shade900,
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Navigation bottom bar
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            children: [
              if (_currentStep > 0)
                Expanded(
                  child: OutlinedButton(
                    onPressed: _previousStep,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(tr('Previous')),
                  ),
                ),
              if (_currentStep > 0) const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _nextStep,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    _currentStep == totalSteps - 1
                        ? tr('Submit')
                        : tr('Next'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInputForQuestion(_ScreeningQuestion q, Color primary) {
    switch (q.type) {
      case _QuestionType.demographics:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('Your Age (years)'),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _ageController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: 'e.g. 25',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              tr('Your Biological Sex'),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildChoiceChip(
                    label: tr('Male'),
                    selected: _answered.contains('sex') && _answers['sex'] == 'male',
                    onTap: () => setState(() { _answers['sex'] = 'male'; _answered.add('sex'); _errorMessage=null; }),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildChoiceChip(
                    label: tr('Female'),
                    selected: _answered.contains('sex') && _answers['sex'] == 'female',
                    onTap: () => setState(() { _answers['sex'] = 'female'; _answered.add('sex'); _errorMessage=null; }),
                  ),
                ),
              ],
            ),
          ],
        );

      case _QuestionType.frequency:
        final currentVal = _answered.contains(q.key) ? _answers[q.key] : null;
        return Column(
          children: [
            _buildChoiceChip(
              label: tr('Never'),
              selected: currentVal == 'never',
              onTap: () => setState(() { _answers[q.key] = 'never'; _answered.add(q.key); _errorMessage=null; }),
            ),
            const SizedBox(height: 8),
            _buildChoiceChip(
              label: tr('Sometimes'),
              selected: currentVal == 'sometimes',
              onTap: () => setState(() { _answers[q.key] = 'sometimes'; _answered.add(q.key); _errorMessage=null; }),
            ),
            const SizedBox(height: 8),
            _buildChoiceChip(
              label: tr('Often'),
              selected: currentVal == 'often',
              onTap: () => setState(() { _answers[q.key] = 'often'; _answered.add(q.key); _errorMessage=null; }),
            ),
          ],
        );

      case _QuestionType.binary:
        final currentVal = _answered.contains(q.key) ? _answers[q.key] : null;
        return Row(
          children: [
            Expanded(
              child: _buildChoiceChip(
                label: tr('Yes'),
                selected: currentVal == 'yes',
                onTap: () => setState(() { _answers[q.key] = 'yes'; _answered.add(q.key); _errorMessage=null; }),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildChoiceChip(
                label: tr('No'),
                selected: currentVal == 'no',
                onTap: () => setState(() { _answers[q.key] = 'no'; _answered.add(q.key); _errorMessage=null; }),
              ),
            ),
          ],
        );
    }
  }

  Widget _buildChoiceChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final primary = Theme.of(context).colorScheme.primary;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: selected
              ? primary.withValues(alpha: 0.1)
              : Colors.grey.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? primary : Colors.grey.shade300,
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? primary : Colors.grey.shade800,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 4),
              Icon(Icons.check_circle_rounded, size: 16, color: primary),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultView(Color primary) {
    final result = _screeningResult!;
    final label = result['predictionLabel']?.toString() ?? 'Healthy';
    final displayLabel = result['displayLabel']?.toString() ?? label;
    final confidence = (result['predictionConfidence'] as num?)?.toDouble() ?? 0.0;
    final int confPercent = (confidence * 100).round();

    Color statusColor;
    switch (label.toLowerCase()) {
      case 'severe':
        statusColor = Colors.red.shade700;
        break;
      case 'moderate':
        statusColor = Colors.deepOrange.shade700;
        break;
      case 'mild':
        statusColor = Colors.orange.shade800;
        break;
      case 'healthy':
      default:
        statusColor = Colors.green.shade700;
        break;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Result Header Card
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: statusColor.withValues(alpha: 0.3)),
            ),
            color: statusColor.withValues(alpha: 0.06),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  Icon(
                    label.toLowerCase() == 'healthy'
                        ? Icons.verified_user_rounded
                        : Icons.health_and_safety_rounded,
                    size: 48,
                    color: statusColor,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    tr('Screening Result'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tr(displayLabel),
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: AppText(
                      '${tr('Screening Confidence')}: $confPercent%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 18),

          Text(
            tr('Based on your reported symptoms and health history, the automated screening model produced the following result:'),
            style: TextStyle(
              fontSize: 13.5,
              color: Colors.grey.shade700,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 18),

          // Medical safety & Next steps
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.medical_services_outlined,
                      size: 20,
                      color: Colors.blueAccent,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      tr('Medical Consultation Recommended'),
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.blueAccent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  tr('If you experience persistent, spontaneous, or severe bleeding, please consult a qualified hematologist or physician promptly.'),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.grey.shade800,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Disclaimer
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 20,
                  color: Colors.amber.shade900,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr('This screening is informational and does not replace a medical diagnosis.'),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.amber.shade900,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _resetScreening,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(tr('Restart Screening')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _savingResult ? null : _complete,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(tr('Continue to app')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _QuestionType { demographics, frequency, binary }

class _ScreeningQuestion {
  final String key;
  final String titleEn;
  final String titleHi;
  final _QuestionType type;

  const _ScreeningQuestion({
    required this.key,
    required this.titleEn,
    required this.titleHi,
    required this.type,
  });
}
