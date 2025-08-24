import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pip/pip.dart'; // Assuming this is 'pip_flutter' or a similar package
import 'package:screen_brightness/screen_brightness.dart';

import 'player_ui_constants.dart'; // Added import

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final Player _player;
  late final VideoController _controller;
  final Pip _pip = Pip();

  final ValueNotifier<bool> _isPlayingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isLoadingNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<Duration> _durationNotifier = ValueNotifier<Duration>(
    Duration.zero,
  );

  bool _isFullscreen = false;
  bool _muted = false;
  bool _showOverlay = true;
  bool _pipActive = false;
  bool _error = false;
  bool _justExitedPip = false;
  bool _isInteractingWithControls = false; // New state for interaction

  Timer? _overlayTimer;

  double _playbackSpeed = 1.0;
  double _volume = 100.0;
  double _brightness = 0.5; // Default brightness

  @override
  void initState() {
    super.initState();
    _initPlayer();
    _initPiP();
    _checkPipActive();
    WidgetsBinding.instance.addObserver(this);
    _initializeBrightness();
    _showOverlayAndStartTimer();
  }

  Future<void> _initializeBrightness() async {
    try {
      _brightness = await ScreenBrightness().current;
      if (mounted) setState(() {});
    } catch (e) {
      print("Failed to get current brightness: $e");
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _player.pause();
    _player.dispose();
    _overlayTimer?.cancel();
    _isPlayingNotifier.dispose();
    _isLoadingNotifier.dispose();
    _durationNotifier.dispose();
    super.dispose();
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);
    if (!mounted) return;

    final bool isPipCurrentlyActive = await _pip.isActived();

    if (state == AppLifecycleState.resumed) {
      if (_pipActive && !isPipCurrentlyActive) {
        if (mounted) {
          setState(() {
            _pipActive = false;
            _showOverlay = true;
            _justExitedPip = true;
            _isInteractingWithControls = false;
          });
          _showOverlayAndStartTimer();
        }
      } else if (isPipCurrentlyActive != _pipActive) {
        if (mounted) {
          setState(() {
            _pipActive = isPipCurrentlyActive;
            _showOverlay = !isPipCurrentlyActive;
            if (!_pipActive) _justExitedPip = false;
            _isInteractingWithControls = false;
          });
        }
      }
      _initializeBrightness();
    } else if (state == AppLifecycleState.paused) {
      if (isPipCurrentlyActive && !_pipActive) {
        if (mounted) {
          setState(() {
            _pipActive = true;
            _showOverlay = false;
            _justExitedPip = false;
            _isInteractingWithControls = false;
          });
        }
      }
    }
  }

  Future<void> _checkPipActive() async {
    if (!mounted) return;
    bool active = await _pip.isActived();
    if (mounted) {
      setState(() {
        _pipActive = active;
        if (_pipActive) {
          _showOverlay = false;
          _justExitedPip = false;
        } else if (_justExitedPip) {
          _showOverlayAndStartTimer();
        }
      });
    }
  }

  Future<void> _initPlayer() async {
    try {
      _player = Player();
      _controller = VideoController(_player);
      final file = await _copyAssetToFile('assets/sample.mp4');
      await _player.open(Media(file.path));

      _player.stream.duration.listen((d) {
        if (mounted) _durationNotifier.value = d;
      });
      _player.stream.playing.listen((playing) {
        if (mounted) {
          _isPlayingNotifier.value = playing;
          if (playing) _isLoadingNotifier.value = false;
        }
      });
      _player.stream.buffering.listen((buffering) {
        if (mounted) _isLoadingNotifier.value = buffering;
      });
      _player.stream.completed.listen((completed) {
        if (mounted && completed) {
          _isPlayingNotifier.value = false;
        }
      });
      _player.setVolume(_volume);
      _player.setRate(_playbackSpeed);
    } catch (e) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) _isLoadingNotifier.value = false;
    }
  }

  Future<File> _copyAssetToFile(String assetPath) async {
    final byteData = await rootBundle.load(assetPath);
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/sample_video.mp4');
    await file.writeAsBytes(byteData.buffer.asUint8List());
    return file;
  }

  Future<void> _initPiP() async {
    if (await _pip.isSupported()) {
      try {
        await _pip.setup(
          PipOptions(
            aspectRatioX: 16,
            aspectRatioY: 9,
            autoEnterEnabled: false,
          ),
        );
      } catch (_) {}
    }
  }

  void _seekRelative(Duration offset) {
    final currentPosition = _player.state.position;
    final newPosition = currentPosition + offset;
    _player.seek(newPosition < Duration.zero ? Duration.zero : newPosition);
    _resetOverlayTimer();
  }

  void _toggleFullscreen() {
    if (!mounted) return;
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
    _resetOverlayTimer();
  }

  void _toggleMute() {
    if (!mounted) return;
    setState(() => _muted = !_muted);
    _player.setVolume(_muted ? 0.0 : _volume);
    if (!_muted && _volume == 0.0) {
      _volume = 50.0; // Keep this as a default recovery volume for now
      _player.setVolume(_volume);
    }
    _resetOverlayTimer();
  }

  Future<void> _enterPiP() async {
    if (!mounted || _pipActive) return;
    if (await _pip.isSupported()) {
      _overlayTimer?.cancel();
      setState(() => _showOverlay = false);
      try {
        await _pip.start();
        bool success = await _pip.isActived();
        if (mounted) {
          setState(() {
            _pipActive = success;
            _showOverlay = !success;
            _justExitedPip = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _pipActive = false;
            if (!_showOverlay) _resetOverlayTimer();
          });
        }
      }
    }
  }

  void _handleInteractionStart() {
    if (!mounted) return;
    setState(() => _isInteractingWithControls = true);
    _overlayTimer?.cancel(); // Pause timer during interaction
  }

  void _handleInteractionEnd() {
    if (!mounted) return;
    setState(() => _isInteractingWithControls = false);
    _resetOverlayTimer(); // Reset timer after interaction
  }

  void _showOverlayAndStartTimer() {
    if (!mounted || _pipActive) return;
    if (!_showOverlay) setState(() => _showOverlay = true);
    _resetOverlayTimer();
    if (_justExitedPip) setState(() => _justExitedPip = false);
  }

  void _resetOverlayTimer() {
    if (!mounted || _pipActive || _isInteractingWithControls) return;
    _overlayTimer?.cancel();
    if (_showOverlay) {
      _overlayTimer = Timer(const Duration(seconds: 3), () {
        if (mounted &&
            !_pipActive &&
            _showOverlay &&
            !_isInteractingWithControls) {
          setState(() => _showOverlay = false);
        }
      });
    }
    _justExitedPip = false;
  }

  String _formatDuration(Duration d) {
    if (d.isNegative) d = Duration.zero;
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, "0");
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, "0");
    if (hours > 0) {
      return "${hours.toString().padLeft(2, "0")}:$minutes:$seconds";
    }
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    final isCurrentlyPip = _pipActive;
    final mediaQuery = MediaQuery.of(context);

    // Define base icon sizes
    double baseControlIconSize = isCurrentlyPip ? 18 : 24;
    double baseMainPlaybackIconSize = isCurrentlyPip ? 28 : 40;

    double effectiveControlIconSize =
        _isFullscreen && !isCurrentlyPip
            ? baseControlIconSize * 1.2
            : baseControlIconSize;
    double effectiveMainPlaybackIconSize =
        _isFullscreen && !isCurrentlyPip
            ? baseMainPlaybackIconSize * 1.2
            : baseMainPlaybackIconSize;
    double effectivePlayPauseIconSize =
        _isFullscreen && !isCurrentlyPip
            ? (baseMainPlaybackIconSize + 10) * 1.2
            : baseMainPlaybackIconSize + 10;

    final double sideSliderWidth =
        PlayerUiConstants.sideSliderWidthPortrait; // Using constant

    double playerAspectRatio;
    if (_isFullscreen) {
      playerAspectRatio =
          (_player.state.width != null &&
                  _player.state.height != null &&
                  _player.state.width! > 0 &&
                  _player.state.height! > 0)
              ? _player.state.width! / _player.state.height!
              : 16 / 9;
    } else if (isCurrentlyPip) {
      playerAspectRatio = 16 / 9;
    } else {
      playerAspectRatio = 9 / 16;
    }

    final double sliderTopOffset =
        _isFullscreen
            ? mediaQuery.size.height *
                0.1 // Kept dynamic for now
            : mediaQuery.size.height * 0.2; // Kept dynamic for now
    final double sliderBottomOffset =
        _isFullscreen
            ? PlayerUiConstants
                .sideSliderBottomOffsetLandscape // Using constant
            : mediaQuery.size.height * 0.3; // Kept dynamic for now

    // *** MAIN LAYOUT Split ***
    if (_isFullscreen && !isCurrentlyPip) {
      // Fullscreen: overlays expand edge to edge
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              GestureDetector(
                onTap: () {
                  if (isCurrentlyPip || _isInteractingWithControls) return;
                  if (!_showOverlay || _justExitedPip) {
                    _showOverlayAndStartTimer();
                  } else {
                    setState(() => _showOverlay = false);
                    _overlayTimer?.cancel();
                  }
                },
                child: Video(
                  controller: _controller,
                  controls: null,
                  fit: BoxFit.contain,
                ),
              ),
              if (_showOverlay && !_error && !isCurrentlyPip) ...[
                // Left Brightness Slider
                Positioned(
                  left: PlayerUiConstants.p10, // Using constant
                  top: sliderTopOffset,
                  bottom: sliderBottomOffset,
                  width: sideSliderWidth,
                  child: _buildBrightnessSlider(context),
                ),
                // Right Volume Slider
                Positioned(
                  right: PlayerUiConstants.p10, // Using constant
                  top: sliderTopOffset,
                  bottom: sliderBottomOffset,
                  width: sideSliderWidth,
                  child: _buildVolumeSlider(context),
                ),
                // Centered Play/Pause and Seek Controls
                _buildCentralControls(
                  effectiveMainPlaybackIconSize,
                  effectivePlayPauseIconSize,
                ),
                // Bottom Controls Bar
                Positioned(
                  bottom: PlayerUiConstants.p10, // Using constant
                  left: PlayerUiConstants.p10, // Using constant
                  right: PlayerUiConstants.p10, // Using constant
                  child: _buildBottomBar(context, effectiveControlIconSize),
                ),
              ],
              if (_isLoadingNotifier.value && !isCurrentlyPip)
                Center(
                  child: CircularProgressIndicator(
                    color:
                        PlayerUiConstants
                            .generalProgressIndicatorColor, // Using constant
                  ),
                ),
              if (_error && !isCurrentlyPip)
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        color:
                            PlayerUiConstants.errorIconColor, // Using constant
                        size: PlayerUiConstants.errorIconSize, // Using constant
                      ),
                      const SizedBox(
                        height: PlayerUiConstants.p8,
                      ), // Using constant
                      Text(
                        "Error loading video",
                        style: TextStyle(
                          color: PlayerUiConstants.errorTextColor,
                        ), // Using constant
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    } else {
      // Portrait/inset or PiP: overlays within aspect ratio
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: AspectRatio(
              aspectRatio: playerAspectRatio,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  GestureDetector(
                    onTap: () {
                      if (isCurrentlyPip || _isInteractingWithControls) return;
                      if (!_showOverlay || _justExitedPip) {
                        _showOverlayAndStartTimer();
                      } else {
                        setState(() => _showOverlay = false);
                        _overlayTimer?.cancel();
                      }
                    },
                    child: Video(
                      controller: _controller,
                      controls: null,
                      fit: BoxFit.contain,
                    ),
                  ),
                  if (_showOverlay && !_error && !isCurrentlyPip) ...[
                    Positioned(
                      left: PlayerUiConstants.p10, // Using constant
                      top: sliderTopOffset,
                      bottom: sliderBottomOffset,
                      width: sideSliderWidth,
                      child: _buildBrightnessSlider(context),
                    ),
                    Positioned(
                      right: PlayerUiConstants.p10, // Using constant
                      top: sliderTopOffset,
                      bottom: sliderBottomOffset,
                      width: sideSliderWidth,
                      child: _buildVolumeSlider(context),
                    ),
                    _buildCentralControls(
                      effectiveMainPlaybackIconSize,
                      effectivePlayPauseIconSize,
                    ),
                    Positioned(
                      bottom: PlayerUiConstants.p10, // Using constant
                      left: PlayerUiConstants.p10, // Using constant
                      right: PlayerUiConstants.p10, // Using constant
                      child: _buildBottomBar(context, effectiveControlIconSize),
                    ),
                  ],
                  if (_isLoadingNotifier.value && !isCurrentlyPip)
                    Center(
                      child: CircularProgressIndicator(
                        color:
                            PlayerUiConstants
                                .generalProgressIndicatorColor, // Using constant
                      ),
                    ),
                  if (_error && !isCurrentlyPip)
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            color:
                                PlayerUiConstants
                                    .errorIconColor, // Using constant
                            size:
                                PlayerUiConstants
                                    .errorIconSize, // Using constant
                          ),
                          const SizedBox(
                            height: PlayerUiConstants.p8,
                          ), // Using constant
                          Text(
                            "Error loading video",
                            style: TextStyle(
                              color: PlayerUiConstants.errorTextColor,
                            ), // Using constant
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }
  }

  // --- Helper Widgets split out for reuse (optional but clearer) ---

  Widget _buildBrightnessSlider(BuildContext context) {
    final isFull = _isFullscreen && !_pipActive;
    return Container(
      decoration: BoxDecoration(
        color: PlayerUiConstants.sideSliderBackgroundColor, // Using constant
        borderRadius:
            PlayerUiConstants.sideSliderContainerRadius, // Using constant
      ),
      child: RotatedBox(
        quarterTurns: 3,
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight:
                PlayerUiConstants.sideSliderTrackHeight, // Using constant
            thumbShape: RoundSliderThumbShape(
              enabledThumbRadius:
                  isFull
                      ? PlayerUiConstants.sideSliderThumbRadiusFull
                      : PlayerUiConstants
                          .sideSliderThumbRadiusNormal, // Using constant
            ),
            overlayShape: RoundSliderOverlayShape(
              overlayRadius:
                  isFull
                      ? PlayerUiConstants.sideSliderOverlayRadiusFull
                      : PlayerUiConstants
                          .sideSliderOverlayRadiusNormal, // Using constant
            ),
            activeTrackColor:
                PlayerUiConstants.commonSliderActiveColor, // Using constant
            inactiveTrackColor:
                PlayerUiConstants.commonSliderInactiveColor, // Using constant
            thumbColor:
                PlayerUiConstants.commonSliderThumbColor, // Using constant
          ),
          child: Slider(
            value: _brightness,
            min: 0.0,
            max: 1.0,
            onChangeStart: (_) => _handleInteractionStart(),
            onChangeEnd: (_) => _handleInteractionEnd(),
            onChanged: (value) async {
              setState(() => _brightness = value);
              try {
                await ScreenBrightness().setApplicationScreenBrightness(value);
              } catch (e) {
                print("Failed to set brightness: $e");
              }
              // Timer reset handled by onChangeEnd
            },
          ),
        ),
      ),
    );
  }

  Widget _buildVolumeSlider(BuildContext context) {
    final isFull = _isFullscreen && !_pipActive;
    return Container(
      decoration: BoxDecoration(
        color: PlayerUiConstants.sideSliderBackgroundColor, // Using constant
        borderRadius:
            PlayerUiConstants.sideSliderContainerRadius, // Using constant
      ),
      child: RotatedBox(
        quarterTurns: 3,
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight:
                PlayerUiConstants.sideSliderTrackHeight, // Using constant
            thumbShape: RoundSliderThumbShape(
              enabledThumbRadius:
                  isFull
                      ? PlayerUiConstants.sideSliderThumbRadiusFull
                      : PlayerUiConstants
                          .sideSliderThumbRadiusNormal, // Using constant
            ),
            overlayShape: RoundSliderOverlayShape(
              overlayRadius:
                  isFull
                      ? PlayerUiConstants.sideSliderOverlayRadiusFull
                      : PlayerUiConstants
                          .sideSliderOverlayRadiusNormal, // Using constant
            ),
            activeTrackColor:
                PlayerUiConstants.commonSliderActiveColor, // Using constant
            inactiveTrackColor:
                PlayerUiConstants.commonSliderInactiveColor, // Using constant
            thumbColor:
                PlayerUiConstants.commonSliderThumbColor, // Using constant
          ),
          child: Slider(
            value: _muted ? 0.0 : _volume,
            min: 0.0,
            max: 100.0,
            onChangeStart: (_) => _handleInteractionStart(),
            onChangeEnd: (_) => _handleInteractionEnd(),
            onChanged: (value) {
              setState(() {
                _volume = value;
                _muted = value == 0.0;
              });
              _player.setVolume(value);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCentralControls(double iconSize, double playPauseIconSize) {
    return Positioned.fill(
      child: Align(
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              iconSize: iconSize,
              color: PlayerUiConstants.controlButtonIconColor, // Using constant
              icon: const Icon(Icons.replay_10_sharp),
              onPressed: () => _seekRelative(const Duration(seconds: -10)),
            ),
            SizedBox(
              width:
                  _isFullscreen
                      ? PlayerUiConstants.centralControlSpacingFull
                      : PlayerUiConstants.centralControlSpacingNormal,
            ), // Using constant
            ValueListenableBuilder<bool>(
              valueListenable: _isPlayingNotifier,
              builder: (context, isPlaying, child) {
                return IconButton(
                  iconSize: playPauseIconSize,
                  color:
                      PlayerUiConstants
                          .controlButtonIconColor, // Using constant
                  icon: Icon(
                    isPlaying
                        ? Icons.pause_circle_filled_sharp
                        : Icons.play_circle_fill_sharp,
                  ),
                  onPressed: () {
                    _player.playOrPause();
                    _resetOverlayTimer();
                  },
                );
              },
            ),
            SizedBox(
              width:
                  _isFullscreen
                      ? PlayerUiConstants.centralControlSpacingFull
                      : PlayerUiConstants.centralControlSpacingNormal,
            ), // Using constant
            IconButton(
              iconSize: iconSize,
              color: PlayerUiConstants.controlButtonIconColor, // Using constant
              icon: const Icon(Icons.forward_10_sharp),
              onPressed: () => _seekRelative(const Duration(seconds: 10)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(
    BuildContext context,
    double effectiveControlIconSize,
  ) {
    return Container(
      padding: const EdgeInsets.all(PlayerUiConstants.p8), // Using constant
      decoration: BoxDecoration(
        color: PlayerUiConstants.bottomBarBackgroundColor, // Using constant
        borderRadius:
            PlayerUiConstants.bottomBarContainerRadius, // Using constant
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: PlayerUiConstants.p4,
            ), // Using constant
            child: Row(
              children: [
                ValueListenableBuilder<Duration>(
                  valueListenable: _durationNotifier,
                  builder: (context, duration, _) {
                    return StreamBuilder<Duration>(
                      stream: _player.stream.position,
                      initialData: Duration.zero,
                      builder: (context, snapshot) {
                        final position = snapshot.data ?? Duration.zero;
                        return Text(
                          _formatDuration(position),
                          style: TextStyle(
                            color:
                                PlayerUiConstants
                                    .timeDisplayTextColor, // Using constant
                            fontSize:
                                _isFullscreen
                                    ? PlayerUiConstants.timeDisplayFontSizeFull
                                    : PlayerUiConstants
                                        .timeDisplayFontSizeNormal, // Using constant
                          ),
                        );
                      },
                    );
                  },
                ),
                Expanded(
                  child: ValueListenableBuilder<Duration>(
                    valueListenable: _durationNotifier,
                    builder: (context, duration, _) {
                      return StreamBuilder<Duration>(
                        stream: _player.stream.position,
                        initialData: Duration.zero,
                        builder: (context, snapshot) {
                          final position = snapshot.data ?? Duration.zero;
                          return SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight:
                                  _isFullscreen
                                      ? PlayerUiConstants
                                          .bottomBarSeekSliderTrackHeightFull
                                      : PlayerUiConstants
                                          .bottomBarSeekSliderTrackHeightNormal, // Using constant
                              thumbShape: RoundSliderThumbShape(
                                enabledThumbRadius:
                                    _isFullscreen
                                        ? 8.0
                                        : 6.0, // Kept for now, can be const
                              ),
                              overlayShape: RoundSliderOverlayShape(
                                overlayRadius:
                                    _isFullscreen
                                        ? 16.0
                                        : 12.0, // Kept for now, can be const
                              ),
                              activeTrackColor:
                                  PlayerUiConstants
                                      .commonSliderActiveColor, // Using constant
                              inactiveTrackColor:
                                  PlayerUiConstants
                                      .commonSliderInactiveColor, // Using constant
                              thumbColor:
                                  PlayerUiConstants
                                      .commonSliderThumbColor, // Using constant
                            ),
                            child: Slider(
                              value: position.inMilliseconds.toDouble().clamp(
                                0.0,
                                duration.inMilliseconds.toDouble() > 0
                                    ? duration.inMilliseconds.toDouble()
                                    : 1.0,
                              ),
                              min: 0.0,
                              max:
                                  duration.inMilliseconds.toDouble() > 0
                                      ? duration.inMilliseconds.toDouble()
                                      : 1.0,
                              onChangeStart: (_) => _handleInteractionStart(),
                              onChangeEnd: (_) => _handleInteractionEnd(),
                              onChanged: (value) {
                                _player.seek(
                                  Duration(milliseconds: value.toInt()),
                                );
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                ValueListenableBuilder<Duration>(
                  valueListenable: _durationNotifier,
                  builder: (context, duration, _) {
                    return Text(
                      _formatDuration(duration),
                      style: TextStyle(
                        color:
                            PlayerUiConstants
                                .timeDisplayTextColor, // Using constant
                        fontSize:
                            _isFullscreen
                                ? PlayerUiConstants.timeDisplayFontSizeFull
                                : PlayerUiConstants
                                    .timeDisplayFontSizeNormal, // Using constant
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(
            height: PlayerUiConstants.p4 / 2,
          ), // Adjusted from 5, can be new constant
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                iconSize: effectiveControlIconSize,
                color: Colors.white, // Can be a constant
                icon: Icon(
                  _muted ? Icons.volume_off_sharp : Icons.volume_up_sharp,
                ),
                onPressed: _toggleMute,
              ),
              const Spacer(),
              Theme(
                data: Theme.of(context).copyWith(
                  canvasColor: Colors.black.withOpacity(
                    PlayerUiConstants.primaryOpacity,
                  ),
                ), // Using constant
                child: DropdownButton<double>(
                  value: _playbackSpeed,
                  icon: Icon(
                    Icons.speed_sharp,
                    color: Colors.white, // Can be a constant
                    size: effectiveControlIconSize - 2,
                  ),
                  underline: Container(),
                  dropdownColor: Colors.black.withOpacity(
                    PlayerUiConstants.primaryOpacity,
                  ), // Using constant
                  style: TextStyle(
                    color: Colors.white, // Can be a constant
                    fontSize: _isFullscreen ? 15 : 13, // Can be constant
                  ),
                  items:
                      [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0].map((speed) {
                        return DropdownMenuItem<double>(
                          value: speed,
                          child: Text('${speed}x'),
                        );
                      }).toList(),
                  onTap: () {
                    _handleInteractionStart();
                  },
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _playbackSpeed = value);
                      _player.setRate(value);
                    }
                    _handleInteractionEnd();
                  },
                ),
              ),
              const Spacer(),
              if (!_pipActive && (ModalRoute.of(context)?.isCurrent ?? false))
                IconButton(
                  iconSize: effectiveControlIconSize,
                  color: Colors.white, // Can be a constant
                  icon: const Icon(Icons.picture_in_picture_alt_sharp),
                  onPressed: _enterPiP,
                ),
              if (_pipActive)
                Padding(
                  padding: const EdgeInsets.only(
                    right: PlayerUiConstants.p8,
                  ), // Using constant
                  child: Icon(
                    Icons.picture_in_picture_alt_sharp,
                    color:
                        PlayerUiConstants
                            .commonSliderActiveColor, // Re-used amber color
                    size: effectiveControlIconSize,
                  ),
                ),
              IconButton(
                iconSize: effectiveControlIconSize,
                color: Colors.white, // Can be a constant
                icon: Icon(
                  _isFullscreen
                      ? Icons.fullscreen_exit_sharp
                      : Icons.fullscreen_sharp,
                ),
                onPressed: _toggleFullscreen,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
