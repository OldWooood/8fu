import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 定义循环模式的枚举
enum LoopMode { list, single }

void main() async {
  // 在启动 App 前初始化 Hive
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  // 打开一个用于存储音频路径列表的 "盒子"
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
  bool _isPlaying = false;
  LoopMode _loopMode = LoopMode.list; // 使用枚举替代布尔值，默认为列表循环
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
        if (_duration.inMilliseconds > 0) {
          _progress =
              p.inMilliseconds.toDouble() / _duration.inMilliseconds.toDouble();
        } else {
          _progress = 0.0;
        }
      });
    });
    _audioPlayer.onPlayerComplete.listen((event) {
      // 根据循环模式决定行为
      if (_loopMode == LoopMode.single) {
        _playAudio(_currentIndex); // 单曲循环
      } else {
        _nextAudio(); // 列表循环（自动播放下一首）
      }
    });
  }

  Future<void> _initApp() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    // 恢复上次的循环模式
    String? savedLoopMode = prefs.getString('loop_mode');
    if (savedLoopMode == LoopMode.single.name) {
      _loopMode = LoopMode.single;
    } else {
      _loopMode = LoopMode.list;
    }

    _firstLaunch = prefs.getBool('first_launch') ?? true;
    _folderPath = '/storage/emulated/0/8fu';

    await _requestPermissions();
    if (_firstLaunch) {
      await _createFolder();
      prefs.setBool('first_launch', false);
      _showDialog('请将您的音频文件放置在手机根目录下的 "8fu" 文件夹中。');
    }

    await _loadAudioFiles();

    // 加载文件后，恢复上次播放的曲目状态
    int lastIndex = prefs.getInt('last_index') ?? 0;
    if (_audioFiles.isNotEmpty &&
        lastIndex >= 0 &&
        lastIndex < _audioFiles.length) {
      setState(() {
        _currentIndex = lastIndex;
        final fileName = _audioFiles[lastIndex].uri.pathSegments.last;
        final dotIndex = fileName.lastIndexOf('.');
        _currentAudioName = (dotIndex != -1)
            ? fileName.substring(0, dotIndex)
            : fileName;
      });
    }
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      final deviceInfo = await DeviceInfoPlugin().androidInfo;
      PermissionStatus status;
      if (deviceInfo.version.sdkInt >= 30) {
        status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) {
          await _showPermissionDialog(
            '''为了在安卓11及以上版本正常读写文件，应用需要“所有文件访问权限”。
点击“去开启”后，请在新页面中找到并打开此应用的开关，然后返回。''',
            () async {
              await Permission.manageExternalStorage.request();
              if (!mounted) return;
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
    Directory folder = Directory(_folderPath);
    if (!await folder.exists()) {
      try {
        await folder.create(recursive: true);
      } catch (e) {
        _showDialog('创建 "8fu" 文件夹失败，请检查应用的存储权限并重试。');
      }
    }
  }

  Future<void> _loadAudioFiles() async {
    final audioBox = Hive.box<List<String>>('audioCache');
    List<String>? cachedPaths = audioBox.get('audio_paths');

    // 1. 尝试从 Hive 缓存加载
    if (cachedPaths != null && cachedPaths.isNotEmpty) {
      List<File> cachedFiles = cachedPaths.map((path) => File(path)).toList();
      // 快速验证第一个文件是否存在，作为缓存是否有效的简单判断
      if (await cachedFiles.first.exists()) {
        setState(() {
          _audioFiles = cachedFiles;
        });
        return;
      } else {
        // 如果缓存失效，则删除
        await audioBox.delete('audio_paths');
      }
    }

    // 2. 如果缓存不存在或无效，则从磁盘扫描
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
              .where(
                (entity) =>
                    entity is File &&
                    (entity.path.endsWith('.mp3') ||
                        entity.path.endsWith('.wav')),
              )
              .cast<File>()
              .toList();
          audioFilesInDir.sort((a, b) => a.path.compareTo(b.path));
          allAudioFiles.addAll(audioFilesInDir);
        }

        setState(() {
          _audioFiles = allAudioFiles;
        });

        // 3. 将新的列表写入 Hive 缓存
        if (allAudioFiles.isNotEmpty) {
          List<String> pathsToCache = allAudioFiles.map((f) => f.path).toList();
          await audioBox.put('audio_paths', pathsToCache);
        }
      } catch (e) {
        _showDialog('加载音频文件失败。请检查 "8fu" 文件夹的子文件夹结构和权限。');
      }
    } else {
      _showDialog('根目录 "$_folderPath" 不存在。');
    }
  }

  void _playAudio(int index) async {
    if (index >= 0 && index < _audioFiles.length) {
      _audioPlayer.play(DeviceFileSource(_audioFiles[index].path));

      final fileName = _audioFiles[index].uri.pathSegments.last;
      final dotIndex = fileName.lastIndexOf('.');
      final displayName = (dotIndex != -1)
          ? fileName.substring(0, dotIndex)
          : fileName;

      setState(() {
        _currentIndex = index;
        _currentAudioName = displayName;
        _isPlaying = true;
      });
      // 保存当前播放的曲目编号
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_index', index);
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

  void _toggleLoop() async {
    // 在两种模式间切换
    setState(() {
      if (_loopMode == LoopMode.list) {
        _loopMode = LoopMode.single;
      } else {
        _loopMode = LoopMode.list;
      }
    });
    // 保存选择的模式
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('loop_mode', _loopMode.name);
  }

  void _handleNumberInput(String number) {
    _inputNumber += number;
    setState(() {});

    _inputTimer?.cancel();
    _inputTimer = Timer(Duration(seconds: 2, milliseconds: 500), () {
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
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 16.0,
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // --- 歌曲标题 ---
                  Container(
                    height: 96, // 给予足够空间以容纳两行文本，防止布局跳动
                    alignment: Alignment.center,
                    child: Text(
                      _currentAudioName,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 24.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(height: 12.0),

                  // --- 曲目编号 ---
                  Text(
                    '曲目: ${_audioFiles.isEmpty ? 0 : _currentIndex + 1} / ${_audioFiles.length}',
                    style: TextStyle(
                      fontSize: 16.0,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  SizedBox(height: 24.0),

                  // --- 数字输入显示区 ---
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 10.0,
                      horizontal: 12.0,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withAlpha(26),
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    child: Text(
                      _inputNumber,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22.0,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 3.0,
                        color: Theme.of(context).primaryColorDark,
                      ),
                    ),
                  ),
                  SizedBox(height: 24.0),

                  // --- 播放进度条 ---
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: _progress,
                      minHeight: 8.0,
                      backgroundColor: Colors.grey.shade300,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: ElevatedButtonTheme(
                    data: ElevatedButtonThemeData(
                      style: ButtonStyle(
                        textStyle: WidgetStateProperty.all(
                          const TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 64,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _toggleLoop,
                                  child: Text(
                                    _loopMode == LoopMode.list
                                        ? '列表循环'
                                        : '单曲循环',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _isPlaying
                                      ? _pauseAudio
                                      : () => _playAudio(_currentIndex),
                                  child: Text(_isPlaying ? '暂停' : '播放'),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 64,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _previousAudio,
                                  child: const Text('上一首歌'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _nextAudio,
                                  child: const Text('下一首歌'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
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
