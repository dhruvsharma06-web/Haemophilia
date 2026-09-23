import 'package:flutter/material.dart';
import '../../utils/exercise_utils.dart';
import 'exercise_demo_model.dart';

/// Reusable exercise demonstration widget that renders an animated visual guide
/// for an exercise. Supports both a compact looping preview and a full interactive viewer.
class ExerciseDemo extends StatefulWidget {
  final String exerciseId;
  final bool compact;
  final bool autoPlay;
  final bool isDark;
  final double? height;
  final double? width;

  const ExerciseDemo({
    super.key,
    required this.exerciseId,
    this.compact = false,
    this.autoPlay = true,
    this.isDark = true,
    this.height,
    this.width,
  });

  @override
  State<ExerciseDemo> createState() => _ExerciseDemoState();
}

class _ExerciseDemoState extends State<ExerciseDemo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late ExerciseDemoConfig _config;

  double _playbackSpeed = 1.0;

  @override
  void initState() {
    super.initState();
    _config = ExerciseDemoRegistry.get(widget.exerciseId);

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5500),
    );

    _controller.addListener(() {
      if (mounted) setState(() {});
    });

    if (widget.autoPlay) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant ExerciseDemo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.exerciseId != widget.exerciseId) {
      _config = ExerciseDemoRegistry.get(widget.exerciseId);
      _controller.reset();
      if (widget.autoPlay) _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_controller.isAnimating) {
      _controller.stop();
    } else {
      _controller.repeat();
    }
  }

  void _replay() {
    _controller.reset();
    _controller.repeat();
  }

  void _toggleSpeed() {
    setState(() {
      _playbackSpeed = _playbackSpeed == 1.0 ? 0.5 : 1.0;
      final baseDuration = 5500;
      _controller.duration = Duration(
        milliseconds: (baseDuration / _playbackSpeed).round(),
      );
      if (_controller.isAnimating) {
        _controller.repeat();
      }
    });
  }

  void _jumpToPhase(ExercisePhase phase) {
    _controller.animateTo(
      phase.startProgress,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) {
      return _buildCompactView();
    }
    return _buildFullView();
  }

  // ============================================================
  // COMPACT VIEW (Looping thumbnail/preview)
  // ============================================================

  Widget _buildCompactView() {
    final height = widget.height ?? 90.0;
    final width = widget.width ?? 110.0;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: widget.isDark
            ? const Color(0xFF0F172A)
            : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.grey.shade300,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: _config.painterBuilder(
          _controller.value,
          isDark: widget.isDark,
        ),
      ),
    );
  }

  // ============================================================
  // FULL INTERACTIVE VIEW
  // ============================================================

  Widget _buildFullView() {
    final activePhase = _config.getPhaseForProgress(_controller.value);
    final canvasHeight = widget.height ?? 240.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Canvas Card with Phase Pill & WIP Badge
        Container(
          height: canvasHeight,
          decoration: BoxDecoration(
            color: widget.isDark
                ? const Color(0xFF0F172A)
                : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: widget.isDark
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.grey.shade300,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // Custom Painter Canvas
              Positioned.fill(
                child: CustomPaint(
                  painter: _config.painterBuilder(
                    _controller.value,
                    isDark: widget.isDark,
                  ),
                ),
              ),

              // Active Phase Chip (Top Left)
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: (widget.isDark ? Colors.black : Colors.white)
                        .withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Color(0xFF38BDF8),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Step ${activePhase.phaseNumber}: ${activePhase.title}',
                        style: TextStyle(
                          color: widget.isDark ? Colors.white : Colors.black87,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // WIP Badge (Top Right, if applicable)
              if (_config.isWorkInProgress)
                Positioned(
                  top: 12,
                  right: 12,
                  child: buildWipBadge(isDark: widget.isDark, compact: true),
                ),

              // Playback Scrub Progress Bar (Bottom of canvas)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  value: _controller.value,
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF38BDF8),
                  ),
                  minHeight: 3,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // 2. Interactive Playback Controls
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                IconButton.filledTonal(
                  onPressed: _togglePlayPause,
                  icon: Icon(
                    _controller.isAnimating
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 22,
                  ),
                  tooltip: _controller.isAnimating ? 'Pause' : 'Play',
                ),
                const SizedBox(width: 6),
                IconButton.outlined(
                  onPressed: _replay,
                  icon: const Icon(Icons.replay_rounded, size: 20),
                  tooltip: 'Replay from start',
                ),
                const SizedBox(width: 6),
                TextButton(
                  onPressed: _toggleSpeed,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  child: Text(
                    '${_playbackSpeed}x',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
            // Looping indicator
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.loop_rounded,
                  size: 14,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(width: 4),
                Text(
                  'Auto-looping',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),

        const SizedBox(height: 10),

        // 3. Step Phase Pills (Clickable to jump)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _config.phases.map((phase) {
              final isCurrent = phase.phaseNumber == activePhase.phaseNumber;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: InkWell(
                  onTap: () => _jumpToPhase(phase),
                  borderRadius: BorderRadius.circular(16),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? const Color(0xFF0284C7)
                          : (widget.isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.grey.shade100),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isCurrent
                            ? const Color(0xFF38BDF8)
                            : Colors.transparent,
                      ),
                    ),
                    child: Text(
                      '${phase.phaseNumber}. ${phase.title}',
                      style: TextStyle(
                        color: isCurrent
                            ? Colors.white
                            : (widget.isDark ? Colors.white70 : Colors.black87),
                        fontSize: 11.5,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 12),

        // 4. Current Phase Description Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: (widget.isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFF1F5F9))
                .withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF0284C7).withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: Color(0xFF0284C7),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activePhase.title,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      activePhase.description,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: widget.isDark
                            ? Colors.grey.shade300
                            : Colors.grey.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
