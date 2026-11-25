import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class SkeletonLoader extends StatefulWidget {
  final double height;
  final double? width;
  final double radius;
  final EdgeInsetsGeometry? margin;

  const SkeletonLoader({
    super.key,
    required this.height,
    this.width,
    this.radius = 12,
    this.margin,
  });

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  AnimationController? _own;
  CurvedAnimation? _curved;
  Animation<double>? _opacity;
  AnimationController? _parentCtrl;

  void _syncAnimation(BuildContext context) {
    final shared = _ShimmerData.maybeOf(context);
    final AnimationController target;
    if (shared != null) {
      _own?.stop();
      target = shared.controller;
    } else {
      final ctrl = _own ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1100),
      );
      if (!ctrl.isAnimating) {
        ctrl.repeat(reverse: true);
      }
      target = ctrl;
    }
    if (!identical(target, _parentCtrl)) {
      _curved?.dispose();
      _parentCtrl = target;
      _curved = CurvedAnimation(parent: target, curve: Curves.easeInOut);
      _opacity = Tween<double>(begin: 0.35, end: 0.85).animate(_curved!);
    }
  }

  @override
  void dispose() {
    _curved?.dispose();
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (MediaQuery.disableAnimationsOf(context)) {
      _own?.stop();
      return Container(
        margin: widget.margin,
        width: widget.width,
        height: widget.height,
        child: Opacity(
          opacity: 0.6,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(widget.radius),
            ),
          ),
        ),
      );
    }
    _syncAnimation(context);
    return Container(
      margin: widget.margin,
      width: widget.width,
      height: widget.height,
      child: FadeTransition(
        opacity: _opacity!,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        ),
      ),
    );
  }
}

class ShimmerScope extends StatefulWidget {
  final Widget child;

  const ShimmerScope({super.key, required this.child});

  @override
  State<ShimmerScope> createState() => _ShimmerScopeState();
}

class _ShimmerScopeState extends State<ShimmerScope>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disabled = MediaQuery.disableAnimationsOf(context);
    if (disabled) {
      _ctrl?.stop();
    } else {
      _ctrl ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1100),
      )..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    if (ctrl == null) {
      return widget.child;
    }
    return _ShimmerData(
      controller: ctrl,
      child: widget.child,
    );
  }
}

class _ShimmerData extends InheritedWidget {
  final AnimationController controller;

  const _ShimmerData({required this.controller, required super.child});

  static _ShimmerData? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_ShimmerData>();
  }

  @override
  bool updateShouldNotify(_ShimmerData oldWidget) => false;
}

class SkeletonList extends StatelessWidget {
  final int itemCount;
  final double itemHeight;
  final EdgeInsetsGeometry padding;

  const SkeletonList({
    super.key,
    this.itemCount = 6,
    this.itemHeight = 64,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  @override
  Widget build(BuildContext context) {
    return ShimmerScope(
      child: ListView.builder(
        padding: padding,
        itemCount: itemCount,
        itemBuilder: (context, i) => SkeletonLoader(
          height: itemHeight,
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
        ),
      ),
    );
  }
}
