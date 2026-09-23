import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../screens/patient/patient_history.dart';

enum AnalyticsMetric {
  score('Movement Score', 'Average Movement Score', 'pts', true),
  rom('Range of Motion', 'Average Range of Motion', '°', false),
  correctRate('Correct Rep Rate', 'Correct Rep Rate', '%', true),
  duration('Duration', 'Average Duration', 's', false),
  smoothness('Smoothness', 'Average Smoothness', '%', true),
  confidence('Confidence', 'Average AI Confidence', '%', true);

  final String shortLabel;
  final String fullLabel;
  final String unit;
  final bool isPercentageOrScore;

  const AnalyticsMetric(
    this.shortLabel,
    this.fullLabel,
    this.unit,
    this.isPercentageOrScore,
  );
}

class SessionAnalyticsChart extends StatefulWidget {
  final List<AssessmentSession> sessions;
  final bool isDoctorView;

  const SessionAnalyticsChart({
    super.key,
    required this.sessions,
    this.isDoctorView = false,
  });

  @override
  State<SessionAnalyticsChart> createState() => _SessionAnalyticsChartState();
}

class _SessionAnalyticsChartState extends State<SessionAnalyticsChart> {
  AnalyticsMetric _selectedMetric = AnalyticsMetric.score;

  double _getMetricValue(AssessmentSession session, AnalyticsMetric metric) {
    switch (metric) {
      case AnalyticsMetric.score:
        return session.averageScore.clamp(0.0, 100.0);
      case AnalyticsMetric.rom:
        return session.averageRom.clamp(0.0, 360.0);
      case AnalyticsMetric.correctRate:
        return session.correctRate.clamp(0.0, 100.0);
      case AnalyticsMetric.duration:
        return session.averageDuration.clamp(0.0, 300.0);
      case AnalyticsMetric.smoothness:
        return session.averageSmoothness.clamp(0.0, 100.0);
      case AnalyticsMetric.confidence:
        return session.averageConfidence.clamp(0.0, 100.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    if (widget.sessions.isEmpty) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Session Progress Trends',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 6),
              Text(
                'Session-level averages across completed sessions',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              SizedBox(height: 25),
              Center(
                child: Column(
                  children: [
                    Icon(Icons.insights_outlined, size: 42, color: Colors.grey),
                    SizedBox(height: 10),
                    Text(
                      'No session data yet',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Complete assessment sessions to view progress trends.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Sort chronologically: oldest (Session 1) on the left, newest on the right
    final chronologicalSessions = List<AssessmentSession>.from(widget.sessions)
      ..sort((a, b) => a.date.compareTo(b.date));

    final availableMetrics = widget.isDoctorView
        ? AnalyticsMetric.values
        : [
            AnalyticsMetric.score,
            AnalyticsMetric.rom,
            AnalyticsMetric.correctRate,
          ];

    final values = chronologicalSessions
        .map((s) => _getMetricValue(s, _selectedMetric))
        .toList();

    final overallAverage = values.isNotEmpty
        ? values.reduce((a, b) => a + b) / values.length
        : 0.0;

    final latestValue = values.isNotEmpty ? values.last : 0.0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedMetric.fullLabel,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Session-level averages across completed sessions',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${chronologicalSessions.length} sessions',
                    style: TextStyle(
                      color: primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Metric Selector Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: availableMetrics.map((metric) {
                  final isSelected = _selectedMetric == metric;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(metric.shortLabel),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _selectedMetric = metric);
                        }
                      },
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: isSelected ? Colors.white : Colors.black87,
                      ),
                      selectedColor: primary,
                      backgroundColor: Colors.grey.shade100,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      side: BorderSide.none,
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 18),

            // Chart Canvas
            SizedBox(
              height: 230,
              width: double.infinity,
              child: CustomPaint(
                painter: _SessionChartPainter(
                  sessions: chronologicalSessions,
                  values: values,
                  metric: _selectedMetric,
                  lineColor: primary,
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Summary Stats Strip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _SummaryItem(
                    label: 'Latest Session',
                    value:
                        '${latestValue.toStringAsFixed(1)}${_selectedMetric.unit}',
                    color: primary,
                  ),
                  Container(
                    width: 1,
                    height: 24,
                    color: Colors.grey.shade300,
                  ),
                  _SummaryItem(
                    label: 'Overall Average',
                    value:
                        '${overallAverage.toStringAsFixed(1)}${_selectedMetric.unit}',
                    color: Colors.black87,
                  ),
                  Container(
                    width: 1,
                    height: 24,
                    color: Colors.grey.shade300,
                  ),
                  _SummaryItem(
                    label: 'Sessions Logged',
                    value: '${chronologicalSessions.length}',
                    color: Colors.black87,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryItem({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _SessionChartPainter extends CustomPainter {
  final List<AssessmentSession> sessions;
  final List<double> values;
  final AnalyticsMetric metric;
  final Color lineColor;

  _SessionChartPainter({
    required this.sessions,
    required this.values,
    required this.metric,
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    const leftPadding = 42.0;
    const rightPadding = 18.0;
    const topPadding = 18.0;
    const bottomPadding = 32.0;

    final chartWidth = size.width - leftPadding - rightPadding;
    final chartHeight = size.height - topPadding - bottomPadding;

    // Calculate Y-axis bounds
    double maxY;
    if (metric.isPercentageOrScore) {
      maxY = 100.0;
    } else if (metric == AnalyticsMetric.rom) {
      final maxVal = values.fold<double>(0.0, math.max);
      maxY = maxVal > 150.0 ? 180.0 : maxVal > 100.0 ? 150.0 : 120.0;
    } else {
      // Duration
      final maxVal = values.fold<double>(0.0, math.max);
      maxY = math.max(10.0, ((maxVal + 2) / 5).ceil() * 5.0);
    }

    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.16)
      ..strokeWidth = 1;

    final axisPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.35)
      ..strokeWidth = 1;

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final pointPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;

    final pointWhitePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final textStyle = TextStyle(
      color: Colors.grey.shade600,
      fontSize: 10,
    );

    // Draw horizontal grid lines & Y labels (4 intervals)
    final yInterval = maxY / 4.0;
    for (int step = 0; step <= 4; step++) {
      final val = step * yInterval;
      final y = topPadding + chartHeight - (val / maxY) * chartHeight;

      canvas.drawLine(
        Offset(leftPadding, y),
        Offset(size.width - rightPadding, y),
        gridPaint,
      );

      final labelText = val % 1 == 0
          ? '${val.toInt()}${metric.unit}'
          : '${val.toStringAsFixed(1)}${metric.unit}';

      final textPainter = TextPainter(
        text: TextSpan(text: labelText, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(leftPadding - textPainter.width - 6, y - textPainter.height / 2),
      );
    }

    // Axes lines
    canvas.drawLine(
      Offset(leftPadding, topPadding),
      Offset(leftPadding, topPadding + chartHeight),
      axisPaint,
    );
    canvas.drawLine(
      Offset(leftPadding, topPadding + chartHeight),
      Offset(size.width - rightPadding, topPadding + chartHeight),
      axisPaint,
    );

    // Build data line path
    final path = Path();
    final points = <Offset>[];

    for (int i = 0; i < values.length; i++) {
      final val = values[i].clamp(0.0, maxY);
      final x = values.length == 1
          ? leftPadding + chartWidth / 2
          : leftPadding + (i / (values.length - 1)) * chartWidth;
      final y = topPadding + chartHeight - (val / maxY) * chartHeight;
      points.add(Offset(x, y));

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, linePaint);

    // Draw data points, values, and X-axis session labels
    for (int i = 0; i < points.length; i++) {
      final pt = points[i];
      final val = values[i];
      final session = sessions[i];

      // Draw point dot
      canvas.drawCircle(pt, 6, pointPaint);
      canvas.drawCircle(pt, 3, pointWhitePaint);

      // Value label above dot
      final valString = val % 1 == 0
          ? val.toStringAsFixed(0)
          : val.toStringAsFixed(1);
      final valPainter = TextPainter(
        text: TextSpan(
          text: '$valString${metric.unit}',
          style: TextStyle(
            color: lineColor,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      valPainter.paint(
        canvas,
        Offset(pt.dx - valPainter.width / 2, pt.dy - valPainter.height - 7),
      );

      // X-axis session label below axis
      final sessionLabel = 'S${i + 1}';
      final dateLabel = '${session.date.day}/${session.date.month}';

      final xPainter = TextPainter(
        text: TextSpan(
          text: '$sessionLabel\n$dateLabel',
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: 9,
            fontWeight: FontWeight.w600,
            height: 1.15,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();

      xPainter.paint(
        canvas,
        Offset(pt.dx - xPainter.width / 2, topPadding + chartHeight + 4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SessionChartPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.metric != metric ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.sessions != sessions;
  }
}
