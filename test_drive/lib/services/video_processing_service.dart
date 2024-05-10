import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter_ffmpeg/flutter_ffmpeg.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class VideoProcessingService {
  final CameraController controller;
  final FlutterTts flutterTts;
  final Function(bool) onRecordingStateChanged;
  final FlutterFFmpeg ffmpeg = FlutterFFmpeg();

  VideoProcessingService({
    required this.controller,
    required this.flutterTts,
    required this.onRecordingStateChanged,
  });

  Future<void> startVideoRecording() async {
    if (!controller.value.isInitialized) {
      await _speak("Camera is not initialized.");
      return;
    }
    try {
      await controller.startVideoRecording();
      onRecordingStateChanged(true);
      await _speak("Scanning. Tap again to stop.");
    } catch (e) {
      await _speak("Failed to start recording due to $e");
    }
  }

  Future<String> stopAndProcessVideo() async {
    if (!controller.value.isRecordingVideo) {
      await _speak("No video is currently being recorded.");
      throw Exception("No video recording in progress.");
    }
    try {
      final videoFile = await controller.stopVideoRecording();
      onRecordingStateChanged(false);
      await _speak("Finished Scanning. Analyzing your surroundings.");
      final extractedFrame = await extractMiddleFrame(videoFile.path);
      return extractedFrame;
    } catch (e) {
      await _speak("Error during video processing: $e");
      throw e;
    }
  }

  Future<String> extractMiddleFrame(String videoFilePath) async {
    final tempDir = await getTemporaryDirectory();
    final frameExtractionDirectory = path.join(tempDir.path, 'frames');
    final outputPath = path.join(frameExtractionDirectory,
        '${path.basenameWithoutExtension(videoFilePath)}_middle.jpg');
    await Directory(frameExtractionDirectory).create(recursive: true);
    final mediaInfo = await FlutterFFprobe().getMediaInformation(videoFilePath);
    final duration =
        double.parse(mediaInfo.getMediaProperties()?['duration'] ?? '0');
    final middleTime = duration / 2;
    final command = "-i $videoFilePath -ss $middleTime -vframes 1 $outputPath";
    final result = await ffmpeg.execute(command);
    if (result == 0) {
      print("Middle frame was extracted successfully.");
      cleanupFiles(videoFilePath);
      return outputPath;
    } else {
      throw Exception(
          "Failed to extract middle frame with FFmpeg error code: $result");
    }
  }

  Future<void> _speak(String message) async {
    await flutterTts.speak(message);
  }

  Future<void> cleanupFiles(String videoFilePath) async {
    try {
      var videoFile = File(videoFilePath);
      if (await videoFile.exists()) {
        await videoFile.delete();
        print("Original video file deleted successfully.");
      }
    } catch (e) {
      print("Failed to delete files: $e");
    }
  }
}
