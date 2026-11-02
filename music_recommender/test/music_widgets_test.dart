import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_recommender/widgets/discovery_animation.dart';
import 'package:music_recommender/widgets/song_card.dart';

void main() {
  Map<String, dynamic> song({bool preview = false}) => {
        'song_name': 'Teardrop',
        'artist': 'Massive Attack',
        'reason': 'Passt zur Stimmung.',
        'preview_url': preview ? 'https://p.scdn.co/preview.mp3' : null,
      };
  Widget wrap(Widget child) => CupertinoApp(
      home: CupertinoPageScaffold(
          child: Center(child: SizedBox(width: 320, child: child))));

  testWidgets('A real Spotify track stays visible when no snippet is available',
      (tester) async {
    var opened = false;
    await tester.pumpWidget(wrap(SongCard(
        song: song(),
        index: 0,
        playing: false,
        loading: false,
        progress: 0,
        onPreview: () => fail('No preview expected'),
        onSpotify: () => opened = true)));
    expect(find.text('Teardrop'), findsOneWidget);
    expect(find.text('Keine Spotify-Hörprobe'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.play_circle_fill), findsNothing);
    await tester.tap(find.text('In Spotify öffnen'));
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Preview has play and pause states and an actionable error',
      (tester) async {
    var played = false;
    await tester.pumpWidget(wrap(SongCard(
        song: song(preview: true),
        index: 0,
        playing: false,
        loading: false,
        progress: .25,
        onPreview: () => played = true,
        onSpotify: () {})));
    await tester.tap(find.text('Hörprobe'));
    expect(played, isTrue);
    await tester.pumpWidget(wrap(SongCard(
        song: song(preview: true),
        index: 0,
        playing: true,
        loading: false,
        progress: .5,
        onPreview: () {},
        onSpotify: () {},
        error: 'Nicht abspielbar.')));
    expect(find.byIcon(CupertinoIcons.pause_circle_fill), findsOneWidget);
    expect(find.text('Nicht abspielbar.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Discovery animation renders and respects reduced motion',
      (tester) async {
    await tester.pumpWidget(wrap(const DiscoveryAnimation()));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Dein Moment wird Musik.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(wrap(const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: DiscoveryAnimation())));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
