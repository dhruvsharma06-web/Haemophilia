import 'package:flutter/material.dart';

import '../utils/app_localizations.dart';

const screeningFields = <String, String>{
  'age': 'Age',
  'sex': 'Biological sex',
  'prolonged_bleeding_minor_cut': 'Bleeding after minor cuts',
  'excessive_post_surgery_bleeding': 'Bleeding after surgery or stitches',
  'excessive_dental_bleeding': 'Bleeding after dental procedures',
  'easy_bruising': 'Easy or unusual bruising',
  'muscle_hematoma': 'Unexplained muscle swelling or pain',
  'recurrent_joint_bleeding': 'Repeated joint swelling or bleeding',
  'joint_warmth': 'Warmth around the affected joint',
  'joint_tightness': 'Joint tightness or stiffness',
  'reduced_joint_mobility': 'Reduced joint mobility',
  'hematuria': 'Blood in urine',
  'hematochezia': 'Blood in stool',
  'family_history_bleeding_disorder': 'Family history of a bleeding disorder',
  'male_relative_with_hemophilia': 'Male relative diagnosed with haemophilia',
  'previous_factor_test': 'Previous clotting factor test',
};

class PatientScreeningCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const PatientScreeningCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    final answers = data['screeningAnswers'] is Map
        ? Map<String, dynamic>.from(data['screeningAnswers'])
        : <String, dynamic>{};
    final result = data['screeningResult'] is Map
        ? Map<String, dynamic>.from(data['screeningResult'])
        : <String, dynamic>{};
    final confidence = num.tryParse(
      result['predictionConfidence']?.toString() ?? '',
    );
    final diagnosis = data['diagnosisStatus']?.toString();
    final diagnosisLabel = diagnosis == 'yes'
        ? 'Yes, diagnosed'
        : diagnosis == 'no'
        ? 'No diagnosis'
        : diagnosis == 'unsure'
        ? 'Not sure'
        : 'Not available';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.fact_check_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr('Patient screening'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text('${tr('Diagnosis status')}: ${tr(diagnosisLabel)}'),
            const SizedBox(height: 8),
            if (result.isNotEmpty) ...[
              Text(
                '${tr('AI screening result')}: ${tr(result['predictionLabel']?.toString() ?? 'Not available')}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (confidence != null &&
                  confidence.isFinite &&
                  confidence >= 0 &&
                  confidence <= 1)
                Text(
                  '${tr('AI Confidence')}: ${(confidence * 100).toStringAsFixed(0)}%',
                ),
              const SizedBox(height: 8),
              Text(
                tr(
                  'This is an automated screening estimate, not a diagnosis. Review the reported symptoms and arrange appropriate clinical evaluation.',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tr(
                  'Recommended action: contact a doctor to review your screening answers and determine whether tests or further assessment are needed.',
                ),
              ),
            ] else
              Text(
                tr(
                  diagnosis == 'yes'
                      ? 'The patient reports an existing diagnosis. The screening questionnaire was not repeated.'
                      : 'The patient has not completed screening yet.',
                ),
              ),
            if (answers.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(tr('Screening answers')),
                children: [
                  for (final field in screeningFields.entries)
                    if (answers.containsKey(field.key))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(tr(field.value)),
                        subtitle: Text(tr(answers[field.key].toString())),
                      ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
