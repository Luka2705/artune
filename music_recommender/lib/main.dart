import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';
import 'widgets/discovery_animation.dart';
import 'widgets/song_card.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const MyApp());

const accent = Color(0xFFE83E65);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => const CupertinoApp(
        title: 'Artune',
        debugShowCheckedModeBanner: false,
        theme: CupertinoThemeData(primaryColor: accent),
        home: MusicRecommenderPage(),
      );
}

class MusicRecommenderPage extends StatefulWidget {
  const MusicRecommenderPage({super.key});

  @override
  State<MusicRecommenderPage> createState() => _MusicRecommenderPageState();
}

class _MusicRecommenderPageState extends State<MusicRecommenderPage>
    with WidgetsBindingObserver {
  final ScrollController _scroll = ScrollController();
  AudioPlayer? _player;
  final List<StreamSubscription<dynamic>> _audioSubscriptions = [];
  String? _activeTrack;
  String? _audioError;
  bool _playing = false;
  bool _audioBusy = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  File? _image;
  String _provider = 'claude';
  String _resultProvider = 'claude';
  String _server = const String.fromEnvironment('API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8001');
  double _popularity = 50;
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _songs = [];
  final http.Client _client = http.Client();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _server = prefs.getString('server') ?? _server;
      _provider = prefs.getString('provider') == 'ollama' ? 'ollama' : 'claude';
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server', _server);
    await prefs.setString('provider', _provider);
  }

  Uri _uri(String path) => Uri.parse('$_server$path');

  Future<String?> _checkServer() async {
    try {
      final response = await _client
          .get(_uri('/health'))
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) {
        return 'Unter $_server läuft kein aktueller Artune-Server. Starte api_server.py neu oder ändere die Adresse in den Einstellungen.';
      }
      final data = jsonDecode(response.body);
      if (data is! Map || data['service'] != 'artune') {
        return 'Unter dieser Adresse antwortet eine andere Anwendung. Bitte den Artune-Port 8001 verwenden.';
      }
      return null;
    } on TimeoutException {
      return 'Der Server antwortet nicht. Prüfe die Adresse und ob dein Backend läuft.';
    } on FormatException {
      return 'Diese Adresse gehört nicht zum Artune-Backend.';
    } catch (_) {
      return 'Keine Verbindung zu $_server. Starte das Backend. Auf einem echten iPhone brauchst du die WLAN-Adresse deines Macs statt 127.0.0.1.';
    }
  }

  Future<void> _pickImage() async {
    try {
      final image = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 1568,
          maxHeight: 1568,
          imageQuality: 85);
      if (image == null || !mounted) return;
      await _stopPreview();
      if (!mounted) return;
      HapticFeedback.selectionClick();
      setState(() {
        _image = File(image.path);
        _songs = [];
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Das Foto konnte nicht geöffnet werden. Bitte den Fotozugriff in den iPhone-Einstellungen prüfen.');
      }
    }
  }

  Future<void> _recommend() async {
    if (_image == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _songs = [];
    });
    if (_scroll.hasClients) {
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic);
    }
    try {
      await _stopPreview();
      final connectionError = await _checkServer();
      if (connectionError != null) throw _AppError(connectionError);
      final request = http.MultipartRequest('POST', _uri('/predict/'));
      request.fields.addAll({
        'target_popularity': _popularity.round().toString(),
        'provider': _provider
      });
      request.files
          .add(await http.MultipartFile.fromPath('image', _image!.path));
      final response = await (() async {
        final streamed = await _client.send(request);
        return http.Response.fromStream(streamed);
      })()
          .timeout(Duration(seconds: _provider == 'ollama' ? 250 : 200));
      if (response.statusCode != 200) {
        throw _AppError(
            'Der Server meldet HTTP ${response.statusCode}. Prüfe die Backend-Logs und die Serveradresse.');
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map) throw const FormatException();
      if (data['message'] != 'Success') {
        throw _AppError(
            data['message']?.toString() ?? 'Keine Empfehlungen erhalten.');
      }
      final songs = (data['recommendations'] as List)
          .map((song) => Map<String, dynamic>.from(song as Map))
          .toList();
      if (songs.isEmpty) {
        throw const _AppError(
            'Keine Songs gefunden. Versuche ein anderes Foto.');
      }
      if (!mounted) return;
      HapticFeedback.lightImpact();
      setState(() {
        _songs = songs;
        _resultProvider = _provider;
      });
    } on _AppError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on TimeoutException {
      if (mounted) {
        setState(() => _error =
            'Die Analyse dauert zu lange. Versuche es erneut oder wechsle den Anbieter.');
      }
    } on FormatException {
      if (mounted) {
        setState(() => _error =
            'Die Serverantwort ist ungültig. Bitte das Artune-Backend aktualisieren und neu starten.');
      }
    } catch (error) {
      debugPrint('Artune request failed: ${error.runtimeType}');
      if (mounted) {
        setState(() => _error =
            'Die Verbindung wurde unterbrochen. Prüfe das Backend und versuche es erneut.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopPreview() async {
    try {
      await _player?.stop();
    } catch (_) {/* A failed preview must not block a new search. */}
    if (mounted) {
      setState(() {
        _playing = false;
        _activeTrack = null;
        _position = Duration.zero;
        _duration = Duration.zero;
        _audioError = null;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _stopPreview();
    }
  }

  Future<void> _togglePreview(Map<String, dynamic> song) async {
    if (_audioBusy) return;
    final id = song['spotify_id'] as String;
    final url = song['preview_url'] as String?;
    if (url == null) return;
    setState(() {
      _audioBusy = true;
      _audioError = null;
    });
    try {
      if (_player == null) {
        _player = AudioPlayer();
        _audioSubscriptions.add(_player!.onPositionChanged.listen((value) {
          if (mounted) setState(() => _position = value);
        }));
        _audioSubscriptions.add(_player!.onDurationChanged.listen((value) {
          if (mounted) setState(() => _duration = value);
        }));
        _audioSubscriptions.add(_player!.onPlayerStateChanged.listen((value) {
          if (mounted) setState(() => _playing = value == PlayerState.playing);
        }));
        _audioSubscriptions.add(_player!.onPlayerComplete.listen((_) {
          if (mounted) {
            setState(() {
              _playing = false;
              _position = Duration.zero;
            });
          }
        }));
      }
      if (_activeTrack == id && _playing) {
        await _player!.pause();
      } else if (_activeTrack == id && _position > Duration.zero) {
        await _player!.resume();
      } else {
        await _player!.stop();
        if (!mounted) return;
        setState(() {
          _activeTrack = id;
          _position = Duration.zero;
          _duration = Duration.zero;
        });
        await _player!.play(UrlSource(url));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _activeTrack = id;
          _audioError = 'Hörprobe nicht abspielbar. Öffne den Song in Spotify.';
          _playing = false;
        });
      }
    } finally {
      if (mounted) setState(() => _audioBusy = false);
    }
  }

  Future<void> _openSpotify(Map<String, dynamic> song) async {
    await _stopPreview();
    try {
      final uri = Uri.parse(song['spotify_url'] as String);
      if (uri.scheme != 'https' || uri.host != 'open.spotify.com') {
        throw const FormatException();
      }
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw const FormatException();
      }
    } catch (_) {
      if (!mounted) return;
      showCupertinoDialog<void>(
          context: context,
          builder: (context) => CupertinoAlertDialog(
                  title: const Text('Spotify konnte nicht geöffnet werden'),
                  content: const Text(
                      'Bitte prüfe deine Verbindung und ob Spotify installiert ist.'),
                  actions: [
                    CupertinoDialogAction(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('OK'))
                  ]));
    }
  }

  Future<void> _settings() async {
    final controller = TextEditingController(text: _server);
    String? status;
    bool checking = false;
    await showCupertinoModalPopup<void>(
        context: context,
        builder: (sheetContext) => StatefulBuilder(
            builder: (context, update) => CupertinoPopupSurface(
                  child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(24, 20, 24,
                            24 + MediaQuery.viewInsetsOf(context).bottom),
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Verbindung',
                                        style: TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold)),
                                    CupertinoButton(
                                        padding: EdgeInsets.zero,
                                        onPressed: () =>
                                            Navigator.pop(sheetContext),
                                        child: const Text('Fertig')),
                                  ]),
                              const SizedBox(height: 12),
                              CupertinoTextField(
                                  controller: controller,
                                  placeholder: 'http://192.168.1.10:8001',
                                  keyboardType: TextInputType.url,
                                  autocorrect: false,
                                  padding: const EdgeInsets.all(14)),
                              const SizedBox(height: 12),
                              const Text(
                                  'Simulator: 127.0.0.1:8001\nEchtes iPhone: WLAN-Adresse deines Macs, Port 8001.',
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: CupertinoColors.secondaryLabel)),
                              if (status != null)
                                Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Text(status!,
                                        style: const TextStyle(fontSize: 14))),
                              const SizedBox(height: 20),
                              CupertinoButton.filled(
                                  onPressed: checking
                                      ? null
                                      : () async {
                                          final value = controller.text
                                              .trim()
                                              .replaceAll(RegExp(r'/+$'), '');
                                          final uri = Uri.tryParse(value);
                                          if (uri == null ||
                                              !['http', 'https']
                                                  .contains(uri.scheme) ||
                                              uri.host.isEmpty ||
                                              (uri.path.isNotEmpty &&
                                                  uri.path != '/') ||
                                              uri.hasQuery ||
                                              uri.hasFragment ||
                                              uri.userInfo.isNotEmpty) {
                                            update(() => status =
                                                'Bitte eine Serveradresse ohne Pfad eingeben.');
                                            return;
                                          }
                                          setState(() => _server = value);
                                          await _saveSettings();
                                          if (!context.mounted) return;
                                          update(() {
                                            checking = true;
                                            status = null;
                                          });
                                          final error = await _checkServer();
                                          if (!context.mounted) return;
                                          update(() {
                                            checking = false;
                                            status = error ??
                                                'Verbunden. Artune ist bereit.';
                                          });
                                        },
                                  child: checking
                                      ? const CupertinoActivityIndicator()
                                      : const Text(
                                          'Speichern & Verbindung prüfen')),
                            ]),
                      )),
                )));
    // The route can still be animating out here; its controller is route-scoped.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final subscription in _audioSubscriptions) {
      subscription.cancel();
    }
    _player?.dispose();
    _scroll.dispose();
    _client.close();
    super.dispose();
  }

  Widget _card(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: CupertinoColors.secondarySystemGroupedBackground
                .resolveFrom(context),
            borderRadius: BorderRadius.circular(24)),
        child: child,
      );

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
        backgroundColor: CupertinoColors.systemGroupedBackground,
        child: CustomScrollView(controller: _scroll, slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('Artune'),
            trailing: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _busy ? null : _settings,
                child:
                    const Icon(CupertinoIcons.slider_horizontal_3, size: 25)),
          ),
          SliverSafeArea(
              top: false,
              sliver: SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  sliver: SliverList(
                      delegate: SliverChildListDelegate([
                    const Text('Dein Moment. Dein Soundtrack.',
                        style: TextStyle(
                            fontSize: 18,
                            color: CupertinoColors.secondaryLabel)),
                    const SizedBox(height: 24),
                    Semantics(
                        button: true,
                        label: 'Foto auswählen oder wechseln',
                        child: GestureDetector(
                            onTap: _busy ? null : _pickImage,
                            child: Container(
                              height: 290,
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(28),
                                  gradient: const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFF341C40),
                                        Color(0xFF9F4262),
                                        Color(0xFFEDAB91)
                                      ])),
                              child: _busy
                                  ? DiscoveryAnimation(image: _image)
                                  : Stack(fit: StackFit.expand, children: [
                                      if (_image != null)
                                        Image.file(_image!, fit: BoxFit.cover),
                                      if (_image == null)
                                        const Center(
                                            child: Icon(CupertinoIcons.waveform,
                                                color: Color(0x66FFFFFF),
                                                size: 120)),
                                      const DecoratedBox(
                                          decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                  begin: Alignment.topCenter,
                                                  end: Alignment.bottomCenter,
                                                  colors: [
                                            Color(0x00000000),
                                            Color(0xA6000000)
                                          ]))),
                                      Positioned(
                                          left: 24,
                                          right: 24,
                                          bottom: 24,
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                    _image == null
                                                        ? 'Musik beginnt\nmit einem Bild.'
                                                        : 'Ein Bild. Tausend Klänge.',
                                                    style: const TextStyle(
                                                        color: CupertinoColors
                                                            .white,
                                                        fontSize: 28,
                                                        height: 1.1,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        letterSpacing: -0.7)),
                                                const SizedBox(height: 14),
                                                Row(children: [
                                                  const Icon(
                                                      CupertinoIcons.photo,
                                                      size: 18,
                                                      color: CupertinoColors
                                                          .white),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                      _image == null
                                                          ? 'Foto auswählen'
                                                          : 'Foto wechseln',
                                                      style: const TextStyle(
                                                          color: CupertinoColors
                                                              .white,
                                                          fontWeight:
                                                              FontWeight.w600))
                                                ]),
                                              ])),
                                    ]),
                            ))),
                    const SizedBox(height: 20),
                    _card(Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('Deine Auswahl',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.4)),
                          const SizedBox(height: 18),
                          CupertinoSlidingSegmentedControl<String>(
                              groupValue: _provider,
                              children: const {
                                'claude': Padding(
                                    padding: EdgeInsets.symmetric(
                                        vertical: 10, horizontal: 14),
                                    child: Text('Claude')),
                                'ollama': Padding(
                                    padding: EdgeInsets.symmetric(
                                        vertical: 10, horizontal: 14),
                                    child: Text('Ollama')),
                              },
                              onValueChanged: (value) {
                                if (_busy || value == null) return;
                                HapticFeedback.selectionClick();
                                setState(() {
                                  _provider = value;
                                  _error = null;
                                });
                                _saveSettings();
                              }),
                          const SizedBox(height: 12),
                          Text(
                              _provider == 'claude'
                                  ? 'Analyse mit Claude. Dein Foto wird an Anthropic gesendet.'
                                  : 'Analyse mit deinem Ollama-Server. Ein Vision-Modell muss installiert sein.',
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: CupertinoColors.secondaryLabel,
                                  height: 1.4)),
                          const SizedBox(height: 24),
                          const Text('Was möchtest du entdecken?',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600)),
                          CupertinoSlider(
                              value: _popularity,
                              min: 0,
                              max: 100,
                              onChanged: _busy
                                  ? null
                                  : (value) =>
                                      setState(() => _popularity = value)),
                          const Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Geheimtipps',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: CupertinoColors.secondaryLabel)),
                                Text('Lieblingshits',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: CupertinoColors.secondaryLabel))
                              ]),
                        ])),
                    const SizedBox(height: 20),
                    CupertinoButton.filled(
                        borderRadius: BorderRadius.circular(18),
                        onPressed: _busy || _image == null ? null : _recommend,
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_busy)
                                const Icon(CupertinoIcons.waveform, size: 20)
                              else
                                const Icon(CupertinoIcons.sparkles, size: 20),
                              const SizedBox(width: 10),
                              Text(
                                  _busy
                                      ? 'Dein Soundtrack entsteht …'
                                      : 'Soundtrack entdecken',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                            ])),
                    if (_image == null)
                      const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                              'Wähle zuerst einen Moment aus deiner Mediathek.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: CupertinoColors.secondaryLabel))),
                    if (_error != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: _card(Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(children: [
                                  Icon(CupertinoIcons.exclamationmark_circle,
                                      color: accent, size: 20),
                                  SizedBox(width: 8),
                                  Text('Das hat noch nicht geklappt',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16))
                                ]),
                                const SizedBox(height: 10),
                                Text(_error!,
                                    style: const TextStyle(
                                        fontSize: 15, height: 1.4)),
                                CupertinoButton(
                                    padding: const EdgeInsets.only(top: 12),
                                    onPressed: _settings,
                                    child: const Text('Verbindung prüfen')),
                              ]))),
                    if (_songs.isNotEmpty) ...[
                      const SizedBox(height: 32),
                      const Text('Für diesen Moment',
                          style: TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.6)),
                      const SizedBox(height: 6),
                      Text(
                          'Auf Spotify gefunden · ${_resultProvider == 'claude' ? 'Claude' : 'Ollama'}',
                          style: const TextStyle(
                              color: CupertinoColors.secondaryLabel,
                              fontSize: 14)),
                      const SizedBox(height: 16),
                      ..._songs.indexed.map((entry) {
                        final selected = _activeTrack == entry.$2['spotify_id'];
                        return Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: SongCard(
                              song: entry.$2,
                              index: entry.$1,
                              playing: selected && _playing,
                              loading: selected && _audioBusy,
                              progress: selected && _duration.inMilliseconds > 0
                                  ? _position.inMilliseconds /
                                      _duration.inMilliseconds
                                  : 0,
                              error: selected ? _audioError : null,
                              onPreview: _audioBusy
                                  ? null
                                  : () => _togglePreview(entry.$2),
                              onSpotify: () => _openSpotify(entry.$2),
                            ));
                      }),
                    ],
                  ])))),
        ]),
      );
}

class _AppError implements Exception {
  const _AppError(this.message);
  final String message;
}
