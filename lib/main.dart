import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audio Player',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: AudioPlayerScreen(),
    );
  }
}

class AudioPlayerScreen extends StatefulWidget {
  @override
  _AudioPlayerScreenState createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends State<AudioPlayerScreen>  {
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

  // ... 其他代码保持不变 ...

  Future<void> _initApp() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    _firstLaunch = prefs.getBool('first_launch') ?? true;

    // 关键修改：直接定义公共存储路径
    _folderPath = '/storage/emulated/0/Download';

    // 权限请求变得至关重要，因为我们正在访问应用外部的目录
    await _requestPermissions();
    if (_firstLaunch) {
      await _createFolder();
      prefs.setBool('first_launch', false);
      _showDialog('请将您的音频文件放置在手机根目录下的 "8fu" 文件夹中。');
    }

    // 现在加载这个公共路径下的文件
    await _loadAudioFiles();
  }

  // ... class _AudioPlayerScreenState ...

  Future<void> _requestPermissions() async {
    PermissionStatus status;

    // 1. 判断安卓版本
    if (Platform.isAndroid) {
      final deviceInfo = await DeviceInfoPlugin().androidInfo;
      // Android 11 (SDK 30) 或更高版本
      if (deviceInfo.version.sdkInt >= 30) {
        status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) {
          // 显示对话框，引导用户去开启“所有文件访问权限”
          await _showPermissionDialog(
            '为了在安卓11及以上版本正常读写文件，应用需要“所有文件访问权限”。\n\n点击“去开启”后，请在新页面中找到并打开此应用的开关，然后返回。',
            () async {
              await Permission.manageExternalStorage.request();
            },
          );
        }
      }
      // Android 10 (SDK 29) 及以下版本
      else {
        status = await Permission.storage.status;
        if (!status.isGranted) {
          // 直接请求旧的存储权限
          await Permission.storage.request();
        }
      }
    }
  }

  // 辅助方法：抽离出通用的权限提示对话框
  Future<void> _showPermissionDialog(
    String content,
    VoidCallback onPressed,
  ) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('权限申请'),
        content: Text(content),
        actions: [TextButton(onPressed: onPressed, child: const Text('去开启'))],
      ),
    );
  }

  Future<void> _createFolder() async {
    // 关键修改：直接在公共路径上创建目录
    Directory folder = Directory(_folderPath);
    if (!await folder.exists()) {
      try {
        await folder.create(recursive: true);
      } catch (e) {
        // 如果因为权限问题创建失败，可以给用户一个提示
        print('创建文件夹失败: $e');
        _showDialog('创建 "8fu" 文件夹失败，请检查应用的存储权限并重试。');
      }
    }
  }

  // ... _loadAudioFiles 和其他方法保持不变 ...

  Future<void> _loadAudioFiles() async {
    if (_folderPath.isNotEmpty) {
      Directory folder = Directory(_folderPath);
      if (await folder.exists()) {
        // Use recursive: true to search in subdirectories.
        List<FileSystemEntity> entities = await folder
            .list(recursive: true)
            .toList();

        // Filter for files with .mp3 or .wav extensions.
        _audioFiles = entities
            .where(
              (entity) =>
                  entity is File &&
                  (entity.path.endsWith('.mp3') ||
                      entity.path.endsWith('.wav')),
            )
            .map((entity) => entity as File)
            .toList();

        // Sort by filename assuming filenames are like 1.mp3, 2.mp3, etc.
        _audioFiles.sort(
          (a, b) => int.parse(
            a.path.split('/').last.split('.').first,
          ).compareTo(int.parse(b.path.split('/').last.split('.').first)),
        );

        setState(() {}); // Update the UI
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
    int prevIndex =
        (_currentIndex - 1 + _audioFiles.length) % _audioFiles.length;
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
                    ElevatedButton(onPressed: _nextAudio, child: Text('Next')),
                    ElevatedButton(
                      onPressed: _isPlaying
                          ? _pauseAudio
                          : () => _playAudio(_currentIndex),
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
