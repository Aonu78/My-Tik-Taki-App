import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:share_plus/share_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';

// Initialize local notifications plugin
FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterDownloader.initialize(debug: false);
  await Permission.manageExternalStorage.request();
  await createDownloadsDirectory(); // Create downloads directory

  // Configure notifications
  var initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  var initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  // Firebase initialization and Analytics
  try {
    await Firebase.initializeApp();
    FirebaseAnalytics analytics = FirebaseAnalytics.instance;

    // Log custom event on app open
    await analytics.logEvent(
      name: 'app_open',
      parameters: {'platform': 'android'}, // Optional parameters
    );
  } catch (e) {
    print("Error initializing Firebase: $e");
  }
  runApp(MyApp());
}

// Create downloads directory
Future<void> createDownloadsDirectory() async {
  var directory = Directory('/storage/emulated/0/Download');
  if (!(await directory.exists())) {
    await directory.create(recursive: true);
    print('Downloads directory created: ${directory.path}');
  } else {
    print('Downloads directory already exists');
  }
}

// MyApp widget that initializes the app
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Tik Taki',
      home: SplashScreen(),
    );
  }
}

// SplashScreen with a delay before navigating to HomeScreen
class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _navigateToHome();
  }

  // Navigate to HomeScreen after 3 seconds
  _navigateToHome() async {
    await Future.delayed(Duration(seconds: 3));
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => HomeScreen()),
    );
  }

  // Check for storage permissions
  Future<void> _checkPermissions() async {
    var status = await Permission.manageExternalStorage.status;
    if (!status.isGranted) {
      status = await Permission.manageExternalStorage.request();
      if (!status.isGranted) {
        print("Storage permission is denied");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Image.asset(
          'assets/splash_image.png', // Path to splash image
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

// Model to track download progress and completion
class DownloadModel {
  String fileName;
  int progress;
  bool isComplete;
  String? filePath;

  DownloadModel({
    required this.fileName,
    this.progress = 0,
    this.isComplete = false,
    this.filePath,
  });
}

// HomeScreen with WebView and download functionality
class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late WebViewController _controller;
  final StreamController<DownloadModel> _downloadController =
      StreamController<DownloadModel>.broadcast();
  List<DownloadModel> _downloads = []; // List to store all downloads
  DownloadModel? _currentDownload;
  bool _isLoading = true;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
  }

  @override
  void dispose() {
    _downloadController.close();
    super.dispose();
  }

  // Check for internet connectivity
  Future<void> _checkConnectivity() async {
    var connectivityResult = await (Connectivity().checkConnectivity());
    setState(() {
      _isOffline = connectivityResult == ConnectivityResult.none;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('My Tik Taki')),
      body: _isOffline
          ? Center(child: CircularProgressIndicator()) // Show loader if offline
          : Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      WebView(
                        initialUrl: 'https://my-tik-taki.netlify.app/',
                        javascriptMode: JavascriptMode.unrestricted,
                        onWebViewCreated:
                            (WebViewController webViewController) {
                          _controller = webViewController;
                        },
                        onPageFinished: (_) {
                          setState(() {
                            _isLoading = false; // Hide loader when page loaded
                          });
                        },
                        javascriptChannels: {
                          JavascriptChannel(
                            name: 'BlobHandler',
                            onMessageReceived:
                                (JavascriptMessage message) async {
                              String base64String = message.message;
                              String fileNameFinal =
                                  _generateRandomString(10) + '.mp4';
                              _currentDownload =
                                  DownloadModel(fileName: fileNameFinal);
                              _downloadController.add(_currentDownload!);
                              await _downloadBase64File(
                                  base64String, _currentDownload!.fileName);
                            },
                          ),
                        },
                        navigationDelegate: (NavigationRequest request) {
                          if (request.url.startsWith('blob:')) {
                            _injectBlobHandler(request.url);
                            return NavigationDecision.prevent;
                          }
                          return NavigationDecision.navigate;
                        },
                      ),
                      if (_isLoading)
                        Center(child: CircularProgressIndicator()),
                    ],
                  ),
                ),
                StreamBuilder<DownloadModel>(
                  stream: _downloadController.stream,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return SizedBox.shrink();
                    final download = snapshot.data!;
                    return Column(
                      children: [
                        if (!download.isComplete)
                          LinearProgressIndicator(
                            value: download.progress / 100,
                            backgroundColor: Colors.grey,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.blue),
                          ),
                        if (download.isComplete && download.filePath != null)
                          ElevatedButton(
                            onPressed: () {
                              Share.shareXFiles([XFile(download.filePath!)],
                                  text:
                                      'Check out this file: ${download.fileName}');
                            },
                            child: Text('Share ${download.fileName}'),
                          ),
                      ],
                    );
                  },
                ),
                _buildFooter(),
              ],
            ),
    );
  }

  // Build the footer with download management
  Widget _buildFooter() {
    return Container(
      padding: EdgeInsets.all(10),
      color: Colors.grey[200],
      child: Column(
        children: [
          ElevatedButton(
            onPressed: _showDownloads,
            child: Text('Show Downloads'),
          ),
        ],
      ),
    );
  }

  // Show a dialog with the list of downloads
  void _showDownloads() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Downloads'),
          content: Container(
            width: double.maxFinite,
            child: ListView.builder(
              itemCount: _downloads.length,
              itemBuilder: (context, index) {
                final download = _downloads[index];
                return ListTile(
                  title: Text(download.fileName),
                  trailing: IconButton(
                    icon: Icon(Icons.close),
                    onPressed: () {
                      // Remove download from list
                      setState(() {
                        _downloads.removeAt(index);
                      });
                    },
                  ),
                  onTap: () {
                    // Share the file
                    Share.shareXFiles([XFile(download.filePath!)],
                        text: 'Check out this file: ${download.fileName}');
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }

  // Generate random file name
  String _generateRandomString(int length) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random();
    return List.generate(length, (index) => chars[rand.nextInt(chars.length)])
        .join();
  }

  // Inject JavaScript to handle blob URLs
  void _injectBlobHandler(String blobUrl) {
    String jsCode = '''
      (function() {
        var xhr = new XMLHttpRequest();
        xhr.open('GET', '$blobUrl', true);
        xhr.responseType = 'blob';
        xhr.onload = function(e) {
          if (this.status == 200) {
            var blob = this.response;
            var reader = new FileReader();
            reader.onload = function(event) {
              var base64String = event.target.result.split(',')[1];
              BlobHandler.postMessage(base64String);
            };
            reader.readAsDataURL(blob);
          }
        };
        xhr.send();
      })();
    ''';
    _controller.runJavascript(jsCode);
  }

  // Handle downloading base64-encoded file
  Future<void> _downloadBase64File(String base64String, String fileName) async {
    bool permissionGranted = await _requestPermission();
    if (permissionGranted) {
      final appDocDir = Directory('/storage/emulated/0/Download');
      final filePath = '${appDocDir.path}/$fileName';
      final bytes = base64Decode(base64String);
      File file = File(filePath);
      await file.writeAsBytes(bytes);

      // Update download progress and completion status
      setState(() {
        _currentDownload?.progress = 100;
        _currentDownload?.isComplete = true;
        _currentDownload?.filePath = filePath;
        _downloads.add(_currentDownload!);
      });

      // Show notification on download completion
      _showDownloadNotification(fileName);
    }
  }

  // Request storage permission
  Future<bool> _requestPermission() async {
    var status = await Permission.manageExternalStorage.status;
    if (status.isGranted) {
      return true;
    } else {
      status = await Permission.manageExternalStorage.request();
      return status.isGranted;
    }
  }

  // Show a download notification
  Future<void> _showDownloadNotification(String fileName) async {
    var androidDetails = AndroidNotificationDetails(
      'download_channel',
      'Downloads',
      channelDescription: 'Download notifications',
      importance: Importance.high,
      priority: Priority.high,
    );
    var platformDetails = NotificationDetails(android: androidDetails);
    await flutterLocalNotificationsPlugin.show(
      0,
      'Download Complete',
      'File $fileName has been downloaded successfully',
      platformDetails,
    );
  }
}
