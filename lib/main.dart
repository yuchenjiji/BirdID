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
import 'package:google_fonts/google_fonts.dart';

// ===========================================================================
// [SECTION] DEBUG LOGGER
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
// [SECTION] MODELS
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'commonName': commonName,
        'scientificName': scientificName,
        'score': score,
        'timestamp': timestamp.toIso8601String(),
        'description': description,
        'imageUrl': imageUrl,
      };

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
  String? get userId => _uid;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _uid = prefs.getString('user_id');

    if (_uid == null) {
      if (kIsWeb) {
        _uid = "web_${DateTime.now().millisecondsSinceEpoch}";
      } else {
        try {
          final deviceInfo = DeviceInfoPlugin();
          if (Platform.isAndroid) {
            final androidInfo = await deviceInfo.androidInfo;
            _uid = "bird_${androidInfo.id}";
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

    final local = prefs.getString('history_cache');
    if (local != null) {
      _history = (jsonDecode(local) as List)
          .map((e) => BirdRecord.fromJson(e))
          .toList();
      notifyListeners();
    }

    final cloud = await AzureService().fetchHistoryFromCloud(_uid!);
    if (cloud.isNotEmpty) {
      _history = cloud;
      _saveLocal();
      notifyListeners();
    }
  }

  Future<void> recoverAccount(String newId) async {
    final prefs = await SharedPreferences.getInstance();
    _uid = newId;
    await prefs.setString('user_id', _uid!);
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
    if (_uid != null) AzureService().addRecordToCloud(_uid!, r);
    notifyListeners();
  }

  void clearHistory() {
    _history.clear();
    _saveLocal();
    if (_uid != null) AzureService().clearHistoryInCloud(_uid!);
    notifyListeners();
  }
}

final appData = BirdAppData();

// ===========================================================================
// [SECTION] SERVICES
// ===========================================================================

class CloudflareWorkerService {
  static const String workerUrl = "https://cdn.dont-click.me";

  static Future<Map<String, dynamic>?> getLatestApkUrl() async {
    try {
      final response = await http.get(Uri.parse(workerUrl));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) return data['data'];
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static String? _cachedUrl;
  static DateTime? _cacheTime;
  static const Duration _cacheDuration = Duration(minutes: 5);

  static Future<String?> getLatestApkUrlCached() async {
    if (_cachedUrl != null &&
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheDuration) {
      return _cachedUrl;
    }
    final result = await getLatestApkUrl();
    if (result != null && result['downloadUrl'] != null) {
      _cachedUrl = result['downloadUrl'];
      _cacheTime = DateTime.now();
      return _cachedUrl;
    }
    return null;
  }
}

class AzureService {
  // 替换为你的 Azure VM 公网 IP 或域名，端口默认 8000
  static const String baseUrl = "http://134.33.96.248:8000";

  final Dio _dio = Dio();

  /// 新增单条记录到 PostgreSQL
  Future<void> addRecordToCloud(String uid, BirdRecord record) async {
    try {
      final body = record.toJson()..['uid'] = uid;
      await _dio.post(
        "$baseUrl/history",
        data: jsonEncode(body),
        options: Options(headers: {"Content-Type": "application/json"}),
      );
      DebugLogger.log("Cloud Sync: record added");
    } catch (e) {
      DebugLogger.log("Cloud addRecord Failed: $e");
    }
  }

  /// 清除该用户在云端的所有记录
  Future<void> clearHistoryInCloud(String uid) async {
    try {
      await _dio.delete("$baseUrl/history", queryParameters: {"uid": uid});
      DebugLogger.log("Cloud Sync: history cleared");
    } catch (e) {
      DebugLogger.log("Cloud clearHistory Failed: $e");
    }
  }

  /// 拉取该用户所有记录
  Future<List<BirdRecord>> fetchHistoryFromCloud(String uid) async {
    try {
      final res = await _dio.get("$baseUrl/history", queryParameters: {"uid": uid});
      final List raw = res.data is String ? jsonDecode(res.data) : res.data;
      return raw.map((e) => BirdRecord.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  // 全量同步（清空后逐条插入，用于数据迁移等场景）
  Future<void> syncHistoryToCloud(String uid, List<BirdRecord> history) async {
    await clearHistoryInCloud(uid);
    for (final r in history) {
      await addRecordToCloud(uid, r);
    }
  }
}

class ApiService {
  static const String baseUrl = "https://oldweng-birdnet.hf.space";

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 45),
    receiveTimeout: const Duration(seconds: 45),
  ));

  Future<List<BirdRecord>> identifyBird(
      String filePath, Function(String) onProgress) async {
    try {
      String fileName = filePath.split('/').last;
      FormData formData = FormData.fromMap({
        "file": await MultipartFile.fromFile(filePath, filename: fileName),
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
      onProgress("AI Analyzing...");
      return _parseResults(response.data);
    } catch (e) {
      DebugLogger.log("Identification Failed: $e");
      rethrow;
    }
  }

  Future<List<BirdRecord>> identifyBirdWeb(
      List<int> bytes, String filename, Function(String) onProgress) async {
    try {
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
      onProgress("AI Analyzing...");
      return _parseResults(response.data);
    } catch (e) {
      DebugLogger.log("Identification Failed: $e");
      rethrow;
    }
  }

  List<BirdRecord> _parseResults(dynamic responseData) {
    final Map<String, dynamic> data =
        responseData is Map ? Map<String, dynamic>.from(responseData) : {};
    final List resultsList = data['results'] ?? [];
    return resultsList
        .map((p) => BirdRecord(
              id: DateTime.now().millisecondsSinceEpoch.toString() +
                  (p['start_time'] ?? "").toString(),
              commonName: p['common_name'] ?? "Unknown",
              scientificName: p['scientific_name'] ?? "",
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
      record.description =
          "Identified via BirdNet. Wikipedia description unavailable.";
    }
  }
}

// ===========================================================================
// [SECTION] THEME PROVIDER
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
// [SECTION] MAIN & MODERN THEME
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

            final lightBase = ColorScheme.fromSeed(seedColor: seed);
            final darkBase = ColorScheme.fromSeed(
                seedColor: seed, brightness: Brightness.dark);

            final light = lightDynamic?.harmonized() ?? lightBase;
            final dark = darkDynamic?.harmonized() ?? darkBase;

            ThemeData buildTheme(ColorScheme scheme) {
              return ThemeData(
                useMaterial3: true,
                colorScheme: scheme,
                textTheme: GoogleFonts.interTextTheme().copyWith(
                  displayLarge: GoogleFonts.lexend(fontWeight: FontWeight.bold),
                  displayMedium:
                      GoogleFonts.lexend(fontWeight: FontWeight.bold),
                  displaySmall: GoogleFonts.lexend(fontWeight: FontWeight.bold),
                  headlineLarge:
                      GoogleFonts.lexend(fontWeight: FontWeight.w600),
                  headlineMedium:
                      GoogleFonts.lexend(fontWeight: FontWeight.w600),
                  titleLarge: GoogleFonts.lexend(
                      fontWeight: FontWeight.w600, fontSize: 22),
                ),
                cardTheme: CardThemeData(
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  clipBehavior: Clip.antiAlias,
                  color: scheme.surfaceContainerLow,
                ),
                navigationBarTheme: NavigationBarThemeData(
                  labelTextStyle: WidgetStateProperty.all(
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),
                appBarTheme: AppBarTheme(
                  centerTitle: false,
                  scrolledUnderElevation: 0,
                  titleTextStyle: GoogleFonts.lexend(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
              );
            }

            return MaterialApp(
              title: 'Bird ID',
              themeMode: themeProvider.themeMode,
              theme: buildTheme(light),
              darkTheme: buildTheme(dark),
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
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Explore'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
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

  Future<void> _handleIdentification() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final info = await DeviceInfoPlugin().androidInfo;
        if (info.version.sdkInt >= 33) {
          await Permission.audio.request();
        } else {
          await Permission.storage.request();
        }
      } catch (_) {}
    }

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'm4a', 'flac', 'ogg'],
        withData: kIsWeb,
      );
      if (result == null) return;

      if (kIsWeb) {
        if (result.files.single.bytes != null) {
          _processAudioFileWeb(
              result.files.single.bytes!, result.files.single.name);
        }
      } else {
        if (result.files.single.path != null) {
          _processAudioFile(result.files.single.path!);
        }
      }
    } catch (e) {
      _error("Selection failed: $e");
    }
  }

  Future<void> _processAudioFile(String path) async {
    setState(() {
      _isProcessing = true;
      _statusMessage = "Preparing...";
    });
    try {
      final predictions = await _api.identifyBird(
          path, (msg) => setState(() => _statusMessage = msg));
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
        if (mounted) _error("No birds detected.");
      }
    } catch (e) {
      _error("Analysis Failed.");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _processAudioFileWeb(List<int> bytes, String filename) async {
    setState(() {
      _isProcessing = true;
      _statusMessage = "Preparing...";
    });
    try {
      final predictions = await _api.identifyBirdWeb(
          bytes, filename, (msg) => setState(() => _statusMessage = msg));
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
        if (mounted) _error("No birds detected.");
      }
    } catch (e) {
      _error("Analysis Failed.");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showIdentifyMenu() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!kIsWeb)
            ListTile(
              leading: const Icon(Icons.mic_rounded),
              title: const Text("Record Live Audio"),
              onTap: () {
                Navigator.pop(ctx);
                _startLiveRecord();
              },
            ),
          ListTile(
            leading: const Icon(Icons.audio_file_rounded),
            title: const Text("Upload Audio File"),
            onTap: () {
              Navigator.pop(ctx);
              _handleIdentification();
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _startLiveRecord() async {
    if (await _recorder.hasPermission()) {
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/live_rec.m4a';
      await _recorder.start(const RecordConfig(), path: path);

      if (mounted) {
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
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    if (recPath != null) _processAudioFile(recPath);
                  },
                  child: const Text("Stop & Identify")),
            ],
          ),
        );
      }
    }
  }

  void _error(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: ListenableBuilder(
        listenable: appData,
        builder: (context, _) {
          return CustomScrollView(
            slivers: [
              SliverAppBar.large(
                title: const Text("Bird ID"),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.history_rounded),
                    onPressed: () => _showLogs(context),
                  ),
                ],
              ),
              if (appData.history.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.eco_rounded,
                            size: 100,
                            color: colors.primary.withValues(alpha: 0.1)),
                        const SizedBox(height: 24),
                        Text("Ready for your first bird?",
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 8),
                        const Text(
                            "Tap the button below to start identifying."),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) =>
                          _buildHistoryCard(context, appData.history[index]),
                      childCount: appData.history.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isProcessing ? null : _showIdentifyMenu,
        icon: _isProcessing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.mic_none_rounded),
        label: Text(_isProcessing ? _statusMessage : "Listen Now"),
      ),
    );
  }

  Widget _buildHistoryCard(BuildContext context, BirdRecord record) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: InkWell(
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => ResultDetailScreen(record: record))),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Hero(
                  tag: 'img-${record.id}',
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: colors.secondaryContainer,
                      borderRadius: BorderRadius.circular(16),
                      image: record.imageUrl != null
                          ? DecorationImage(
                              image: NetworkImage(record.imageUrl!),
                              fit: BoxFit.cover)
                          : null,
                    ),
                    child: record.imageUrl == null
                        ? Icon(Icons.nature_rounded,
                            color: colors.onSecondaryContainer)
                        : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(record.commonName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text(
                          DateFormat('MMM dd • hh:mm a')
                              .format(record.timestamp),
                          style: TextStyle(
                              fontSize: 12, color: colors.onSurfaceVariant)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text("${(record.score * 100).toStringAsFixed(0)}%",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: colors.primary,
                            fontSize: 18)),
                    const Text("Match", style: TextStyle(fontSize: 10)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// [SECTION] SCREEN: RESULT DETAIL (沉浸式大图版)
// ===========================================================================

class ResultDetailScreen extends StatelessWidget {
  final BirdRecord record;
  const ResultDetailScreen({super.key, required this.record});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 400.0,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Hero(
                tag: 'img-${record.id}',
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (record.imageUrl != null)
                      Image.network(record.imageUrl!, fit: BoxFit.cover)
                    else
                      Container(
                          color: colors.surfaceContainerHighest,
                          child: Icon(Icons.nature_rounded,
                              size: 80, color: colors.primary)),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black45],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(record.commonName,
                                style:
                                    Theme.of(context).textTheme.displaySmall),
                            const SizedBox(height: 4),
                            Text(record.scientificName,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontStyle: FontStyle.italic,
                                      color: colors.primary,
                                    )),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                            "${(record.score * 100).toStringAsFixed(0)}%",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: colors.onPrimaryContainer)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 24),
                  Text("Species Description",
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Text(
                      record.description ??
                          "Species biography loading from Wikipedia...",
                      style: const TextStyle(fontSize: 16, height: 1.6)),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.mic_rounded),
                      label: const Text("Listen to Another"),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// [SECTION] SCREEN: SETTINGS
// ===========================================================================

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar.large(title: Text("Settings")),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildSection(context, "ACCOUNT & DATA", [
                  _buildTile(context, Icons.sync_rounded, "Cloud Sync ID",
                      appData.userId ?? "Initializing",
                      onTap: () => _showIdManagement(context)),
                  _buildTile(context, Icons.delete_forever_rounded,
                      "Clear History", "Wipe all local records",
                      onTap: () => _askClear(context), isDestructive: true),
                ]),
                _buildSection(context, "VISUALS", [
                  _buildTile(context, Icons.dark_mode_rounded, "Appearance",
                      "Modify app theme",
                      onTap: () => _showThemePicker(context)),
                ]),
                _buildSection(context, "RESOURCES", [
                  if (kIsWeb)
                    _buildTile(context, Icons.android_rounded, "Native App",
                        "Download Android APK",
                        onTap: () => _showDownloadDialog(context)),
                  _buildTile(context, Icons.help_outline_rounded,
                      "About Bird ID", "v1.0.0 • Nature Tech Inc.",
                      onTap: () => _showAboutDialog(context)),
                ]),
                const SizedBox(height: 100),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
      BuildContext context, String title, List<Widget> children) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, top: 24, bottom: 8),
          child: Text(title,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: colors.primary,
                  letterSpacing: 1.2)),
        ),
        ...children,
      ],
    );
  }

  Widget _buildTile(
      BuildContext context, IconData icon, String title, String subtitle,
      {VoidCallback? onTap, bool isDestructive = false}) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        leading:
            Icon(icon, color: isDestructive ? colors.error : colors.primary),
        title: Text(title,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDestructive ? colors.error : null)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 13)),
        trailing: const Icon(Icons.chevron_right_rounded, size: 20),
      ),
    );
  }

  void _showIdManagement(BuildContext context) {
    final TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Data Recovery"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Your Sync ID:", style: TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            SelectableText(appData.userId ?? "",
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.blue)),
            const Divider(height: 32),
            TextField(
                controller: controller,
                decoration:
                    const InputDecoration(labelText: "Enter recovery ID")),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          FilledButton(
              onPressed: () async {
                if (controller.text.isNotEmpty) {
                  await appData.recoverAccount(controller.text);
                  if (context.mounted) Navigator.pop(ctx);
                }
              },
              child: const Text("Recover")),
        ],
      ),
    );
  }

  void _showThemePicker(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _themeOption(context, "Light Mode", Icons.light_mode_rounded,
              ThemeMode.light, themeProvider),
          _themeOption(context, "Dark Mode", Icons.dark_mode_rounded,
              ThemeMode.dark, themeProvider),
          _themeOption(context, "System Default", Icons.brightness_auto_rounded,
              ThemeMode.system, themeProvider),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _themeOption(BuildContext context, String title, IconData icon,
      ThemeMode mode, ThemeProvider provider) {
    final selected = provider.themeMode == mode;
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: selected
          ? const Icon(Icons.check_circle_rounded, color: Colors.green)
          : null,
      onTap: () {
        provider.setThemeMode(mode);
        Navigator.pop(context);
      },
    );
  }

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: "Bird ID",
      applicationVersion: "1.0.0",
      applicationIcon:
          const Icon(Icons.eco_rounded, size: 40, color: Colors.green),
      children: [
        const Text(
            "Bird ID uses advanced AI to identify bird species from audio recordings."),
        const SizedBox(height: 10),
        const Text("Powered by BirdNET-Analyzer and Wikipedia API."),
      ],
    );
  }

  void _showDownloadDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Download Android App"),
        content: const Text(
            "Get the native experience with offline support and better performance."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          FilledButton(
              onPressed: () => _downloadApk(context),
              child: const Text("Download APK")),
        ],
      ),
    );
  }

  void _downloadApk(BuildContext context) async {
    final downloadUrl = await CloudflareWorkerService.getLatestApkUrlCached();
    if (downloadUrl != null) {
      launchUrl(Uri.parse(downloadUrl), mode: LaunchMode.externalApplication);
    }
  }

  void _askClear(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Clear History?"),
        content: const Text("This action cannot be undone."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          TextButton(
              onPressed: () {
                appData.clearHistory();
                Navigator.pop(ctx);
              },
              child:
                  const Text("Clear All", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }
}

void _showLogs(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (context, scrollController) => Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text("System Logs",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: ValueListenableBuilder<List<String>>(
              valueListenable: DebugLogger.logs,
              builder: (context, logList, _) => ListView.builder(
                controller: scrollController,
                itemCount: logList.length,
                itemBuilder: (context, i) => ListTile(
                  title: SelectableText(logList[i],
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 11)),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

}
