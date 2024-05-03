import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ffmpeg/flutter_ffmpeg.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_generative_ai/google_generative_ai.dart' as genai;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

Future<String> loadEnvFile() async {
  return await rootBundle.loadString('assets/.env');
}

String? parseApiKey(String fileContents) {
  final List<String> lines = fileContents.split('\n');
  final apiKeyLine =
      lines.firstWhere((line) => line.startsWith('API_KEY='), orElse: () => '');
  return apiKeyLine.isNotEmpty ? apiKeyLine.split('=')[1].trim() : null;
}

stt.SpeechToText _speech = stt.SpeechToText();

class VideoProcessingService {
  final CameraController controller;
  final FlutterTts flutterTts;
  final Function(bool) onRecordingStateChanged;

  VideoProcessingService({
    required this.controller,
    required this.flutterTts,
    required this.onRecordingStateChanged,
  }) {
    _initializeSpeech();
  }

  Future<void> _initializeSpeech() async {
    bool hasSpeech = await _speech.initialize();
    if (!hasSpeech) {
      print("The user has denied the use of speech recognition.");
    } else {
      print("Speech initialization successful.");
    }
  }

  Future<void> startVideoRecording() async {
    if (!controller.value.isInitialized) {
      await flutterTts.speak("Camera is not initialized.");
      return;
    }
    try {
      await controller.initialize();
      await controller.startVideoRecording();
      onRecordingStateChanged(true);
      await flutterTts.speak("Scanning. Tap again to stop.");
    } catch (e) {
      await flutterTts.speak("Failed to start recording due to $e");
    }
  }

  Future<void> stopAndProcessVideo() async {
    if (!controller.value.isRecordingVideo) {
      await flutterTts.speak("No video is currently being recorded.");
      return;
    }
    try {
      final videoFile = await controller.stopVideoRecording();
      onRecordingStateChanged(false);
      await flutterTts.speak("Finished Scanning. Analyzing your surroundings.");
      final extractedFrame = await extractMiddleFrame(videoFile.path);
      await geminiprocess(extractedFrame);
    } catch (e) {
      await flutterTts.speak("Error during video processing: $e");
    }
  }

  Future<String> extractMiddleFrame(String videoFilePath) async {
    final FlutterFFmpeg ffmpeg = FlutterFFmpeg();
    final Directory tempDir = await getTemporaryDirectory();
    final String frameExtractionDirectory = path.join(tempDir.path, 'frames');
    final String outputPath = path.join(frameExtractionDirectory,
        '${path.basenameWithoutExtension(videoFilePath)}_middle.jpg');

    await Directory(frameExtractionDirectory).create(recursive: true);

    final info = await FlutterFFprobe().getMediaInformation(videoFilePath);
    final double duration =
        double.parse(info.getMediaProperties()?['duration'] ?? '0');
    final double middleTime = duration / 2;

    final ffmpegCommand =
        "-i $videoFilePath -ss $middleTime -vframes 1 $outputPath";
    final int result = await ffmpeg.execute(ffmpegCommand);

    if (result == 0) {
      print("Middle frame was extracted successfully.");
      return outputPath;
    } else {
      throw Exception(
          "Failed to extract middle frame with FFmpeg error code: $result");
    }
  }

  Future<void> geminiprocess(String framePath) async {
    final String apiKeyContents = await loadEnvFile();
    final String? apiKey = parseApiKey(apiKeyContents);

    if (apiKey == null) {
      print('API key not found. Please check your configuration.');
      return;
    }

    final genai.GenerativeModel model =
        genai.GenerativeModel(model: 'gemini-1.5-pro-latest', apiKey: apiKey);
    final extractedImage = await File(framePath).readAsBytes();
    final genai.Content content = genai.Content.multi([
      genai.TextPart(
          "This is a frame of a video taken by a visually impaired person. Create a simple yet concise video description for a visually impaired person. Specifically, I want to know if there's anything of interest that would affect the visually impaired person's decision making on safety. I don't need the full description of everything going on in the environment, but I need to be alerted if there's a concern, and reassured if not. Please limit the response to 4 sentences unless absolutely critical. Imagine you are talking to a friend, make this conversational. Please start your response with a one sentence summary of the situation."),
      genai.DataPart('image/jpeg', extractedImage)
    ]);

    final chat = model.startChat(history: [content]);
    final response = chat.sendMessageStream(content);

    bool isLastChunk = false;

    // Listening to the model's content stream
    await for (final chunk in response) {
      isLastChunk =
          true; // Assuming each chunk is the final due to nature  //the loop
      await flutterTts.speak(chunk.text ?? 'No description available.');
    }

    if (isLastChunk && _speech.isAvailable) {
      final Completer<String> completer = Completer<String>();
      // Set up the listener
      _speech.listen(
          onResult: (result) {
            if (result.finalResult) {
              completer.complete(result.recognizedWords);
            }
          },
          listenFor: Duration(seconds: 10),
          pauseFor: Duration(seconds: 3));

      String userSpeech = await completer.future;
      print(userSpeech);

      // Wait for the completer to complete which will happen once final result is available
      //print(completer.future);
      var content = genai.Content.text(userSpeech);
      var response = chat.sendMessageStream(content);
      await for (final chunk in response) {
        await flutterTts.speak(chunk.text ?? 'No description available.');
      }
    }
  }
}
