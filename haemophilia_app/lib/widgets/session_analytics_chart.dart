import 'app_text.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../screens/patient/patient_history.dart';
import '../utils/app_localizations.dart';

enum AnalyticsMetric {
  score('Movement Score', 'Average Movement Score', 'pts', true),
  rom('Range of Motion', 'Average Range of Motion', '°', false),
  correctRate('Correct Rep Rate', 'Correct Rep Rate', '%', true),
  duration('Duration', 'Average Duration', 's', false),
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
  int? _selectedSessionIndex;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

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
      case AnalyticsMetric.confidence:
        return session.averageConfidence.clamp(0.0, 100.0);
    }
  }

  String _formatDateTime(DateTime dt) {
    final d = dt.toLocal();
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    final hour = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '$day/$month/${d.year} at $hour:$min';
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    if (widget.sessions.isEmpty) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('Session Progress Trends'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                tr('Session-level averages across completed sessions'),
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 25),
              Center(
                child: Column(
                  children: [
                    const Icon(Icons.insights_outlined, size: 42, color: Colors.grey),
                    const SizedBox(height: 10),
                    Text(
                      tr('No assessment sessions yet'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tr('Complete assessment sessions to view progress trends.'),
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
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

    // Default selected to latest session if index out of bounds
    final selectedIdx = (_selectedSessionIndex != null &&
            _selectedSessionIndex! >= 0 &&
            _selectedSessionIndex! < chronologicalSessions.length)
        ? _selectedSessionIndex!
        : (chronologicalSessions.length - 1);

    final selectedSession = chronologicalSessions[selectedIdx];

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
                        tr(_selectedMetric.fullLabel),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        tr('Tap any session data point to inspect details'),
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: AppText(
                    '${chronologicalSessions.length} ${tr('Sessions')}',
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
                      label: Text(tr(metric.shortLabel)),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _selectedMetric = metric);
                        }
                      },
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.w800 : FontWeight.w600,
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
            const SizedBox(height: 16),

            // Responsive & Horizontally Scrollable Chart Canvas
            LayoutBuilder(
              builder: (context, constraints) {
                const double pointSpacing = 72.0;
                const double yAxisWidth = 44.0;
                final double availableCanvasWidth =
                    math.max(100.0, constraints.maxWidth - yAxisWidth);
                final double requiredCanvasWidth = math.max(
                  availableCanvasWidth,
                  chronologicalSessions.length * pointSpacing + 20.0,
                );

                // Compute Y-axis bounds
                double maxY;
                if (_selectedMetric.isPercentageOrScore) {
                  maxY = 100.0;
                } else if (_selectedMetric == AnalyticsMetric.rom) {
                  final maxVal = values.fold<double>(0.0, math.max);
                  maxY = maxVal > 150.0
                      ? 180.0
                      : maxVal > 100.0
                          ? 150.0
                          : 120.0;
                } else {
                  final maxVal = values.fold<double>(0.0, math.max);
                  maxY = math.max(10.0, ((maxVal + 2) / 5).ceil() * 5.0);
                }

                return SizedBox(
                  height: 220,
                  child: Row(
                    children: [
                      // Fixed Y-Axis column
                      SizedBox(
                        width: yAxisWidth,
                        height: 220,
                        child: CustomPaint(
                          painter: _YAxisPainter(
                            maxY: maxY,
                            unit: _selectedMetric.unit,
                          ),
                        ),
                      ),

                      // Horizontally scrollable plot area
                      Expanded(
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: GestureDetector(
                            onTapUp: (details) {
                              final dx = details.localPosition.dx;
                              final int count = chronologicalSessions.length;
                              if (count <= 1) {
                                setState(() => _selectedSessionIndex = 0);
                                return;
                              }
                              final step =
                                  (requiredCanvasWidth - 40.0) / (count - 1);
                              int closestIdx = 0;
                              double closestDist = double.infinity;
                              for (int i = 0; i < count; i++) {
                                final pointX = 20.0 + i * step;
                                final dist = (pointX - dx).abs();
                                if (dist < closestDist) {
                                  closestDist = dist;
                                  closestIdx = i;
                                }
                              }
                              if (closestDist <= 40.0) {
                                setState(
                                    () => _selectedSessionIndex = closestIdx);
                              }
                            },
                            child: SizedBox(
                              width: requiredCanvasWidth,
                              height: 220,
                              child: CustomPaint(
                                painter: _SessionChartPlotPainter(
                                  sessions: chronologicalSessions,
                                  values: values,
                                  metric: _selectedMetric,
                                  lineColor: primary,
                                  maxY: maxY,
                                  selectedIndex: selectedIdx,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // Interactive Point Details Card (Shows when a session is selected)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: primary.withValues(alpha: 0.15)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.touch_app_outlined,
                        size: 18, color: primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                selectedSession.sessionName.isNotEmpty
                                    ? selectedSession.sessionName
                                    : 'Session ${selectedIdx + 1}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatDateTime(selectedSession.date),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            _miniMetric(
                                tr('Score'),
                                '${selectedSession.averageScore.toStringAsFixed(0)}/100',
                                primary),
                            _miniMetric(tr('ROM'),
                                '${selectedSession.averageRom.toStringAsFixed(0)}°'),
                            _miniMetric(tr('Correct'),
                                '${selectedSession.correctReps}/${selectedSession.reps} (${selectedSession.correctRate.toStringAsFixed(0)}%)'),
                            _miniMetric(tr('AI Confidence'),
                                '${selectedSession.averageConfidence.toStringAsFixed(0)}%'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Summary Stats Strip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _SummaryItem(
                      label: tr('Latest Session'),
                      value:
                          '${latestValue.toStringAsFixed(1)}${_selectedMetric.unit}',
                      color: primary,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 24,
                    color: Colors.grey.shade300,
                  ),
                  Expanded(
                    child: _SummaryItem(
                      label: tr('Overall Average'),
                      value:
                          '${overallAverage.toStringAsFixed(1)}${_selectedMetric.unit}',
                      color: Colors.black87,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 24,
                    color: Colors.grey.shade300,
                  ),
                  Expanded(
                    child: _SummaryItem(
                      label: tr('Total Sessions'),
                      value: '${chronologicalSessions.length}',
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniMetric(String label, String value, [Color? color]) {
    return Text.rich(
      TextSpan(
        text: '$label: ',
        style: TextStyle(
          fontSize: 11,
          color: Colors.grey.shade700,
        ),
        children: [
          TextSpan(
            text: value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: color ?? Colors.black87,
            ),
          ),
        ],
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
    AppLocaleScope.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
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

/// Draws the stationary Y-axis scale and tick labels on the left
class _YAxisPainter extends CustomPainter {
  final double maxY;
  final String unit;

  _YAxisPainter({required this.maxY, required this.unit});

  @override
  void paint(Canvas canvas, Size size) {
    const topPadding = 18.0;
    const bottomPadding = 42.0;
    final chartHeight = size.height - topPadding - bottomPadding;

    final axisPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.35)
      ..strokeWidth = 1;

    final textStyle = TextStyle(
      color: Colors.grey.shade600,
      fontSize: 10,
    );

    // Vertical Y-axis line on the right edge of this box
    canvas.drawLine(
      Offset(size.width - 2, topPadding),
      Offset(size.width - 2, topPadding + chartHeight),
      axisPaint,
    );

    final yInterval = maxY / 4.0;
    for (int step = 0; step <= 4; step++) {
      final val = step * yInterval;
      final y = topPadding + chartHeight - (val / maxY) * chartHeight;

      final labelText = val % 1 == 0
          ? '${val.toInt()}$unit'
          : '${val.toStringAsFixed(1)}$unit';

      final textPainter = TextPainter(
        text: TextSpan(text: labelText, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(size.width - textPainter.width - 6, y - textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _YAxisPainter oldDelegate) {
    return oldDelegate.maxY != maxY || oldDelegate.unit != unit;
  }
}

/// Draws the scrollable session points, connectors, and X-axis labels
class _SessionChartPlotPainter extends CustomPainter {
  final List<AssessmentSession> sessions;
  final List<double> values;
  final AnalyticsMetric metric;
  final Color lineColor;
  final double maxY;
  final int selectedIndex;

  _SessionChartPlotPainter({
    required this.sessions,
    required this.values,
    required this.metric,
    required this.lineColor,
    required this.maxY,
    required this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    const topPadding = 18.0;
    const bottomPadding = 42.0;
    const horizontalMargin = 24.0;

    final chartHeight = size.height - topPadding - bottomPadding;
    final plotWidth = size.width - horizontalMargin * 2;

    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.12)
      ..strokeWidth = 1;

    final axisPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.35)
      ..strokeWidth = 1;

    // Horizontal baseline
    canvas.drawLine(
      Offset(0, topPadding + chartHeight),
      Offset(size.width, topPadding + chartHeight),
      axisPaint,
    );

    // 4 horizontal gridlines across the plot
    final yInterval = maxY / 4.0;
    for (int step = 1; step <= 4; step++) {
      final val = step * yInterval;
      final y = topPadding + chartHeight - (val / maxY) * chartHeight;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }

    final points = <Offset>[];
    final count = values.length;

    for (int i = 0; i < count; i++) {
      final val = values[i].clamp(0.0, maxY);
      final double x;
      if (count == 1) {
        x = size.width / 2;
      } else {
        x = horizontalMargin + (i / (count - 1)) * plotWidth;
      }
      final y = topPadding + chartHeight - (val / maxY) * chartHeight;
      points.add(Offset(x, y));
    }

    // Connect discrete session points with a dashed/clear stroke if multiple points
    if (points.length > 1) {
      final connectorPaint = Paint()
        ..color = lineColor.withValues(alpha: 0.45)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;

      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(path, connectorPaint);
    }

    final pointPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;

    final pointWhitePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Draw individual session markers and X labels
    for (int i = 0; i < points.length; i++) {
      final pt = points[i];
      final val = values[i];
      final session = sessions[i];
      final isSelected = (i == selectedIndex);

      // Selected halo ring
      if (isSelected) {
        final haloPaint = Paint()
          ..color = lineColor.withValues(alpha: 0.20)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(pt, 12, haloPaint);

        final haloBorder = Paint()
          ..color = lineColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawCircle(pt, 12, haloBorder);
      }

      // Point circle
      canvas.drawCircle(pt, isSelected ? 7 : 5.5, pointPaint);
      canvas.drawCircle(pt, isSelected ? 3.5 : 2.5, pointWhitePaint);

      // Value label above dot
      final valString = val % 1 == 0
          ? val.toStringAsFixed(0)
          : val.toStringAsFixed(1);
      final valPainter = TextPainter(
        text: TextSpan(
          text: '$valString${metric.unit}',
          style: TextStyle(
            color: isSelected ? lineColor : Colors.grey.shade800,
            fontSize: isSelected ? 11 : 9.5,
            fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      valPainter.paint(
        canvas,
        Offset(pt.dx - valPainter.width / 2, pt.dy - valPainter.height - 6),
      );

      // X-axis session date & time label (real session timestamps, no fake S1/S2/S3)
      final dt = session.date.toLocal();
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      final monthStr =
          (dt.month >= 1 && dt.month <= 12) ? months[dt.month - 1] : '';
      final timeStr =
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      final dateLabel = '${dt.day} $monthStr\n$timeStr';

      final xPainter = TextPainter(
        text: TextSpan(
          text: dateLabel,
          style: TextStyle(
            color: isSelected ? lineColor : Colors.grey.shade700,
            fontSize: 9.0,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
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
  bool shouldRepaint(covariant _SessionChartPlotPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.metric != metric ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.sessions != sessions ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.maxY != maxY;
  }
}
