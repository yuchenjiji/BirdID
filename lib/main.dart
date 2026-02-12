import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:dynamic_color/dynamic_color.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:intl/intl.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

// ===========================================================================
// [SECTION] DEBUG LOGGER - 你的“飞行记录仪”
// ===========================================================================

class DebugLogger {
  static final ValueNotifier<List<String>> logs =
      ValueNotifier<List<String>>([]);

  static void log(String message) {
    final time = DateFormat('HH:mm:ss').format(DateTime.now());
    debugPrint("[$time] $message");
    List<String> current = List.from(logs.value);
    if (current.length > 100) current.removeLast();
    logs.value = ["[$time] $message", ...current];
  }
}

// ===========================================================================
// [SECTION] MODELS - 数据模型
// ===========================================================================

class BirdRecord {
  final String id;
  final String commonName;
  final String scientificName;
  final double score;
  final DateTime timestamp;
  String? description;
  String? imageUrl;

  BirdRecord({
    required this.id,
    required this.commonName,
    required this.scientificName,
    required this.score,
    required this.timestamp,
    this.description,
    this.imageUrl,
  });

  // 转为 JSON (用于存入 Azure)
  Map<String, dynamic> toJson() => {
        'id': id,
        'commonName': commonName,
        'scientificName': scientificName,
        'score': score,
        'timestamp': timestamp.toIso8601String(),
        'description': description,
        'imageUrl': imageUrl,
      };

  // 从 JSON 恢复
  factory BirdRecord.fromJson(Map<String, dynamic> json) => BirdRecord(
        id: json['id'],
        commonName: json['commonName'],
        scientificName: json['scientific_name'] ?? json['scientificName'],
        score: (json['score'] ?? json['confidence'] ?? 0.0).toDouble(),
        timestamp: DateTime.parse(json['timestamp']),
        description: json['description'],
        imageUrl: json['imageUrl'],
      );
}

class BirdAppData extends ChangeNotifier {
  List<BirdRecord> _history = [];
  List<BirdRecord> get history => _history;
  String? _uid;
  String? get userId => _uid; // 暴露给 UI 显示

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 1. 尝试从本地恢复 ID
    _uid = prefs.getString('user_id');

    // 2. 如果本地没 ID（说明是第一次运行或刚清除了数据），尝试获取硬件 ID
    if (_uid == null) {
      if (kIsWeb) {
        // Web 平台：使用时间戳生成唯一 ID
        _uid = "web_${DateTime.now().millisecondsSinceEpoch}";
      } else {
        try {
          final deviceInfo = DeviceInfoPlugin();
          if (Platform.isAndroid) {
            final androidInfo = await deviceInfo.androidInfo;
            _uid = "bird_${androidInfo.id}"; // 使用安卓系统唯一 ID
          } else if (Platform.isIOS) {
            final iosInfo = await deviceInfo.iosInfo;
            _uid = "bird_${iosInfo.identifierForVendor}";
          } else {
            _uid = "u_${DateTime.now().millisecondsSinceEpoch}";
          }
        } catch (e) {
          _uid = "u_${DateTime.now().millisecondsSinceEpoch}";
        }
      }
      await prefs.setString('user_id', _uid!);
    }

    // 3. 先加载本地缓存（离线可用）
    final local = prefs.getString('history_cache');
    if (local != null) {
      _history = (jsonDecode(local) as List).map((e) => BirdRecord.fromJson(e)).toList();
      notifyListeners();
    }

    // 4. 核心：从云端强制同步（这步解决了清除数据后的恢复问题）
    final cloud = await AzureService().fetchHistoryFromCloud(_uid!);
    if (cloud.isNotEmpty) {
      _history = cloud;
      _saveLocal(); // 同步到本地
      notifyListeners();
    }
  }

  // 手动恢复 ID 的方法（用于换手机或强力找回）
  Future<void> recoverAccount(String newId) async {
    final prefs = await SharedPreferences.getInstance();
    _uid = newId;
    await prefs.setString('user_id', _uid!);
    
    // 立即从云端拉取新 ID 的数据
    final cloud = await AzureService().fetchHistoryFromCloud(_uid!);
    _history = cloud;
    _saveLocal();
    notifyListeners();
  }

  void _saveLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'history_cache', jsonEncode(_history.map((e) => e.toJson()).toList()));
  }

  void addRecord(BirdRecord r) {
    _history.insert(0, r);
    _saveLocal();
    AzureService().syncHistoryToCloud(_uid!, _history); // 自动推送到云端
    notifyListeners();
  }

  void clearHistory() {
    _history.clear();
    _saveLocal();
    AzureService().syncHistoryToCloud(_uid!, _history);
    notifyListeners();
  }
}

final appData = BirdAppData();

// ===========================================================================
// [SECTION] APPWRITE SERVICE - APK 下载链接管理
// ===========================================================================
class AppwriteService {
  // TODO: 替换为你的 Appwrite 配置
  static const String endpoint = "https://cloud.appwrite.io/v1";
  static const String projectId = "YOUR_PROJECT_ID"; // 替换为你的 Project ID
  static const String functionId = "YOUR_FUNCTION_ID"; // 替换为你的 Function ID
  
  /// 获取最新 APK 下载链接
  static Future<Map<String, dynamic>?> getLatestApkUrl() async {
    try {
      final url = Uri.parse('$endpoint/functions/$functionId/executions');
      
      final response = await http.post(
        url,
        headers: {
          'X-Appwrite-Project': projectId,
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // Appwrite function 执行是异步的，需要等待完成
        final executionId = data['\$id'];
        
        // 轮询获取执行结果（最多等待10秒）
        for (int i = 0; i < 20; i++) {
          await Future.delayed(const Duration(milliseconds: 500));
          
          final resultUrl = Uri.parse('$endpoint/functions/$functionId/executions/$executionId');
          final resultResponse = await http.get(
            resultUrl,
            headers: {'X-Appwrite-Project': projectId},
          );
          
          if (resultResponse.statusCode == 200) {
            final resultData = jsonDecode(resultResponse.body);
            
            if (resultData['status'] == 'completed') {
              final responseBody = jsonDecode(resultData['responseBody']);
              
              if (responseBody['success'] == true) {
                return responseBody['data'];
              } else {
                debugPrint('Appwrite function error: ${responseBody['error']}');
                return null;
              }
            } else if (resultData['status'] == 'failed') {
              debugPrint('Appwrite function execution failed');
              return null;
            }
          }
        }
        
        debugPrint('Appwrite function execution timeout');
        return null;
      } else {
        debugPrint('Failed to trigger Appwrite function: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('Error fetching APK URL from Appwrite: $e');
      return null;
    }
  }
  
  /// 带缓存的获取APK链接（避免频繁请求）
  static String? _cachedUrl;
  static DateTime? _cacheTime;
  static const Duration _cacheDuration = Duration(minutes: 5);
  
  static Future<String?> getLatestApkUrlCached() async {
    // 检查缓存是否有效
    if (_cachedUrl != null && 
        _cacheTime != null && 
        DateTime.now().difference(_cacheTime!) < _cacheDuration) {
      return _cachedUrl;
    }
    
    // 从 Appwrite 获取
    final result = await getLatestApkUrl();
    if (result != null && result['downloadUrl'] != null) {
      _cachedUrl = result['downloadUrl'];
      _cacheTime = DateTime.now();
      return _cachedUrl;
    }
    
    // 失败时返回备用链接（旧的硬编码链接）
    return "https://laow.blob.core.windows.net/birdid-apk/BirdID_1.0.0+1_20260212_012811.apk";
  }
}

// ===========================================================================
// [SECTION] AZURE SERVICE - 专门负责微软云同步
// ===========================================================================
class AzureService {
  // 使用和 ApiService 一样的基础地址
  static const String baseUrl = "https://oldweng-birdnet.hf.space";
  final Dio _dio = Dio();

  // A. 上传历史记录 (PUT)
  Future<void> syncHistoryToCloud(String uid, List<BirdRecord> history) async {
    try {
      // 1. 找后端要一张“写权限”的票
      final urlRes = await _dio.get("$baseUrl/generate_history_url", 
          queryParameters: {"user_id": uid, "mode": "w"});
      
      final uploadUrl = urlRes.data['url'];
      final body = jsonEncode(history.map((e) => e.toJson()).toList());
      
      // 2. 直传 Azure Blob
      await _dio.put(
        uploadUrl, 
        data: body, 
        options: Options(headers: {"x-ms-blob-type": "BlockBlob"})
      );
      DebugLogger.log("Azure Sync: Success");
    } catch (e) {
      DebugLogger.log("Azure Sync Failed: $e");
    }
  }

  // B. 下载历史记录 (GET)
  Future<List<BirdRecord>> fetchHistoryFromCloud(String uid) async {
    try {
      // 1. 找后端要一张“读权限”的票
      final urlRes = await _dio.get("$baseUrl/generate_history_url", 
          queryParameters: {"user_id": uid, "mode": "r"});
      
      // 2. 从 Azure 下载 JSON
      final res = await _dio.get(urlRes.data['url']);
      final List raw = res.data is String ? jsonDecode(res.data) : res.data;
      
      return raw.map((e) => BirdRecord.fromJson(e)).toList();
    } catch (_) {
      return []; // 如果云端没文件，就返回空列表
    }
  }
}

// ===========================================================================
// [SECTION] API SERVICE - 后端通信（精准适配你的 JSON 日志）
// ===========================================================================

class ApiService {
  // 定义基础地址
  static const String baseUrl = "https://oldweng-birdnet.hf.space";

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 45),
    receiveTimeout: const Duration(seconds: 45),
  ));

  Future<List<BirdRecord>> identifyBird(
      String filePath, Function(String) onProgress) async {
    try {
      String fileName = filePath.split('/').last;
      DebugLogger.log("Preparing to upload: $fileName");

      FormData formData = FormData.fromMap({
        "file": await MultipartFile.fromFile(filePath, filename: fileName),
      });

      onProgress("Uploading...");

      // 注意这里：我们将 baseUrl 拼接上 /analyze
      final response = await _dio.post(
        "$baseUrl/analyze",
        data: formData,
        onSendProgress: (sent, total) {
          if (total > 0) {
            int progress = ((sent / total) * 100).toInt();
            onProgress("Uploading: $progress%");
          }
        },
      );

      DebugLogger.log("Server Response Status: ${response.statusCode}");
      DebugLogger.log("Raw JSON: ${response.data}");

      onProgress("AI Analyzing...");

      return _parseResults(response.data);
    } on DioException catch (de) {
      DebugLogger.log("Dio Error: ${de.type} - ${de.message}");
      rethrow;
    } catch (e) {
      DebugLogger.log("Identification Failed: $e");
      rethrow;
    }
  }

  // Web 版本：使用字节数据
  Future<List<BirdRecord>> identifyBirdWeb(
      List<int> bytes, String filename, Function(String) onProgress) async {
    try {
      DebugLogger.log("Preparing to upload: $filename (Web)");

      FormData formData = FormData.fromMap({
        "file": MultipartFile.fromBytes(bytes, filename: filename),
      });

      onProgress("Uploading...");

      final response = await _dio.post(
        "$baseUrl/analyze",
        data: formData,
        onSendProgress: (sent, total) {
          if (total > 0) {
            int progress = ((sent / total) * 100).toInt();
            onProgress("Uploading: $progress%");
          }
        },
      );

      DebugLogger.log("Server Response Status: ${response.statusCode}");
      DebugLogger.log("Raw JSON: ${response.data}");

      onProgress("AI Analyzing...");

      return _parseResults(response.data);
    } on DioException catch (de) {
      DebugLogger.log("Dio Error: ${de.type} - ${de.message}");
      rethrow;
    } catch (e) {
      DebugLogger.log("Identification Failed: $e");
      rethrow;
    }
  }

  // 共用的结果解析方法
  List<BirdRecord> _parseResults(dynamic responseData) {
    // 【核心修正】：针对你的日志结构解析
    // 1. 获取最外层的 Map
    final Map<String, dynamic> data =
        responseData is Map ? Map<String, dynamic>.from(responseData) : {};
    // 2. 提取 'results' 列表
    final List resultsList = data['results'] ?? [];

    DebugLogger.log("Detected ${resultsList.length} segments in results.");

    return resultsList
        .map((p) => BirdRecord(
              // 使用时间戳+音频段起始时间作为 ID
              id: DateTime.now().millisecondsSinceEpoch.toString() +
                  (p['start_time'] ?? "").toString(),
              commonName: p['common_name'] ?? "Unknown",
              scientificName: p['scientific_name'] ?? "",
              // 你的后端字段名是 'confidence'
              score: (p['confidence'] ?? 0.0).toDouble(),
              timestamp: DateTime.now(),
            ))
        .toList();
  }

  Future<void> enrichWithWiki(BirdRecord record) async {
    if (record.scientificName.isEmpty) return;
    try {
      final query = Uri.encodeComponent(record.scientificName);
      final wikiUrl =
          "https://en.wikipedia.org/api/rest_v1/page/summary/$query";
      final response = await _dio.get(wikiUrl);

      if (response.statusCode == 200) {
        record.description = response.data['extract'];
        record.imageUrl = response.data['originalimage']?['source'] ??
            response.data['thumbnail']?['source'];
      }
    } catch (e) {
      DebugLogger.log("Wiki fetch failed: $e");
      record.description =
          "Identified via BirdNet. Wikipedia description unavailable.";
    }
  }
}
// ===========================================================================
// [SECTION] THEME PROVIDER - 主题管理
// ===========================================================================

class ThemeProvider with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  ThemeProvider() {
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final themeModeIndex = prefs.getInt('theme_mode') ?? 0;
    _themeMode = ThemeMode.values[themeModeIndex];
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_mode', mode.index);
  }
}

// ===========================================================================
// [SECTION] MAIN ENTRY & THEME
// ===========================================================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await appData.init();
  SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarColor: Colors.transparent));
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const BirdIdApp(),
    ),
  );
}

class BirdIdApp extends StatelessWidget {
  const BirdIdApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return DynamicColorBuilder(
          builder: (lightDynamic, darkDynamic) {
            const seed = Color(0xFF006d38);
            final light = lightDynamic ?? ColorScheme.fromSeed(seedColor: seed);
            final dark = darkDynamic ??
                ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);

            return MaterialApp(
              title: 'Bird ID',
              themeMode: themeProvider.themeMode,
              theme: ThemeData(
                colorScheme: light,
                useMaterial3: true,
                fontFamily: 'Roboto',
                cardTheme: CardThemeData(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
                  clipBehavior: Clip.antiAlias,
                ),
              ),
              darkTheme: ThemeData(colorScheme: dark, useMaterial3: true),
              home: const MainNavigationWrapper(),
              debugShowCheckedModeBanner: false,
            );
          },
        );
      },
    );
  }
}

// ===========================================================================
// [SECTION] NAVIGATION
// ===========================================================================

class MainNavigationWrapper extends StatefulWidget {
  const MainNavigationWrapper({super.key});
  @override
  State<MainNavigationWrapper> createState() => _MainNavigationWrapperState();
}

class _MainNavigationWrapperState extends State<MainNavigationWrapper> {
  int _currentIndex = 0;
  final _screens = [const HomeScreen(), const SettingsScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_filled),
              label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings'),
        ],
      ),
    );
  }
}

// ===========================================================================
// [SECTION] SCREEN: HOME
// ===========================================================================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiService _api = ApiService();
  bool _isProcessing = false;
  String _statusMessage = "Analyzing...";
  final AudioRecorder _recorder = AudioRecorder();
  // 处理文件上传识别
  Future<void> _handleIdentification() async {
    // 权限处理：仅在移动端
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final info = await DeviceInfoPlugin().androidInfo;
        if (info.version.sdkInt >= 33) {
          await Permission.audio.request();
        } else {
          await Permission.storage.request();
        }
      } catch (e) {
        DebugLogger.log("Permission request failed: $e");
      }
    }

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'm4a', 'flac', 'ogg'],
        withData: kIsWeb, // Web 需要读取文件数据
      );
      if (result == null) return;

      // Web 和移动端路径处理不同
      if (kIsWeb) {
        if (result.files.single.bytes != null) {
          _processAudioFileWeb(result.files.single.bytes!, result.files.single.name);
        }
      } else {
        if (result.files.single.path != null) {
          _processAudioFile(result.files.single.path!);
        }
      }
    } catch (e) {
      _error("File selection failed: $e");
    }
  }

  // 真正的核心分析逻辑 (移动端使用文件路径)
  Future<void> _processAudioFile(String path) async {
    setState(() {
      _isProcessing = true;
      _statusMessage = "Preparing...";
    });

    try {
      final predictions = await _api.identifyBird(
        path,
        (msg) => setState(() => _statusMessage = msg),
      );

      if (predictions.isNotEmpty) {
        final topMatch = predictions.first;
        await _api.enrichWithWiki(topMatch);
        appData.addRecord(topMatch);
        if (mounted) {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => ResultDetailScreen(record: topMatch)));
        }
      } else {
        if (mounted) _error("AI could not detect any birds in this clip.");
      }
    } catch (e) {
      _error("Analysis Failed. Check system logs.");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // Web 端使用字节数据
  Future<void> _processAudioFileWeb(List<int> bytes, String filename) async {
    setState(() {
      _isProcessing = true;
      _statusMessage = "Preparing...";
    });

    try {
      final predictions = await _api.identifyBirdWeb(
        bytes,
        filename,
        (msg) => setState(() => _statusMessage = msg),
      );

      if (predictions.isNotEmpty) {
        final topMatch = predictions.first;
        await _api.enrichWithWiki(topMatch);
        appData.addRecord(topMatch);
        if (mounted) {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => ResultDetailScreen(record: topMatch)));
        }
      } else {
        if (mounted) _error("AI could not detect any birds in this clip.");
      }
    } catch (e) {
      _error("Analysis Failed: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // 弹出选择菜单
  void _showIdentifyMenu() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 仅在移动端显示录音选项
          if (!kIsWeb)
            ListTile(
              leading: const Icon(Icons.mic, color: Colors.red),
              title: const Text("Record Audio"),
              onTap: () {
                Navigator.pop(ctx);
                _startLiveRecord();
              },
            ),
          ListTile(
            leading: const Icon(Icons.upload_file, color: Colors.blue),
            title: const Text("Upload File"),
            onTap: () {
              Navigator.pop(ctx);
              _handleIdentification();
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // 录音具体逻辑 (仅移动端)
  Future<void> _startLiveRecord() async {
    if (kIsWeb) {
      _error("Recording is not supported on web. Please upload an audio file.");
      return;
    }
    
    if (await _recorder.hasPermission()) {
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/live_rec.m4a';
      await _recorder.start(const RecordConfig(), path: path);

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text("Recording..."),
          content: const LinearProgressIndicator(),
          actions: [
            TextButton(
                onPressed: () async {
                  final recPath = await _recorder.stop();
                  Navigator.pop(ctx);
                  if (recPath != null) {
                    // 录音完了，也调用统一的分析方法
                    _processAudioFile(recPath);
                  }
                },
                child: const Text("Stop & Identify")),
          ],
        ),
      );
    }
  }

  void _error(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      body: ListenableBuilder(
        listenable: appData,
        builder: (context, _) {
          return CustomScrollView(
            slivers: [
              SliverAppBar.large(
                title: const Text("Bird ID"),
                backgroundColor: colors.surface,
                scrolledUnderElevation: 0,
              ),
              if (appData.history.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.waves_rounded,
                            size: 80,
                            color: colors.primary.withValues(alpha: 0.2)),
                        const SizedBox(height: 16),
                        const Text("No records found",
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        const Text("Identify bird sounds to see them here."),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) =>
                          _buildHistoryCard(context, appData.history[index]),
                      childCount: appData.history.length,
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isProcessing ? null : _showIdentifyMenu,
        icon: _isProcessing
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.mic),
        label: Text(_isProcessing ? _statusMessage : "Identify Bird"),
      ),
    );
  }

  Widget _buildHistoryCard(BuildContext context, BirdRecord record) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: colors.surfaceContainerLow,
      child: ListTile(
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => ResultDetailScreen(record: record))),
        contentPadding: const EdgeInsets.all(12),
        leading: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(12)),
          child: Icon(Icons.graphic_eq, color: colors.onPrimaryContainer),
        ),
        title: Text(record.commonName,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(DateFormat('MMM dd, hh:mm a').format(record.timestamp)),
        trailing: Text("${(record.score * 100).toStringAsFixed(0)}%",
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colors.primary,
                fontSize: 16)),
      ),
    );
  }
}

// ===========================================================================
// [SECTION] SCREEN: RESULT DETAIL
// ===========================================================================

class ResultDetailScreen extends StatelessWidget {
  final BirdRecord record;
  const ResultDetailScreen({super.key, required this.record});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
          title: const Text("Identification Results"), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text("Top match found",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text("Based on AI audio analysis",
                style: TextStyle(color: colors.onSurfaceVariant)),
            const SizedBox(height: 32),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(32)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      Container(
                        height: 300,
                        width: double.infinity,
                        color: colors.surfaceContainerHighest,
                        child: record.imageUrl != null
                            ? Image.network(record.imageUrl!, fit: BoxFit.cover)
                            : const Icon(Icons.image_not_supported, size: 100),
                      ),
                      Positioned(
                        top: 20,
                        right: 20,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(12)),
                          child: Text(
                              "${(record.score * 100).toStringAsFixed(0)}% Match",
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(record.commonName,
                                      style: const TextStyle(
                                          fontSize: 32,
                                          fontWeight: FontWeight.bold,
                                          height: 1.1)),
                                  const SizedBox(height: 8),
                                  Text(record.scientificName,
                                      style: TextStyle(
                                          fontSize: 18,
                                          fontStyle: FontStyle.italic,
                                          color: colors.onSurfaceVariant)),
                                ])),
                            const CircleAvatar(
                                radius: 28, child: Icon(Icons.volume_up)),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Text(
                            record.description ??
                                "Species biography loading from Wikipedia...",
                            style: const TextStyle(fontSize: 16, height: 1.6)),
                        const SizedBox(height: 32),
                        Center(
                          child: FilledButton.tonalIcon(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.mic),
                            label: const Text("Record Again"),
                          ),
                        )
                      ],
                    ),
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// [SECTION] SCREEN: SETTINGS (修复图标报错版)
// ===========================================================================

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large( // 注意：因为使用了变量 colors，这里去掉了 const
            title: const Text("Settings"),
            scrolledUnderElevation: 0,
            backgroundColor: colors.surface,
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _header("GENERAL", colors),
                _tile(
                  context,
                  Icons.history,
                  "Identification History",
                  "Clear all recorded data",
                  onTap: () => _askClear(context),
                ),
                _header("APPEARANCE", colors),
                _tile(
                  context,
                  Icons.palette_outlined,
                  "Theme",
                  "System Default",
                  onTap: () => _showThemePicker(context),
                ),
                _header("INFO", colors),
                _tile(
                  context,
                  Icons.info_outline,
                  "About Bird ID",
                  "Version 1.0.0",
                  onTap: () => _showAboutDialog(context),
                ),
                
                // ✨ 新增板块：DOWNLOAD APK (仅 Web) ✨
                if (kIsWeb) ...[
                  _header("DOWNLOAD", colors),
                  _tile(
                    context,
                    Icons.android,
                    "Download Android App",
                    "Get the latest APK version",
                    onTap: () => _showDownloadDialog(context),
                  ),
                ],

                // ✨ 新增板块：DATA SYNC ✨
                _header("DATA SYNC", colors),
                _tile(
                  context, 
                  Icons.sync_lock, 
                  "Cloud Sync ID", 
                  appData.userId ?? "Not initialized",
                  onTap: () => _showIdManagement(context),
                ),

                _header("DEBUG", colors),
                _tile(
                  context,
                  Icons.terminal,
                  "View System Logs",
                  "Inspect raw data communication",
                  onTap: () => _showLogs(context),
                ),
                const SizedBox(height: 60),
                Center(
                  child: Opacity(
                    opacity: 0.4,
                    child: Column(
                      children: [
                        Text(
                          "Bird ID • AI Bird Identification",
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: colors.onSurface),
                        ),
                        Text(
                          "Made with nature in mind",
                          style:
                              TextStyle(fontSize: 12, color: colors.onSurface),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // --- 新增：ID 管理弹窗方法 ---
  void _showIdManagement(BuildContext context) {
    final TextEditingController controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Data Recovery"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Your current ID (Save this to recover data):", style: TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            SelectableText(
              appData.userId ?? "", 
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)
            ),
            const Divider(height: 32),
            const Text("To recover data from another device, enter ID below:", style: TextStyle(fontSize: 12)),
            TextField(
              controller: controller,
              decoration: const InputDecoration(hintText: "Enter old Sync ID"),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                await appData.recoverAccount(controller.text);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Data recovered!")));
              }
            }, 
            child: const Text("Recover Now")
          ),
        ],
      ),
    );
  }

  Widget _header(String t, ColorScheme c) => Padding(
        padding: const EdgeInsets.only(left: 12, top: 24, bottom: 8),
        child: Text(
          t,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: c.primary,
              letterSpacing: 1.1),
        ),
      );

  Widget _tile(BuildContext context, IconData i, String t, String s,
      {VoidCallback? onTap}) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: colors.surfaceContainerLow,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  // 修复：使用 withValues 替代 withOpacity (适配新版Flutter)
                  color: colors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(i, color: colors.primary, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(s,
                        style: TextStyle(
                            fontSize: 13, color: colors.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: colors.outline),
            ],
          ),
        ),
      ),
    );
  }

  // --- 交互逻辑 (修复了图标报错) ---

  void _showThemePicker(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text("Choose Theme"),
        children: [
          SimpleDialogOption(
            onPressed: () {
              themeProvider.setThemeMode(ThemeMode.light);
              Navigator.pop(ctx);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Light Mode"),
                  if (themeProvider.themeMode == ThemeMode.light)
                    const Icon(Icons.check, color: Colors.green, size: 20),
                ],
              ),
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              themeProvider.setThemeMode(ThemeMode.dark);
              Navigator.pop(ctx);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Dark Mode"),
                  if (themeProvider.themeMode == ThemeMode.dark)
                    const Icon(Icons.check, color: Colors.green, size: 20),
                ],
              ),
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              themeProvider.setThemeMode(ThemeMode.system);
              Navigator.pop(ctx);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("System Default"),
                  if (themeProvider.themeMode == ThemeMode.system)
                    const Icon(Icons.check, color: Colors.green, size: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: "Bird ID",
      applicationVersion: "1.0.0",
      children: [
        const Text(
            "Bird ID uses advanced AI to identify bird species from audio recordings."),
        const SizedBox(height: 10),
        const Text("Powered by BirdNET-Analyzer and Wikipedia API."),
        const SizedBox(height: 10),
        const Text("© 2026 Nature Tech Inc."),
      ],
    );
  }

  void _showDownloadDialog(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.android, color: colors.primary),
            const SizedBox(width: 12),
            const Text("Download Android App"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Get the native Android experience with:",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _downloadFeature(Icons.speed, "Better performance"),
            _downloadFeature(Icons.offline_bolt, "Offline support"),
            _downloadFeature(Icons.notifications, "Push notifications"),
            _downloadFeature(Icons.mic, "Native audio recording"),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Latest Version",
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "BirdID v1.0.0",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "APK files are hosted on Azure Blob Storage",
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _downloadApk(context);
            },
            icon: const Icon(Icons.download),
            label: const Text("Download APK"),
          ),
        ],
      ),
    );
  }

  Widget _downloadFeature(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.green),
          const SizedBox(width: 8),
          Text(text),
        ],
      ),
    );
  }

  void _downloadApk(BuildContext context) async {
    // 显示加载状态
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Fetching latest APK link..."),
          duration: Duration(seconds: 2),
        ),
      );
    }
    
    // 从 Appwrite 获取最新下载链接
    final downloadUrl = await AppwriteService.getLatestApkUrlCached();
    
    if (downloadUrl == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Failed to fetch download link. Please try again."),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    
    if (kIsWeb) {
      // 尝试在新标签页打开下载链接
      final Uri url = Uri.parse(downloadUrl);
      
      try {
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Download started! Check your browser downloads."),
                duration: Duration(seconds: 3),
              ),
            );
          }
        } else {
          // 如果无法打开，显示复制链接对话框
          if (context.mounted) {
            _showDownloadLinkDialog(context, downloadUrl);
          }
        }
      } catch (e) {
        // 出错时显示复制链接对话框
        if (context.mounted) {
          _showDownloadLinkDialog(context, downloadUrl);
        }
      }
    }
  }

  void _showDownloadLinkDialog(BuildContext context, String downloadUrl) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Download Link"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Click the link below to download:"),
            const SizedBox(height: 12),
            SelectableText(
              downloadUrl,
              style: const TextStyle(
                color: Colors.blue,
                decoration: TextDecoration.underline,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "Or copy and paste this link in your browser.",
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Close"),
          ),
          FilledButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: downloadUrl));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Download link copied to clipboard!")),
              );
            },
            child: const Text("Copy Link"),
          ),
        ],
      ),
    );
  }

  void _askClear(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Clear History?"),
        content: const Text(
            "This action will permanently delete all your identification records."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              appData.clearHistory();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("History cleared")));
            },
            child: const Text("Clear All", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showLogs(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("System Logs",
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  IconButton(
                    onPressed: () => DebugLogger.logs.value = [],
                    icon: const Icon(Icons.delete_sweep_outlined),
                    tooltip: "Clear Logs",
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: ValueListenableBuilder<List<String>>(
                  valueListenable: DebugLogger.logs,
                  builder: (context, logList, _) {
                    if (logList.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.bug_report_outlined,
                                size: 48,
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant),
                            const SizedBox(height: 12),
                            const Text("No logs generated yet."),
                          ],
                        ),
                      );
                    }
                    return ListView.builder(
                      controller: scrollController,
                      itemCount: logList.length,
                      itemBuilder: (context, i) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          logList[i],
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 11),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
