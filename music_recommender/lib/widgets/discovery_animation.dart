import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';

/// A decorative record and equalizer. No simulated completion percentage.
class DiscoveryAnimation extends StatefulWidget {
  const DiscoveryAnimation({super.key, this.image});
  final File? image;
  @override
  State<DiscoveryAnimation> createState() => _DiscoveryAnimationState();
}

class _DiscoveryAnimationState extends State<DiscoveryAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion =
      AnimationController(vsync: this, duration: const Duration(seconds: 8));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.stop();
    } else {
      _motion.repeat();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label:
            'Dein Bild wird analysiert und passende Songs werden auf Spotify gesucht.',
        liveRegion: true,
        child: ExcludeSemantics(
            child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Container(
            height: 260,
            decoration: const BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                  Color(0xFF201828),
                  Color(0xFF4D2443),
                  Color(0xFF251B35)
                ])),
            child: AnimatedBuilder(
                animation: _motion,
                builder: (context, _) {
                  final t = _motion.value * math.pi * 2;
                  return Stack(alignment: Alignment.center, children: [
                    Positioned(
                        top: -60 + 15 * math.sin(t),
                        right: -20 + 25 * math.cos(t),
                        child: Container(
                            width: 200,
                            height: 200,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(colors: [
                                  const Color(0xFFE83E65).withValues(alpha: .4),
                                  const Color(0x00E83E65)
                                ])))),
                    Positioned(
                        left: -50,
                        bottom: -80,
                        child: Container(
                            width: 240,
                            height: 240,
                            decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(colors: [
                                  Color(0x555D5CE2),
                                  Color(0x005D5CE2)
                                ])))),
                    Positioned(
                        top: 24,
                        child: Transform.rotate(
                            angle: t,
                            child: Container(
                              width: 112,
                              height: 112,
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFF17151C),
                                  border: Border.all(
                                      color: const Color(0x33FFFFFF)),
                                  boxShadow: const [
                                    BoxShadow(
                                        color: Color(0x55200018),
                                        blurRadius: 25,
                                        offset: Offset(0, 12))
                                  ]),
                              child:
                                  Stack(alignment: Alignment.center, children: [
                                for (final size in [96.0, 84.0, 72.0])
                                  Container(
                                      width: size,
                                      height: size,
                                      decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: const Color(0x16FFFFFF)))),
                                ClipOval(
                                    child: widget.image == null
                                        ? Container(
                                            width: 50,
                                            height: 50,
                                            color: const Color(0xFFE83E65),
                                            child: const Icon(
                                                CupertinoIcons.music_note,
                                                color: CupertinoColors.white))
                                        : Image.file(widget.image!,
                                            width: 50,
                                            height: 50,
                                            fit: BoxFit.cover)),
                                Container(
                                    width: 7,
                                    height: 7,
                                    decoration: const BoxDecoration(
                                        color: Color(0xFF17151C),
                                        shape: BoxShape.circle)),
                              ]),
                            ))),
                    Positioned(
                        top: 155,
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: List.generate(19, (i) {
                              final wave = (math.sin(t * 4 + i * .65) + 1) / 2;
                              final envelope = 1 - (i - 9).abs() / 12;
                              return Container(
                                  width: 4,
                                  height: 5 + 25 * wave * envelope,
                                  margin:
                                      const EdgeInsets.symmetric(horizontal: 2),
                                  decoration: BoxDecoration(
                                      color: Color.lerp(const Color(0xFFFFB6C9),
                                          const Color(0xFFE83E65), i / 19),
                                      borderRadius: BorderRadius.circular(3)));
                            }))),
                    const Positioned(
                        bottom: 44,
                        child: Text('Dein Moment wird Musik.',
                            style: TextStyle(
                                color: CupertinoColors.white,
                                fontSize: 19,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -.3))),
                    const Positioned(
                        bottom: 22,
                        child: Text('Bildanalyse & Spotify-Suche',
                            style: TextStyle(
                                color: Color(0xBBFFFFFF), fontSize: 13))),
                  ]);
                }),
          ),
        )),
      );
}
