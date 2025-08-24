import 'dart:async';
import 'dart:developer' as developer; // For performance tracing
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pip/pip.dart'; // Assuming this is 'pip_flutter' or a similar package

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

  Timer? _overlayTimer;

  @override
  void initState() {
    super.initState();
    developer.log('HomeScreen: initState Start', name: 'my_app_perf_log');
    _initPlayer();
    _initPiP();
    _checkPipActive();
    WidgetsBinding.instance.addObserver(this);
    developer.log('HomeScreen: initState End', name: 'my_app_perf_log');
  }

  @override
  void dispose() {
    developer.log('HomeScreen: dispose Start', name: 'my_app_perf_log');
    WidgetsBinding.instance.removeObserver(this);
    _player.pause();
    _player.dispose();
    _overlayTimer?.cancel();
    _isPlayingNotifier.dispose();
    _isLoadingNotifier.dispose();
    _durationNotifier.dispose();
    developer.log('HomeScreen: dispose End', name: 'my_app_perf_log');
    super.dispose();
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);
    developer.log(
      'AppLifecycleState changed to: $state',
      name: 'my_app_perf_log',
    );
    if (!mounted) return;

    final bool isPipCurrentlyActive = await _pip.isActived();
    developer.log(
      'PiP status check in didChangeAppLifecycleState: $isPipCurrentlyActive, current _pipActive: $_pipActive',
      name: 'my_app_perf_log',
    );

    if (state == AppLifecycleState.resumed) {
      if (_pipActive && !isPipCurrentlyActive) {
        developer.log(
          'Exited PiP mode (detected via AppLifecycleState.resumed)',
          name: 'my_app_perf_log',
        );
        if (mounted) {
          setState(() {
            _pipActive = false;
            _showOverlay = true;
            _justExitedPip = true;
          });
          // Start hide timer automatically after PiP exit
          _overlayTimer?.cancel();
          _overlayTimer = Timer(const Duration(seconds: 2), () {
            if (mounted && !_pipActive) {
              setState(() {
                _showOverlay = false;
                _justExitedPip = false;
              });
            }
          });
        }
      } else if (isPipCurrentlyActive != _pipActive) {
        developer.log(
          'Syncing PiP state on resume. Plugin says: $isPipCurrentlyActive, local was: $_pipActive',
          name: 'my_app_perf_log',
        );
        if (mounted) {
          setState(() {
            _pipActive = isPipCurrentlyActive;
            _showOverlay = !isPipCurrentlyActive;
            if (!_pipActive && _justExitedPip) {
              // This case might be redundant if the above handles it,
              // but ensures _justExitedPip is true if we determine we just left PiP.
            } else if (!_pipActive) {
              _justExitedPip =
                  false; // If not in PiP and didn't just exit, reset flag.
            }
          });
        }
      }
    } else if (state == AppLifecycleState.paused) {
      if (isPipCurrentlyActive && !_pipActive) {
        developer.log(
          'App paused, PiP detected as active. Updating local state.',
          name: 'my_app_perf_log',
        );
        if (mounted) {
          setState(() {
            _pipActive = true;
            _showOverlay = false;
            _justExitedPip =
                false; // When entering PiP, we haven't "just exited"
          });
        }
      }
    }
  }

  Future<void> _checkPipActive() async {
    if (!mounted) return;
    bool active = await _pip.isActived();
    developer.log('Initial PiP check: $active', name: 'my_app_perf_log');
    if (mounted) {
      setState(() {
        _pipActive = active;
        if (_pipActive) {
          _showOverlay = false;
          _justExitedPip = false;
        } else if (_justExitedPip) {
          // Start timer after exiting PiP
          _showOverlayAndStartTimer();
        }
      });
    }
  }

  Future<void> _initPlayer() async {
    developer.log('HomeScreen: _initPlayer Start', name: 'my_app_perf_log');
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
    } catch (e, s) {
      developer.log(
        'HomeScreen: _initPlayer Error: $e',
        stackTrace: s,
        name: 'my_app_perf_log',
        error: e,
      );
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) _isLoadingNotifier.value = false;
      developer.log('HomeScreen: _initPlayer End', name: 'my_app_perf_log');
    }
  }

  Future<File> _copyAssetToFile(String assetPath) async {
    final stopwatch = Stopwatch()..start();
    final byteData = await rootBundle.load(assetPath);
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/sample_video.mp4');
    await file.writeAsBytes(byteData.buffer.asUint8List());
    developer.log(
      'HomeScreen: _copyAssetToFile completed in ${stopwatch.elapsedMilliseconds}ms for $assetPath',
      name: 'my_app_perf_log',
    );
    stopwatch.stop();
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
        developer.log('PiP setup successful', name: 'my_app_perf_log');
      } catch (e) {
        developer.log('Error setting up PiP: $e', name: 'my_app_perf_log');
      }
    } else {
      developer.log(
        'PiP is not supported on this device.',
        name: 'my_app_perf_log',
      );
    }
  }

  void _seekRelative(Duration offset) {
    final currentPosition = _player.state.position;
    final newPosition = currentPosition + offset;
    _player.seek(newPosition < Duration.zero ? Duration.zero : newPosition);
    _showOverlayWithTimeoutIfNeeded();
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
    _showOverlayWithTimeoutIfNeeded();
  }

  void _toggleMute() {
    if (!mounted) return;
    setState(() => _muted = !_muted);
    _player.setVolume(_muted ? 0.0 : 100.0);
    _showOverlayWithTimeoutIfNeeded();
  }

  Future<void> _enterPiP() async {
    if (!mounted || _pipActive) return;
    if (await _pip.isSupported()) {
      _overlayTimer?.cancel();
      setState(() {
        _showOverlay = false;
      }); // Optimistically hide
      developer.log('Attempting to enter PiP mode...', name: 'my_app_perf_log');
      try {
        await _pip.start();
        // Check activation status AFTER attempting to start
        bool success = await _pip.isActived();
        if (mounted) {
          if (success) {
            developer.log(
              'Entered PiP mode successfully',
              name: 'my_app_perf_log',
            );
            setState(() {
              _pipActive = true;
              _showOverlay = false; // Ensure it's hidden
              _justExitedPip = false;
            });
          } else {
            developer.log(
              'Failed to enter PiP mode (plugin reported not active after start)',
              name: 'my_app_perf_log',
            );
            setState(() {
              _pipActive = false; // Ensure state is correct
              // If PiP failed, show overlay again
              if (!_showOverlay) _showOverlayWithTimeoutIfNeeded();
            });
          }
        }
      } catch (e) {
        developer.log(
          'Error calling _pip.start(): $e',
          name: 'my_app_perf_log',
        );
        if (mounted) {
          setState(() {
            _pipActive = false;
            if (!_showOverlay) _showOverlayWithTimeoutIfNeeded();
          });
        }
      }
    } else {
      developer.log(
        'PiP not supported, cannot enter.',
        name: 'my_app_perf_log',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Picture-in-Picture is not supported.')),
      );
    }
  }

  Future<void> _manualExitPiP() async {
    if (!mounted || !_pipActive) return;
    developer.log(
      'Attempting to manually exit PiP mode...',
      name: 'my_app_perf_log',
    );
    // Your PiP package might have a _pip.stop() or _pip.exit() method.
    // If it does, call it here. Then, didChangeAppLifecycleState should handle the UI update.
    // For now, this is a placeholder. If _pip.stop() exists:
    // try {
    //   await _pip.stop();
    //   // AppLifecycleState should then catch the change.
    // } catch(e) {
    //   developer.log('Error calling _pip.stop(): $e', name: 'my_app_perf_log');
    // }
    // If no explicit stop method, this button might just bring the app to focus,
    // and didChangeAppLifecycleState would handle the state change.
  }

  // Call this when user interacts with player controls (play, seek, etc.)
  // or when explicitly tapping the video to show controls.
  void _showOverlayAndStartTimer() {
    if (!mounted || _pipActive) return;

    if (!_showOverlay) {
      setState(() => _showOverlay = true);
    }
    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && !_pipActive && _showOverlay) {
        setState(() => _showOverlay = false);
      }
    });
    // CRITICAL: Any action that shows the overlay and starts the timer
    // means the user has interacted, so we are no longer "just exited PiP".
    if (_justExitedPip) {
      setState(() => _justExitedPip = false);
    }
  }

  // Call this when UI elements that should refresh the overlay timer are interacted with
  // (e.g., seek buttons, play/pause, mute, fullscreen toggle).
  void _showOverlayWithTimeoutIfNeeded() {
    if (!mounted || _pipActive) return;

    // Always show overlay first
    if (!_showOverlay) setState(() => _showOverlay = true);

    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && !_pipActive) {
        setState(() => _showOverlay = false);
      }
    });

    _justExitedPip = false; // Reset flag on any interaction
  }

  String _formatDuration(Duration d) {
    if (d.isNegative) d = Duration.zero;
    if (d.inHours > 0) return d.toString().split('.').first.padLeft(8, "0");
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, "0");
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, "0");
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    developer.log(
      'HomeScreen: build. PiP: $_pipActive, Overlay: $_showOverlay, JustExitedPiP: $_justExitedPip',
      name: 'my_app_perf_log',
    );
    final showAppBar = !_isFullscreen && !_pipActive;
    final isCurrentlyPip = _pipActive;

    final double iconSize = isCurrentlyPip ? 20 : 40;
    final double playButtonSize = isCurrentlyPip ? 30 : 56;
    final EdgeInsets overlayPadding =
        isCurrentlyPip
            ? const EdgeInsets.all(4)
            : const EdgeInsets.symmetric(horizontal: 16, vertical: 12);

    return WillPopScope(
      onWillPop: () async {
        if (_isFullscreen) {
          _toggleFullscreen();
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          top: !showAppBar,
          bottom: !_isFullscreen,
          child: Center(
            child: AspectRatio(
              aspectRatio: _isFullscreen || isCurrentlyPip ? 16 / 9 : 9 / 16,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  GestureDetector(
                    onTap: () {
                      if (isCurrentlyPip) return; // No overlay toggling in PiP

                      // If overlay is hidden OR if it's shown *because* we just exited PiP
                      // then a tap should show it and start the timer (and clear _justExitedPip).
                      if (!_showOverlay || _justExitedPip) {
                        _showOverlayAndStartTimer(); // This will also set _justExitedPip = false
                      }
                      // If overlay is already shown (and not because we just exited PiP),
                      // then a tap should hide it.
                      else {
                        setState(() => _showOverlay = false);
                        _overlayTimer?.cancel();
                      }
                    },
                    child: Video(controller: _controller, controls: null),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: _isLoadingNotifier,
                    builder: (context, isLoading, child) {
                      if (isLoading && !isCurrentlyPip) {
                        return const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                  if (_error && !isCurrentlyPip)
                    const Center(
                      child: Text(
                        "Failed to load video.",
                        style: TextStyle(color: Colors.red, fontSize: 18),
                      ),
                    ),

                  if (_showOverlay && !_error && !isCurrentlyPip)
                    Positioned.fill(
                      child: Container(
                        padding: overlayPadding,
                        color: Colors.black.withOpacity(0.45),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      IconButton(
                                        iconSize: iconSize,
                                        color: Colors.white,
                                        icon: const Icon(Icons.replay_10),
                                        onPressed:
                                            () => _seekRelative(
                                              const Duration(seconds: -10),
                                            ),
                                      ),
                                      ValueListenableBuilder<bool>(
                                        valueListenable: _isPlayingNotifier,
                                        builder: (context, isPlaying, child) {
                                          return IconButton(
                                            iconSize: playButtonSize,
                                            color: Colors.white,
                                            icon: Icon(
                                              isPlaying
                                                  ? Icons.pause_circle_filled
                                                  : Icons.play_circle_fill,
                                            ),
                                            onPressed: () {
                                              _player.playOrPause();
                                              _showOverlayWithTimeoutIfNeeded();
                                            },
                                          );
                                        },
                                      ),
                                      IconButton(
                                        iconSize: iconSize,
                                        color: Colors.white,
                                        icon: const Icon(Icons.forward_10),
                                        onPressed:
                                            () => _seekRelative(
                                              const Duration(seconds: 10),
                                            ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    StreamBuilder<Duration>(
                                      stream: _player.stream.position,
                                      builder:
                                          (context, snapshot) => Text(
                                            _formatDuration(
                                              snapshot.data ?? Duration.zero,
                                            ),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                            ),
                                          ),
                                    ),
                                    Expanded(
                                      child: StreamBuilder<Duration>(
                                        stream: _player.stream.position,
                                        builder: (context, positionSnapshot) {
                                          final currentPosition =
                                              positionSnapshot.data ??
                                              Duration.zero;
                                          return ValueListenableBuilder<
                                            Duration
                                          >(
                                            valueListenable: _durationNotifier,
                                            builder: (
                                              context,
                                              duration,
                                              child,
                                            ) {
                                              return SliderTheme(
                                                data: SliderTheme.of(
                                                  context,
                                                ).copyWith(
                                                  trackHeight: 2.0,
                                                  thumbShape:
                                                      const RoundSliderThumbShape(
                                                        enabledThumbRadius: 6.0,
                                                      ),
                                                  overlayShape:
                                                      const RoundSliderOverlayShape(
                                                        overlayRadius: 12.0,
                                                      ),
                                                ),
                                                child: Slider(
                                                  min: 0,
                                                  max: duration.inMilliseconds
                                                      .toDouble()
                                                      .clamp(
                                                        1.0,
                                                        double.infinity,
                                                      ),
                                                  value:
                                                      currentPosition
                                                          .inMilliseconds
                                                          .clamp(
                                                            0.0,
                                                            duration
                                                                .inMilliseconds
                                                                .toDouble(),
                                                          )
                                                          .toDouble(),
                                                  onChanged: (v) {
                                                    _player.seek(
                                                      Duration(
                                                        milliseconds: v.toInt(),
                                                      ),
                                                    );
                                                    _showOverlayWithTimeoutIfNeeded();
                                                  },
                                                  activeColor: Colors.amber,
                                                  inactiveColor: Colors.white38,
                                                ),
                                              );
                                            },
                                          );
                                        },
                                      ),
                                    ),
                                    ValueListenableBuilder<Duration>(
                                      valueListenable: _durationNotifier,
                                      builder:
                                          (context, duration, child) => Text(
                                            _formatDuration(duration),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                            ),
                                          ),
                                    ),
                                  ],
                                ),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    IconButton(
                                      iconSize: iconSize - 8,
                                      color: Colors.white,
                                      icon: Icon(
                                        _muted
                                            ? Icons.volume_off
                                            : Icons.volume_up,
                                      ),
                                      onPressed: _toggleMute,
                                    ),
                                    if (!_pipActive &&
                                        (ModalRoute.of(context)?.isCurrent ??
                                            false)) // Only show if not in PiP and current route
                                      IconButton(
                                        iconSize: iconSize - 8,
                                        color: Colors.white,
                                        icon: const Icon(
                                          Icons.picture_in_picture_alt,
                                        ),
                                        onPressed: _enterPiP,
                                      ),
                                    if (_pipActive)
                                      IconButton(
                                        iconSize: iconSize - 8,
                                        color: Colors.white,
                                        icon: const Icon(Icons.launch),
                                        onPressed: _manualExitPiP,
                                      ),
                                    IconButton(
                                      iconSize: iconSize - 8,
                                      color: Colors.white,
                                      icon: Icon(
                                        _isFullscreen
                                            ? Icons.fullscreen_exit
                                            : Icons.fullscreen,
                                      ),
                                      onPressed: _toggleFullscreen,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
