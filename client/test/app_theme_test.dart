import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexusroom/app/theme/app_colors.dart';
import 'package:nexusroom/app/theme/app_theme.dart';
import 'package:nexusroom/core/models/app_settings.dart';

void main() {
  test('stored color mode defaults safely to dark', () {
    expect(AppColorMode.fromStorage(null), AppColorMode.dark);
    expect(AppColorMode.fromStorage('unknown'), AppColorMode.dark);
    expect(AppColorMode.fromStorage('light'), AppColorMode.light);
  });

  test('dark theme uses a light foreground on black surfaces', () {
    final theme = AppTheme.forBrightness(Brightness.dark);
    final colors = theme.extension<NexusColors>()!;

    expect(theme.brightness, Brightness.dark);
    expect(colors.background.computeLuminance(), lessThan(0.02));
    expect(colors.textPrimary.computeLuminance(), greaterThan(0.8));
    expect(theme.colorScheme.onPrimary, const Color(0xFF111111));
  });

  test('light theme uses a dark foreground on white surfaces', () {
    final theme = AppTheme.forBrightness(Brightness.light);
    final colors = theme.extension<NexusColors>()!;

    expect(theme.brightness, Brightness.light);
    expect(colors.background.computeLuminance(), greaterThan(0.8));
    expect(colors.textPrimary.computeLuminance(), lessThan(0.02));
    expect(theme.colorScheme.onPrimary, Colors.white);
  });

  testWidgets('mounted components update all context color tokens',
      (tester) async {
    Widget build(Brightness brightness) => MaterialApp(
          theme: AppTheme.forBrightness(brightness),
          home: Builder(
            builder: (context) => ColoredBox(
              key: const ValueKey('surface'),
              color: context.colors.background,
            ),
          ),
        );

    await tester.pumpWidget(build(Brightness.dark));
    expect(
      tester.widget<ColoredBox>(find.byKey(const ValueKey('surface'))).color,
      NexusColors.dark.background,
    );

    await tester.pumpWidget(build(Brightness.light));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ColoredBox>(find.byKey(const ValueKey('surface'))).color,
      NexusColors.light.background,
    );
  });
}
