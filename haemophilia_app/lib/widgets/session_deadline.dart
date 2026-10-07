import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/app_localizations.dart';

class SessionDeadline extends StatefulWidget {
  final DateTime deadline;
  final VoidCallback? onExpired;
  const SessionDeadline({super.key, required this.deadline, this.onExpired});
  @override
  State<SessionDeadline> createState() => _SessionDeadlineState();
}

class _SessionDeadlineState extends State<SessionDeadline> {
  Timer? _timer;
  bool _notified = false;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!_notified && !DateTime.now().isBefore(widget.deadline)) {
        _notified = true;
        widget.onExpired?.call();
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    final remaining = widget.deadline.difference(DateTime.now());
    final seconds = remaining.inSeconds.clamp(0, 3600);
    final time =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        seconds == 0
            ? tr('Session expired')
            : '${tr('Time remaining')}: $time · ${tr('Expires at')} ${TimeOfDay.fromDateTime(widget.deadline).format(context)}',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: seconds < 300
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
