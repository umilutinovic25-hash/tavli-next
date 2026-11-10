// Asset exporter: renderuje postojeći TavliBrand vektorski na macOS veličinama.
// Pokretanje: flutter test tools/export_app_icon.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavli/app/tavli_brand.dart';
import 'package:tavli/app/theme/app_theme.dart';
import 'package:tavli/domain/theme_choice.dart';

void main() {
  testWidgets('izvoz postojećeg Tavli znaka za macOS', (tester) async {
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    tester.view.physicalSize = const Size.square(1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const key = ValueKey('app-icon-export');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Theme(
          data: buildTavliTheme(TavliTheme.bosiljak, Brightness.light),
          child: const RepaintBoundary(
            key: key,
            child: SizedBox.square(
              dimension: 1024,
              child: Padding(
                padding: EdgeInsets.all(96),
                child: FittedBox(child: TavliBrand(compact: true)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(key),
    );
    await tester.runAsync(() async {
      for (final size in [16, 32, 64, 128, 256, 512, 1024]) {
        final image = await boundary.toImage(pixelRatio: size / 1024);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        await File(
          'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$size.png',
        ).writeAsBytes(png!.buffer.asUint8List());
      }
    });
  });
}
