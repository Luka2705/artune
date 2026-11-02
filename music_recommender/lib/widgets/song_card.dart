import 'package:flutter/cupertino.dart';

class SongCard extends StatelessWidget {
  const SongCard(
      {super.key,
      required this.song,
      required this.index,
      required this.playing,
      required this.loading,
      required this.progress,
      required this.onPreview,
      required this.onSpotify,
      this.error});
  final Map<String, dynamic> song;
  final int index;
  final bool playing, loading;
  final double progress;
  final VoidCallback? onPreview;
  final VoidCallback onSpotify;
  final String? error;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFE83E65);
    final artwork = song['artwork_url'] as String?;
    final hasPreview = song['preview_url'] is String &&
        (song['preview_url'] as String).isNotEmpty;
    Widget placeholder() => Container(
        color: accent.withValues(alpha: .1),
        child: const Center(
            child: Icon(CupertinoIcons.music_note, color: accent, size: 32)));
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: CupertinoColors.secondarySystemGroupedBackground
              .resolveFrom(context),
          borderRadius: BorderRadius.circular(24)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                  width: 72,
                  height: 72,
                  child: artwork == null
                      ? placeholder()
                      : Image.network(artwork,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => placeholder()))),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('${index + 1}  ·  SPOTIFY',
                    style: const TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.3,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.secondaryLabel)),
                const SizedBox(height: 5),
                Text(song['song_name'] as String,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.3)),
                const SizedBox(height: 4),
                Text(song['artist'] as String,
                    style: const TextStyle(
                        fontSize: 14, color: CupertinoColors.secondaryLabel)),
              ])),
        ]),
        const SizedBox(height: 14),
        Text(song['reason'] as String,
            style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                color: CupertinoColors.secondaryLabel)),
        const SizedBox(height: 16),
        if (hasPreview) ...[
          ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                  height: 3,
                  child: LayoutBuilder(
                      builder: (context, box) => Stack(children: [
                            Container(
                                color: CupertinoColors.systemFill
                                    .resolveFrom(context)),
                            Container(
                                width: box.maxWidth * progress.clamp(0, 1),
                                color: accent)
                          ])))),
          const SizedBox(height: 10),
        ],
        Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              if (hasPreview)
                CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: onPreview,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (loading)
                        const CupertinoActivityIndicator()
                      else
                        Icon(
                            playing
                                ? CupertinoIcons.pause_circle_fill
                                : CupertinoIcons.play_circle_fill,
                            size: 30),
                      const SizedBox(width: 7),
                      Text(playing ? 'Pause' : 'Hörprobe',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                    ]))
              else
                const Text('Keine Spotify-Hörprobe',
                    style: TextStyle(
                        fontSize: 12, color: CupertinoColors.secondaryLabel)),
              CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: onSpotify,
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('In Spotify öffnen',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    SizedBox(width: 5),
                    Icon(CupertinoIcons.arrow_up_right, size: 14)
                  ])),
            ]),
        if (error != null)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(error!,
                  style: const TextStyle(
                      color: CupertinoColors.systemRed, fontSize: 13))),
      ]),
    );
  }
}
