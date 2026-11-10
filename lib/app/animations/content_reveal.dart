import 'package:flutter/material.dart';

import 'motion.dart';

/// Kratak ulazak sadržaja uz postojeći sistem Reduce Motion.
class ContentReveal extends StatelessWidget {
  const ContentReveal({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => MotionBuilder(
    repeat: false,
    duration: TavliMotion.reveal,
    builder: (context, t, still) {
      final progress = Curves.easeOutCubic.transform(t);
      return Opacity(
        opacity: progress,
        alwaysIncludeSemantics: true,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - progress)),
          child: child,
        ),
      );
    },
  );
}
