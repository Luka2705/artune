import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_recommender/main.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Provider selection persists and upload is required',
      (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    expect(find.text('Artune'), findsWidgets);
    await tester.ensureVisible(find.text('Ollama'));
    await tester.tap(find.text('Ollama'));
    await tester.pumpAndSettle();
    expect((await SharedPreferences.getInstance()).getString('provider'),
        'ollama');
    expect(find.textContaining('Ein Vision-Modell muss installiert sein.'),
        findsOneWidget);
    await tester.ensureVisible(find.text('Soundtrack entdecken'));
    final button = tester.widget<CupertinoButton>(find
        .ancestor(
            of: find.text('Soundtrack entdecken'),
            matching: find.byType(CupertinoButton))
        .first);
    expect(button.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Settings reject malformed server addresses', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(CupertinoIcons.slider_horizontal_3));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField), 'not-a-url');
    await tester.tap(find.text('Speichern & Verbindung prüfen'));
    await tester.pumpAndSettle();
    expect(find.text('Bitte eine Serveradresse ohne Pfad eingeben.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
