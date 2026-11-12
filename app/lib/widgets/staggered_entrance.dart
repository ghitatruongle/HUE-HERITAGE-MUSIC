import 'package:flutter/material.dart';

class StaggeredEntrance extends StatefulWidget {
  final int index;
  final int maxAnimatedIndex;
  final Widget child;

  const StaggeredEntrance({
    super.key,
    required this.index,
    this.maxAnimatedIndex = 9,
    required this.child,
  });

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final CurvedAnimation _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    final animate = widget.index <= widget.maxAnimatedIndex;
    final begin = animate ? (widget.index * 0.08).clamp(0.0, 0.6) : 0.0;
    _fade = CurvedAnimation(
      parent: _ctrl,
      curve: Interval(begin, 1.0, curve: Curves.easeOut),
    );
    if (animate) {
      _ctrl.forward();
    } else {
      _ctrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.04),
        end: Offset.zero,
      ).animate(_fade),
      child: FadeTransition(
        opacity: _fade,
        child: widget.child,
      ),
    );
  }
}
