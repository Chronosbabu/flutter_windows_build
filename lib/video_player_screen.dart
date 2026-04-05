import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String url;
  final String name;

  VideoPlayerScreen({required this.url, required this.name});

  @override
  _VideoPlayerScreenState createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController controller;
  String? errorMessage;
  bool _showControls = true;
  bool _isFullScreen = false;
  Timer? _hideTimer;

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${twoDigits(duration.inMinutes)}:${twoDigits(duration.inSeconds.remainder(60))}";
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    _hideTimer?.cancel();
    if (_showControls && controller.value.isPlaying) _startHideTimer();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && controller.value.isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleFullScreen() async {
    if (_isFullScreen) {
      // === SORTIE DU MODE PAYSAGE ===
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) {
        setState(() => _isFullScreen = false);
      }
    } else {
      // === ENTRÉE EN MODE PAYSAGE ===
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) {
        setState(() => _isFullScreen = true);
      }
    }
  }

  void _seekForward() => controller.seekTo(controller.value.position + const Duration(seconds: 10));
  void _seekBackward() => controller.seekTo(controller.value.position - const Duration(seconds: 10));

  @override
  void initState() {
    super.initState();
    controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..addListener(() {
        if (mounted) setState(() {});
        if (controller.value.isPlaying && _showControls) _startHideTimer();
        if (controller.value.hasError) {
          setState(() => errorMessage = controller.value.errorDescription ?? "Erreur inconnue");
        }
      })
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _showControls = true);
          controller.play();
          _startHideTimer();
        }
      }).catchError((e) {
        if (mounted) setState(() => errorMessage = e.toString());
      });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    controller.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_isFullScreen) {
          _toggleFullScreen();
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: errorMessage != null
              ? Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error, color: Colors.red, size: 80),
              Text(errorMessage!, style: TextStyle(color: Colors.white, fontSize: 16)),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: Text("Retour"),
              ),
            ],
          )
              : controller.value.isInitialized
              ? Stack(
            alignment: Alignment.center,
            children: [
              // === 1. VIDÉO (fond) ===
              _isFullScreen
                  ? SizedBox.expand(
                child: ClipRect(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: controller.value.size.width,
                      height: controller.value.size.height,
                      child: VideoPlayer(controller),
                    ),
                  ),
                ),
              )
                  : AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: VideoPlayer(controller),
              ),

              // === 2. Double tap seek (gauche / droite) ===
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onDoubleTap: _seekBackward,
                      behavior: HitTestBehavior.translucent,
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onDoubleTap: _seekForward,
                      behavior: HitTestBehavior.translucent,
                    ),
                  ),
                ],
              ),

              // === 3. Tap partout pour afficher/masquer les contrôles ===
              Positioned.fill(
                child: GestureDetector(
                  onTap: _toggleControls,
                  behavior: HitTestBehavior.translucent,
                ),
              ),

              // === 4. WATERMARK "Chronostv" → TOUJOURS VISIBLE (portrait + paysage) ===
              Positioned(
                top: 20,
                right: 20,
                child: Text(
                  "Chronostv",
                  style: TextStyle(
                    color: const Color(0xFF00FFCC), // très belle couleur cyan néon
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    shadows: [
                      Shadow(
                        blurRadius: 12,
                        color: Colors.black.withOpacity(0.7),
                        offset: const Offset(2, 2),
                      ),
                    ],
                  ),
                ),
              ),

              // === 5. Nom de la vidéo (plein écran) → N'AFFICHE QUE SI LES CONTRÔLES SONT VISIBLES ===
              if (_isFullScreen && _showControls)
                Positioned(
                  top: 50,
                  left: 20,
                  right: 20,
                  child: Text(
                    widget.name,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

              // === 6. CONTRÔLES (barre de progression + boutons) ===
              if (_showControls)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.transparent, Colors.black87],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        VideoProgressIndicator(
                          controller,
                          allowScrubbing: true,
                          colors: VideoProgressColors(
                            playedColor: const Color(0xFFE50914),
                            bufferedColor: Colors.white38,
                            backgroundColor: Colors.white24,
                          ),
                        ),
                        SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              _formatDuration(controller.value.position),
                              style: TextStyle(color: Colors.white),
                            ),
                            Spacer(),
                            Text(
                              _formatDuration(controller.value.duration),
                              style: TextStyle(color: Colors.white),
                            ),
                            SizedBox(width: 30),
                            IconButton(
                              icon: Icon(Icons.replay_10, color: Colors.white, size: 32),
                              onPressed: _seekBackward,
                            ),
                            IconButton(
                              icon: Icon(Icons.forward_10, color: Colors.white, size: 32),
                              onPressed: _seekForward,
                            ),
                            IconButton(
                              icon: Icon(
                                _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                                color: Colors.white,
                                size: 32,
                              ),
                              onPressed: _toggleFullScreen,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

              // === 7. Bouton play central (quand pause) ===
              if (!controller.value.isPlaying)
                GestureDetector(
                  onTap: () => controller.play(),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    padding: EdgeInsets.all(24),
                    child: Icon(Icons.play_arrow, color: Colors.white, size: 80),
                  ),
                ),
            ],
          )
              : CircularProgressIndicator(color: const Color(0xFFE50914)),
        ),
      ),
    );
  }
}
