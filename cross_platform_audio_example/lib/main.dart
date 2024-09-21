import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cross_platform_audio/cross_platform_audio_service.dart';
import 'package:shared_audio_utils/shared_audio_utils.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final service = CrossPlatformAudioService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            ElevatedButton(
                onPressed: () async {
                  // await service.initialize();
                  // final streamController = StreamController<Uint8List>();
                  final testData = await rootBundle.load("test.pcm");
                  // streamController.add(testData.buffer.asUint8List());
                  // service.playStream(streamController.stream, 44100, false);
                  service.playBuffer(
                      testData.buffer.asUint8List(), sampleRate: 44100,stereo:false);
                  // await service.play("test.wav", source: AudioSource.Asset);
                },
                child: Text("Play stream"))
          ],
        ),
      ),
    );
  }
}
