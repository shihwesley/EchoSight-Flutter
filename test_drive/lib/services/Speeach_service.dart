import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

class VoiceInteractionScreen extends StatefulWidget {
  @override
  _VoiceInteractionScreenState createState() => _VoiceInteractionScreenState();
}

class _VoiceInteractionScreenState extends State<VoiceInteractionScreen> {
  late stt.SpeechToText _speech;
  late FlutterTts _flutterTts;
  bool _isListening = false;
  String _text = "Press the button and start speaking";

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _flutterTts = FlutterTts();

    _flutterTts.setCompletionHandler(() {
      _startListening();
    });
  }

  void _startListening() async {
    bool available = await _speech.initialize(
      onStatus: (val) => print('onStatus: $val'),
      onError: (val) => print('onError: $val'),
    );
    if (available) {
      setState(() => _isListening = true);
      _speech.listen(
        onResult: (val) => setState(() {
          _text = val.recognizedWords;
        }),
      );
    } else {
      setState(() => _isListening = false);
      await _speech.stop();
    }
  }

  void _speakAndListen() async {
    await _flutterTts.speak("Hello, how can I help you today?");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Voice Interaction"),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            _isListening ? 'Listening...' : 'Not listening',
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(_text),
          ),
          ElevatedButton(
            onPressed: _speakAndListen,
            child: Icon(Icons.mic),
          ),
        ],
      ),
    );
  }
}
