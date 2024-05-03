import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

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
  late FlutterTts flutterTts = FlutterTts();
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(widget.camera, ResolutionPreset.high);
    _videoService = VideoProcessingService(
      controller: _controller,
      flutterTts: flutterTts,
      onRecordingStateChanged: (isRecording) {
        setState(() {
          _isRecording = isRecording;
        });
      },
    );
    _initializeCamera();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkAccessibilityFeatures();
    });
  }

  void checkAccessibilityFeatures() {
    var accessibilityFeatures = MediaQuery.of(context).accessibleNavigation;
    if (accessibilityFeatures) {
      flutterTts.speak(
          "Welcome to Echo Sight. Press anywhere on the screen to start or stop recording.");
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleRecording() {
    if (_isRecording) {
      _videoService.stopAndProcessVideo();
    } else {
      _videoService.startVideoRecording();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      await _controller.initialize();
      setState(() {}); // Rebuild the widget after initialization
    } catch (e) {
      print('Error initializing camera: $e');
      // Handle error initializing camera
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _controller.value.isInitialized
          ? GestureDetector(
              onTap: _toggleRecording,
              child: _buildCameraPreview(),
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildCameraPreview() {
    return Stack(
      fit: StackFit.expand, // Make sure the Stack fills the screen
      children: <Widget>[
        CameraPreview(_controller), // This fills the available space
        Positioned(
          bottom: 50.0,
          left: 0.0,
          right: 0.0,
          child: Center(
            child: GestureDetector(
              onLongPressStart: (details) {
                _videoService.startVideoRecording(); // Start recording
              },
              onLongPressEnd: (details) {
                _videoService
                    .stopAndProcessVideo(); // Stop recording and process
              },
              child: Semantics(
                button: true,
                label: "Ready to scan environment",
                hint: "",
                child: Opacity(
                  opacity: 0.7,
                  child: ElevatedButton(
                    onPressed: () {
                      // It's a good practice to provide an action even if it's empty to avoid any accessibility issues
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(20),
                    ),
                    child: const Icon(
                      Icons.camera_alt,
                      size: 50.0,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
