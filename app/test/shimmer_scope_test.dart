import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_heritage_music/widgets/skeleton_loader.dart';

Widget _wrap(Widget child, {bool disableAnimations = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(
        body: SizedBox(
          width: 400,
          height: 800,
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('SkeletonList 12 ô chỉ tạo đúng 1 controller shimmer dùng chung', (tester) async {
    await tester.pumpWidget(_wrap(const SkeletonList(itemCount: 12, itemHeight: 56)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.binding.transientCallbackCount, 1);
    expect(find.byType(ShimmerScope), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Skeleton rời rạc không có scope: mỗi ô 1 controller (hành vi cũ giữ nguyên)', (tester) async {
    await tester.pumpWidget(_wrap(
      Column(
        children: [
          for (var i = 0; i < 3; i++)
            const SkeletonLoader(height: 56, margin: EdgeInsets.zero),
        ],
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.binding.transientCallbackCount, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Re-parent skeleton giữa ngoài-scope và trong-scope không văng, callback đúng 1', (tester) async {
    final key = GlobalKey(debugLabel: 'sk');
    Widget host(bool scoped) {
      final loader = SkeletonLoader(key: key, height: 56, margin: EdgeInsets.zero);
      return _wrap(scoped ? ShimmerScope(child: loader) : loader);
    }

    await tester.pumpWidget(host(false));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.binding.transientCallbackCount, 1);
    await tester.pumpWidget(host(true));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.binding.transientCallbackCount, 1);
    await tester.pumpWidget(host(false));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.binding.transientCallbackCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reduced motion: skeleton tĩnh, 0 controller chạy', (tester) async {
    await tester.pumpWidget(_wrap(
      const SkeletonList(itemCount: 6, itemHeight: 56),
      disableAnimations: true,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
