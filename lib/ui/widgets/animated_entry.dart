import 'package:flutter/material.dart';

/// A reusable animated entry widget that fades in and slides up.
/// Inspired by the fitness app reference UI's entry animations.
///
/// Usage:
/// ```dart
/// AnimatedEntry(
///   delay: Duration(milliseconds: 100),
///   child: MyWidget(),
/// )
/// ```
class AnimatedEntry extends StatefulWidget {
  const AnimatedEntry({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 600),
    this.offset = 30.0,
    this.curve = Curves.fastOutSlowIn,
  });

  /// The child widget to animate.
  final Widget child;

  /// Delay before the animation starts.
  final Duration delay;

  /// Duration of the animation.
  final Duration duration;

  /// Vertical offset (pixels) to slide from.
  final double offset;

  /// Animation curve.
  final Curve curve;

  @override
  State<AnimatedEntry> createState() => _AnimatedEntryState();
}

class _AnimatedEntryState extends State<AnimatedEntry>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _animation = Tween<double>(begin: widget.offset, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );

    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: Transform.translate(
            offset: Offset(0, _animation.value),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// A staggered grid entry animation that animates children one by one.
class StaggeredAnimatedList extends StatelessWidget {
  const StaggeredAnimatedList({
    super.key,
    required this.children,
    this.staggerDelay = const Duration(milliseconds: 80),
    this.entryDuration = const Duration(milliseconds: 500),
    this.offset = 30.0,
  });

  final List<Widget> children;
  final Duration staggerDelay;
  final Duration entryDuration;
  final double offset;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < children.length; i++)
          AnimatedEntry(
            delay: Duration(milliseconds: staggerDelay.inMilliseconds * i),
            duration: entryDuration,
            offset: offset,
            child: children[i],
          ),
      ],
    );
  }
}

/// Scale-in animation for FABs and buttons.
class ScaleAnimatedEntry extends StatefulWidget {
  const ScaleAnimatedEntry({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 400),
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  @override
  State<ScaleAnimatedEntry> createState() => _ScaleAnimatedEntryState();
}

class _ScaleAnimatedEntryState extends State<ScaleAnimatedEntry>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.fastOutSlowIn),
    );

    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: widget.child,
    );
  }
}
