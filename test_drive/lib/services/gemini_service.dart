import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_generative_ai/google_generative_ai.dart' as genai;

class GeminiProcessingService {
  final FlutterTts flutterTts;
  final String apiKey;
  genai.GenerativeModel? _model;
  genai.ChatSession? _chat;

  GeminiProcessingService({required this.flutterTts, required this.apiKey}) {
    initializeModel();
  }

  Future<String> loadEnvFile() async {
    return await rootBundle.loadString('assets/.env');
  }

  String? parseApiKey(String fileContents) {
    final List<String> lines = fileContents.split('\n');
    final apiKeyLine = lines.firstWhere((line) => line.startsWith('API_KEY='),
        orElse: () => '');
    return apiKeyLine.isNotEmpty ? apiKeyLine.split('=')[1].trim() : null;
  }

  Future<void> initializeModel() async {
    final apiKeyContents = await loadEnvFile();
    final apiKey = parseApiKey(apiKeyContents);
    if (apiKey!.isEmpty) {
      print('API key not found. Please check your configuration.');
      return;
    }
    _model ??=
        genai.GenerativeModel(model: 'gemini-1.5-pro-latest', apiKey: apiKey);
    _chat ??= _model!.startChat(history: [
      genai.Content.model([
        genai.TextPart(
            "You are a Helper or Guide for the Visually Impaired user. The input is a extracted frame from a video taken by the visually impaired user. Create a simple yet concise video description for the visually impaired user. Specifically, They want to know if there's anything of interest that would affect their decision making on safety. I don't need the full description of everything going on in the environment, but I need to be alerted if there's a concern, and reassured if not. Please limit the response to 4 sentences unless absolutely critical. Imagine you are talking to a friend, make this conversational. Please start your response with a one sentence summary of the situation. At the end, always ask if the user needs more information.")
      ])
    ]);
    print('Model initialized.');
  }

  Future<void> processVideo(String? framePath) async {
    if (framePath != null && await File(framePath).exists()) {
      final extractedImage = await File(framePath).readAsBytes();
      var userVideo = genai.Content.data('image/jpeg', extractedImage);
      //sendmessage() sendmessagestream()
      await for (final chunk in _chat!.sendMessageStream(userVideo)) {
        if (chunk.text != null && chunk.text!.isNotEmpty) {
          await flutterTts.speak(chunk.text!);
        } else {
          print('No description available.');
        }
      }
      cleanupFrame(framePath);
    }
  }

  Future<void> processAudio(String? audioText) async {
    if (audioText != null) {
      //var response = await _chat!.sendMessage(genai.Content.text(
      //    "based on that extracted frame from the video, $audioText"));
      //await flutterTts.speak(response.text!);
//
      //_chat?.history.forEach((element) {
      //  print(element.role);
      //});
      var userAudio = genai.Content.text(audioText);
      await for (final chunk in _chat!.sendMessageStream(userAudio)) {
        if (chunk.text != null && chunk.text!.isNotEmpty) {
          await flutterTts.speak(chunk.text!);
        } else {
          print('No description available.');
        }
        audioText = '';
      }
    }
  }

  Future<void> cleanupFrame(String framePath) async {
    try {
      var frameFile = File(framePath);
      if (await frameFile.exists()) {
        await frameFile.delete();
        print("Extracted frame file deleted successfully.");
      }
    } catch (e) {
      print("Failed to delete files: $e");
    }
  }
}
