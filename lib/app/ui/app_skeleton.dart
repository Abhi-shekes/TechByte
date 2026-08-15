import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// A placeholder block that pulses between two surface tones.
///
/// Replaces six bare centred spinners. Each of those threw away layout the app
/// already knew — the feed card, the tile grid and the question list all have a
/// known shape — then jumped when content landed. Below the ~400ms Doherty
/// threshold a skeleton reads as instant; a spinner reads as waiting.
///
/// Tone-pulse rather than a sweeping shimmer: a gradient travelling across a
/// dark ground is a lot of movement for something that means "nothing has
/// happened yet". Honours reduced motion by holding still.
class AppSkeleton extends StatefulWidget {
  const AppSkeleton({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = Radii.smAll,
  });

  final double width;
  final double height;
  final BorderRadius borderRadius;

  @override
  State<AppSkeleton> createState() => _AppSkeletonState();
}

class _AppSkeletonState extends State<AppSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MotionScope.of(context)) {
      _controller.stop();
      _controller.value = 0.5;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Color.lerp(
              scheme.surfaceContainer,
              scheme.surface,
              _controller.value,
            ),
            borderRadius: widget.borderRadius,
          ),
        );
      },
    );
  }
}

/// Skeleton shaped like the feed's question card.
class FeedCardSkeleton extends StatelessWidget {
  const FeedCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.gutterReading),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: Space.md),
            const AppSkeleton(width: 120, height: 12),
            const SizedBox(height: Space.xxxl),
            const AppSkeleton(width: double.infinity, height: 30),
            const SizedBox(height: Space.md),
            const AppSkeleton(width: double.infinity, height: 30),
            const SizedBox(height: Space.md),
            const AppSkeleton(width: 200, height: 30),
            const Spacer(),
            AppSkeleton(
              width: double.infinity,
              height: Sizes.buttonLg,
              borderRadius: Radii.lgAll,
            ),
            const SizedBox(height: Space.xxxl),
          ],
        ),
      ),
    );
  }
}

/// Skeleton shaped like a list of question tiles.
class QuestionListSkeleton extends StatelessWidget {
  const QuestionListSkeleton({super.key, this.count = 6});

  final int count;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: Space.pagePadding,
      itemCount: count,
      itemBuilder: (context, index) => const Padding(
        padding: EdgeInsets.only(bottom: Space.md),
        child: AppSkeleton(
          width: double.infinity,
          height: 92,
          borderRadius: Radii.xlAll,
        ),
      ),
    );
  }
}

/// Skeleton shaped like the Explore category grid.
class TileGridSkeleton extends StatelessWidget {
  const TileGridSkeleton({super.key, this.count = 8});

  final int count;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: Space.pagePadding,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: Space.md,
        crossAxisSpacing: Space.md,
        childAspectRatio: 1.35,
      ),
      itemCount: count,
      itemBuilder: (context, index) => const AppSkeleton(
        width: double.infinity,
        height: double.infinity,
        borderRadius: Radii.xlAll,
      ),
    );
  }
}
