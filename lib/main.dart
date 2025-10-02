import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audio Player',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: AudioPlayerScreen(),
    );
  }
}

class AudioPlayerScreen extends StatefulWidget {
  @override
  _AudioPlayerScreenState createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends State<AudioPlayerScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  String _currentAudioName = 'No audio playing';
  int _currentIndex = 0;
  double _progress = 0.0;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isPlaying = false;
  bool _isLooping = false;
  List<File> _audioFiles = [];
  String _folderPath = '';
  String _inputNumber = '';
  Timer? _inputTimer;
  bool _firstLaunch = true;

  @override
  void initState() {
    super.initState();
    _initApp();
    _audioPlayer.onDurationChanged.listen((Duration d) {
      setState(() {
        _duration = d;
      });
    });
    _audioPlayer.onPositionChanged.listen((Duration p) {
      setState(() {
        _position = p;
        _progress = _position.inMilliseconds / _duration.inMilliseconds;
      });
    });
    _audioPlayer.onPlayerComplete.listen((event) {
      if (_isLooping) {
        _playAudio(_currentIndex);
      } else {
        _nextAudio();
      }
    });
  }

  Future<void> _initApp() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    _firstLaunch = prefs.getBool('first_launch') ?? true;

    if (_firstLaunch) {
      await _requestPermissions();
      await _createFolder();
      prefs.setBool('first_launch', false);
      _showDialog('Please place your audio files in the "8fu" folder.');
    }

    await _loadAudioFiles();
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      var status = await Permission.manageExternalStorage.request();
      if (!status.isGranted) {
        // Handle permission denied
        _showDialog('Storage permission is required to access audio files.');
      }
    }
  }

  Future<void> _createFolder() async {
    Directory? externalDir = await getExternalStorageDirectory();
    if (externalDir != null) {
      _folderPath = '${externalDir.path}/8fu';
      Directory folder = Directory(_folderPath);
      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }
    }
  }

  Future<void> _loadAudioFiles() async {
    if (_folderPath.isNotEmpty) {
      Directory folder = Directory(_folderPath);
      if (await folder.exists()) {
        List<FileSystemEntity> files = folder.listSync();
        _audioFiles = files.where((file) => file.path.endsWith('.mp3') || file.path.endsWith('.wav')).map((e) => File(e.path)).toList();
        // Sort by filename assuming filenames are like 1.mp3, 2.mp3, etc.
        _audioFiles.sort((a, b) => int.parse(a.uri.pathSegments.last.split('.').first).compareTo(int.parse(b.uri.pathSegments.last.split('.').first)));
        setState(() {});
      }
    }
  }

  void _playAudio(int index) {
    if (index >= 0 && index < _audioFiles.length) {
      _audioPlayer.play(DeviceFileSource(_audioFiles[index].path));
      setState(() {
        _currentIndex = index;
        _currentAudioName = _audioFiles[index].uri.pathSegments.last;
        _isPlaying = true;
      });
    }
  }

  void _pauseAudio() {
    _audioPlayer.pause();
    setState(() {
      _isPlaying = false;
    });
  }

  void _nextAudio() {
    int nextIndex = (_currentIndex + 1) % _audioFiles.length;
    _playAudio(nextIndex);
  }

  void _previousAudio() {
    int prevIndex = (_currentIndex - 1 + _audioFiles.length) % _audioFiles.length;
    _playAudio(prevIndex);
  }

  void _toggleLoop() {
    setState(() {
      _isLooping = !_isLooping;
    });
  }

  void _handleNumberInput(String number) {
    _inputNumber += number;
    setState(() {});

    _inputTimer?.cancel();
    _inputTimer = Timer(Duration(seconds: 1), () {
      int? index = int.tryParse(_inputNumber);
      if (index != null && index > 0 && index <= _audioFiles.length) {
        _playAudio(index - 1); // Assuming 1-based indexing
      }
      _inputNumber = '';
      setState(() {});
    });
  }

  void _showDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Info'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _inputTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Audio Player')),
      body: Column(
        children: [
          Expanded(
            flex: 1,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_currentAudioName),
                Text('Index: ${_currentIndex + 1}'),
                if (_inputNumber.isNotEmpty) Text('Input: $_inputNumber'),
                LinearProgressIndicator(value: _progress),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      onPressed: _toggleLoop,
                      child: Text(_isLooping ? 'Loop On' : 'Loop Off'),
                    ),
                    ElevatedButton(
                      onPressed: _previousAudio,
                      child: Text('Previous'),
                    ),
                    ElevatedButton(
                      onPressed: _nextAudio,
                      child: Text('Next'),
                    ),
                    ElevatedButton(
                      onPressed: _isPlaying ? _pauseAudio : () => _playAudio(_currentIndex),
                      child: Text(_isPlaying ? 'Pause' : 'Play'),
                    ),
                  ],
                ),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 3,
                    children: List.generate(10, (index) {
                      return ElevatedButton(
                        onPressed: () => _handleNumberInput(index.toString()),
                        child: Text(index.toString()),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}