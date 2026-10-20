import 'package:flutter/material.dart';

/// A soft, sweeping shimmer used to build skeleton placeholders.
///
/// The app has no shimmer dependency and does not need one: the effect is a
/// moving highlight painted over a flat placeholder, which is a
/// [ShaderMask] over a repeating [AnimationController].
///
/// The highlight sweeps diagonally across the child, so a stack of shimmering
/// blocks reads as one continuous light passing over the whole skeleton
/// rather than as several independently blinking boxes.
class Shimmer extends StatefulWidget {
  final Widget child;

  /// The resting colour of the placeholder.
  final Color? baseColor;

  /// The colour the highlight sweeps in as.
  final Color? highlightColor;

  /// How long one full sweep takes.
  final Duration duration;

  const Shimmer({
    super.key,
    required this.child,
    this.baseColor,
    this.highlightColor,
    this.duration = const Duration(milliseconds: 1400),
  });

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // In light mode the base is a soft grey and the highlight is near-white,
    // so the block pulses between "empty slot" and "almost filled". In dark
    // mode both are white at low alpha.
    final base = widget.baseColor ??
        (dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.09));
    final highlight = widget.highlightColor ??
        (dark ? Colors.white.withValues(alpha: 0.20) : Colors.white.withValues(alpha: 0.85));

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) {
          // Slide the gradient from fully off the left edge to fully off the
          // right edge over the life of the animation.
          final travel = _controller.value * 3 - 1.5;
          return LinearGradient(
            begin: Alignment(travel - 1, 0),
            end: Alignment(travel + 1, 0),
            colors: [base, highlight, base],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(bounds);
        },
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// A single shimmering block — the building unit of every skeleton.
///
/// [width] and [height] may be null for "fill the space you are given",
/// which is what lets a skeleton row grow with the text next to it.
class ShimmerBox extends StatelessWidget {
  final double? width;
  final double? height;
  final double borderRadius;
  final Color? baseColor;
  final Color? highlightColor;

  const ShimmerBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 6,
    this.baseColor,
    this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}
