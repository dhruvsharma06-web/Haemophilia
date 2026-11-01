import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/local_test_config.dart';
import '../services/auth_service.dart';
import '../utils/app_localizations.dart';

class DoctorDocuments extends StatefulWidget {
  final String userId;
  final Map<String, dynamic> data;
  final bool editable;
  const DoctorDocuments({
    super.key,
    required this.userId,
    required this.data,
    this.editable = false,
  });
  @override
  State<DoctorDocuments> createState() => _DoctorDocumentsState();
}

class _DoctorDocumentsState extends State<DoctorDocuments> {
  bool _busy = false;
  Future<void> _open(String path) async {
    setState(() => _busy = true);
    try {
      // Resolve only the applicant's storage path after authenticated review.
      if (!path.startsWith('doctor_documents/${widget.userId}/')) {
        throw StateError('Invalid document path.');
      }
      final url = await LocalTestConfig.storage.ref(path).getDownloadURL();
      if (!await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        throw StateError('Could not open document.');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('Could not open document. Please try again.')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload(String key) async {
    setState(() => _busy = true);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      );
      if (files.isEmpty) return;
      final file = files.first;
      if (await file.length() >= 10 * 1024 * 1024) { throw StateError('Document too large.'); }
      await AuthService().uploadDoctorDocuments(widget.userId, {
        key: (file.name, await file.readAsBytes()),
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr('Document uploaded.'))));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                'Could not upload document. Use a PDF, JPG or PNG smaller than 10 MB.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final entry in {
        'registrationCert': 'Registration certificate',
        'professionalId': 'Professional ID',
      }.entries) ...[
        Text(tr(entry.value)),
        if (widget.data['${entry.key}Path'] is String)
          TextButton.icon(
            onPressed: _busy
                ? null
                : () => _open(widget.data['${entry.key}Path'] as String),
            icon: const Icon(Icons.description_outlined),
            label: Text(
              widget.data['${entry.key}Name']?.toString() ??
                  tr('View document'),
            ),
          )
        else
          Text(
            tr('Document not uploaded.'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (widget.editable)
          TextButton.icon(
            onPressed: _busy ? null : () => _upload(entry.key),
            icon: const Icon(Icons.upload_file),
            label: Text(tr('Upload document')),
          ),
      ],
      if (_busy) const LinearProgressIndicator(),
    ],
  );
}
