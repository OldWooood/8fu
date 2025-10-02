import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox<List<String>>('audioCache');
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '八福播放器',
      theme: ThemeData(primarySwatch: Colors.blue),
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
  String _currentAudioName = '当前无歌曲播放';
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
        if (_duration.inMilliseconds > 0) {
          _progress =
              p.inMilliseconds.toDouble() / _duration.inMilliseconds.toDouble();
        } else {
          _progress = 0.0;
        }
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
    _folderPath = '/storage/emulated/0/8fu';

    await _requestPermissions();
    if (_firstLaunch) {
      await _createFolder();
      prefs.setBool('first_launch', false);
      _showDialog('请将您的音频文件放置在手机根目录下的 "8fu" 文件夹中。');
    }

    await _loadAudioFiles();
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      final deviceInfo = await DeviceInfoPlugin().androidInfo;
      PermissionStatus status;
      if (deviceInfo.version.sdkInt >= 30) {
        status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) {
          await _showPermissionDialog(
            '为了在安卓11及以上版本正常读写文件，应用需要“所有文件访问权限”。\n\n点击“去开启”后，请在新页面中找到并打开此应用的开关，然后返回。',
            () async {
              await Permission.manageExternalStorage.request();
              Navigator.pop(context);
            },
          );
        }
      } else {
        status = await Permission.storage.status;
        if (!status.isGranted) {
          await Permission.storage.request();
        }
      }
    }
  }

  Future<void> _showPermissionDialog(
      String content, VoidCallback onPressed) async {
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
    Directory folder = Directory(_folderPath);
    if (!await folder.exists()) {
      try {
        await folder.create(recursive: true);
      } catch (e) {
        print('创建文件夹失败: $e');
        _showDialog('创建 "8fu" 文件夹失败，请检查应用的存储权限并重试。');
      }
    }
  }

  Future<void> _loadAudioFiles() async {
    final audioBox = Hive.box<List<String>>('audioCache');
    List<String>? cachedPaths = audioBox.get('audio_paths');

    if (cachedPaths != null && cachedPaths.isNotEmpty) {
      List<File> cachedFiles = cachedPaths.map((path) => File(path)).toList();
      if (await cachedFiles.first.exists()) {
        setState(() {
          _audioFiles = cachedFiles;
        });
        print("Loaded ${_audioFiles.length} audio files from Hive cache.");
        return;
      } else {
        print("Hive cache is invalid, deleting.");
        await audioBox.delete('audio_paths');
      }
    }

    print("Hive cache not found or invalid. Scanning disk for audio files...");
    Directory rootFolder = Directory(_folderPath);
    if (await rootFolder.exists()) {
      final List<File> allAudioFiles = [];
      try {
        List<Directory> subdirectories = await rootFolder
            .list()
            .where((entity) => entity is Directory)
            .cast<Directory>()
            .toList();
        subdirectories.sort((a, b) => a.path.compareTo(b.path));

        for (final dir in subdirectories) {
          List<File> audioFilesInDir = await dir
              .list()
              .where((entity) =>
                  entity is File &&
                  (entity.path.endsWith('.mp3') || entity.path.endsWith('.wav')))
              .cast<File>()
              .toList();
          audioFilesInDir.sort((a, b) => a.path.compareTo(b.path));
          allAudioFiles.addAll(audioFilesInDir);
        }

        setState(() {
          _audioFiles = allAudioFiles;
        });

        if (allAudioFiles.isNotEmpty) {
          print("Found ${allAudioFiles.length} files. Updating Hive cache.");
          List<String> pathsToCache = allAudioFiles.map((f) => f.path).toList();
          await audioBox.put('audio_paths', pathsToCache);
        }
      } catch (e) {
        print('加载音频文件时出错: $e');
        _showDialog('加载音频文件失败。请检查 "8fu" 文件夹的子文件夹结构和权限。');
      }
    } else {
      _showDialog('根目录 "$_folderPath" 不存在。');
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
    if (_audioFiles.isEmpty) return;
    int nextIndex = (_currentIndex + 1) % _audioFiles.length;
    _playAudio(nextIndex);
  }

  void _previousAudio() {
    if (_audioFiles.isEmpty) return;
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
        _playAudio(index - 1);
      }
      _inputNumber = '';
      setState(() {});
    });
  }

  void _showDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('提示'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('好的'),
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
      appBar: AppBar(title: Text('八福播放器')),
      body: Column(
        children: [
          Expanded(
            flex: 1,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_currentAudioName),
                Text(
                    '曲目: ${_audioFiles.isEmpty ? 0 : _currentIndex + 1} / ${_audioFiles.length}'),
                if (_inputNumber.isNotEmpty) Text('输入: $_inputNumber'),
                LinearProgressIndicator(value: _progress),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _toggleLoop,
                          child: Text(
                            _isLooping ? '循环开启' : '循环关闭',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _previousAudio,
                          child: Text('上一首', style: TextStyle(fontSize: 16)),
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _nextAudio,
                          child: Text('下一首', style: TextStyle(fontSize: 16)),
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isPlaying
                              ? _pauseAudio
                              : () => _playAudio(_currentIndex),
                          child: Text(
                            _isPlaying ? '暂停' : '播放',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 5,
                    mainAxisSpacing: 8.0,
                    crossAxisSpacing: 8.0,
                    padding: const EdgeInsets.all(8.0),
                    children: List.generate(10, (index) {
                      return AspectRatio(
                        aspectRatio: 1,
                        child: ElevatedButton(
                          onPressed: () => _handleNumberInput(index.toString()),
                          child: Text(
                            index.toString(),
                            style: TextStyle(fontSize: 18),
                          ),
                        ),
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
