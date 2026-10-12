import 'package:flutter/material.dart';

class ContentMaxWidth extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ContentMaxWidth({
    super.key,
    required this.child,
    this.maxWidth = 1360,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final content = ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        );
        if (constraints.maxWidth > maxWidth) {
          return Center(child: content);
        }
        return content;
      },
    );
  }
}
