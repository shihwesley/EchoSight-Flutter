import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'services/gemini_service.dart';
import 'services/video_processing_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  final firstCamera = cameras.first;
  runApp(MaterialApp(home: TakePictureScreen(camera: firstCamera)));
}

class TakePictureScreen extends StatefulWidget {
  final CameraDescription camera;
  const TakePictureScreen({Key? key, required this.camera}) : super(key: key);

  @override
  _TakePictureScreenState createState() => _TakePictureScreenState();
}

class _TakePictureScreenState extends State<TakePictureScreen> {
  late CameraController _controller;
  late VideoProcessingService _videoService;
  FlutterTts flutterTts = FlutterTts();
  SpeechToText _audioTranscriber = SpeechToText();
  final GeminiProcessingService _geminiService =
      GeminiProcessingService(flutterTts: FlutterTts(), apiKey: '');
  ValueNotifier<bool> _isVideoRecording = ValueNotifier(false);
  ValueNotifier<bool> _isListening = ValueNotifier(false);
  String _lastWords = '';
  late Timer _semanticsTimer;
  bool _allowSemanticUpdate = true;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _semanticsTimer = Timer.periodic(Duration(minutes: 1), (_) {
      if (!_allowSemanticUpdate) {
        setState(() => _allowSemanticUpdate = true);
      }
    });
  }

  Future<void> _initializeServices() async {
    _controller = CameraController(widget.camera, ResolutionPreset.veryHigh);
    await _controller.initialize();
    setState(() {});
    _videoService = VideoProcessingService(
      controller: _controller,
      flutterTts: flutterTts,
      onRecordingStateChanged: (isRecording) =>
          _isVideoRecording.value = isRecording,
    );
    await _audioTranscriber.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    _semanticsTimer.cancel();
    _audioTranscriber.stop();
    super.dispose();
  }

  void _toggleVideoRecording() async {
    if (_isVideoRecording.value) {
      String framePath = await _videoService.stopAndProcessVideo();
      _geminiService.processVideo(framePath);
      _isVideoRecording.value = false;
    } else {
      _videoService.startVideoRecording();
      //flutterTts.speak("I am scanning what is around you.");
      _isVideoRecording.value = true;
    }
    if (_allowSemanticUpdate) {
      setState(() => _allowSemanticUpdate = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _controller.value.isInitialized
          ? GestureDetector(
              onTap: _toggleVideoRecording,
              child: _buildCameraPreview(),
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildCameraPreview() {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Semantics(
          label: _allowSemanticUpdate
              ? 'Double Tap anywhere on the screen to toggle video recording'
              : '',
          child: GestureDetector(
            onTap: _toggleVideoRecording,
            child: CameraPreview(_controller),
          ),
        ),
        CameraPreview(_controller),
        Positioned(
          bottom: 50.0,
          left: 0.0,
          right: 0.0,
          child: Center(
            child: ValueListenableBuilder<bool>(
              valueListenable: _isListening,
              builder: (_, isListening, __) {
                debugPrint('Listening state: $isListening'); // Debug statement
                return Semantics(
                    button: true,
                    label: 'Microphone',
                    child: Opacity(
                      opacity: 0.7,
                      child: ElevatedButton(
                        onPressed: () {
                          if (isListening) {
                            debugPrint('Stopping listening'); // Debug statement
                            _stopListening();
                          } else {
                            debugPrint('Starting listening'); // Debug statement
                            _startListening();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          shape: const CircleBorder(),
                          padding: const EdgeInsets.all(20),
                        ),
                        child: const Icon(
                          Icons.mic,
                          size: 50.0,
                        ),
                      ),
                    ));
              },
            ),
          ),
        ),
      ],
    );
  }

  void _startListening() {
    _audioTranscriber.listen(onResult: _onSpeechResult);
    _isListening.value = true;
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (result.finalResult) {
      _lastWords = result.recognizedWords;
      _geminiService.processAudio(_lastWords);
    }
  }

  void _stopListening() {
    _audioTranscriber.stop();
    _isListening.value = false;
  }
}
