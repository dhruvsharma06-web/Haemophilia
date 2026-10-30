import 'package:flutter/material.dart';

import '../utils/app_localizations.dart';

Future<bool> confirmSessionSafety(BuildContext context) async {
  var noBleeding = false;
  var consent = false;
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(tr('Before you start')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tr(
                      'If you are bleeding or suspect bleeding, do not start. Stop immediately if bleeding occurs during exercise and contact your treating doctor before proceeding.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    tr(
                      'Camera frames are sent for AI movement assessment. AI feedback can be incorrect and is not a medical diagnosis. Follow your clinician’s instructions and stop if you feel unwell.',
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: noBleeding,
                    onChanged: (v) => setState(() => noBleeding = v ?? false),
                    title: Text(
                      tr('I am not bleeding and do not suspect bleeding.'),
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: consent,
                    onChanged: (v) => setState(() => consent = v ?? false),
                    title: Text(
                      tr(
                        'I consent to camera processing for this session and understand the AI limitations.',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr('Cancel')),
              ),
              FilledButton(
                onPressed: noBleeding && consent
                    ? () => Navigator.pop(context, true)
                    : null,
                child: Text(tr('Start session')),
              ),
            ],
          ),
        ),
      ) ??
      false;
}
