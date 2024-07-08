import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:video_player/video_player.dart';

FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize necessary plugins and request permissions
  await FlutterDownloader.initialize(debug: false);
  await Permission.manageExternalStorage.request();
  await createDownloadsDirectory(); // Create downloads directory

  var initializationSettingsAndroid =
  AndroidInitializationSettings('@mipmap/ic_launcher');
  var initializationSettings =
  InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  runApp(MyApp());
}

Future<void> createDownloadsDirectory() async {
  var directory = Directory('/storage/emulated/0/Download');
  if (!(await directory.exists())) {
    await directory.create(recursive: true);
    print('Downloads directory created: ${directory.path}');
  } else {
    print('Downloads directory already exists');
  }
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Tik Taki',
      home: SplashScreen(),
    );
  }
}

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

  _navigateToHome() async {
    await Future.delayed(Duration(seconds: 3));
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => HomeScreen()),
    );
  }

  Future<void> _checkPermissions() async {
    var status = await Permission.manageExternalStorage.status;
    if (!status.isGranted) {
      status = await Permission.manageExternalStorage.request();
      if (!status.isGranted) {
        // Handle the case where permission is not granted
        print("Storage permission is denied");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(
          'My Tik Taki',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

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

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late WebViewController _controller;
  final StreamController<DownloadModel> _downloadController =
  StreamController<DownloadModel>.broadcast();
  DownloadModel? _currentDownload;

  @override
  void dispose() {
    _downloadController.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('My Tik Taki'),
      ),
      body: Column(
        children: [
          Expanded(
            child: WebView(
              initialUrl: 'https://super-marzipan-94e6d2.netlify.app/',
              javascriptMode: JavascriptMode.unrestricted,
              onWebViewCreated: (WebViewController webViewController) {
                _controller = webViewController;
              },
              javascriptChannels: {
                JavascriptChannel(
                  name: 'BlobHandler',
                  onMessageReceived: (JavascriptMessage message) async {
                    String base64String = message.message;
                    String fileNameFinal = _generateRandomString(10) + '.mp4';
                    _currentDownload = DownloadModel(fileName: fileNameFinal);
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
          ),
          StreamBuilder<DownloadModel>(
            stream: _downloadController.stream,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return SizedBox.shrink();
              }

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
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => VideoPlayerScreen(
                              filePath: download.filePath!,
                            ),
                          ),
                        );
                      },
                      child: Text('Play ${download.fileName}'),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
  String _generateRandomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random();
    return List.generate(length, (index) => chars[rand.nextInt(chars.length)]).join();
  }
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

  Future<void> _downloadBase64File(
      String base64String, String fileName) async {
    bool status = await _requestPermission();
    if (status) {
      final appDocDir = Directory('/storage/emulated/0/Download');
      if (appDocDir == null) {
        print("Error: Application documents directory is null.");
        return;
      }
      final filePath = '${appDocDir.path}/$fileName';
      final bytes = base64Decode(base64String);
      final file = File(filePath);

      // Show notification on download start
      await _showDownloadNotification(
          'Download Started', 'Downloading $fileName');
      print("Download Started");
      await file.writeAsBytes(bytes);

      // Show notification on download completion
      await _showDownloadNotification(
          'Download Completed', '$fileName downloaded to $filePath');
      print("File downloaded to $filePath");

      setState(() {
        _currentDownload?.isComplete = true;
        _currentDownload?.filePath = filePath;
        _downloadController.add(_currentDownload!);
      });
    } else {
      print('Permission denied for storage');
    }
  }

  Future<bool> _requestPermission() async {
    var status = await Permission.manageExternalStorage.status;
    if (status.isGranted) {
      print("Storage permission is already granted");
      return true;
    } else {
      status = await Permission.manageExternalStorage.request();
      if (status.isGranted) {
        print("Storage permission is granted");
        return true;
      } else {
        print("Storage permission is denied");
        return false;
      }
    }
  }

  Future<void> _showDownloadNotification(String title, String body) async {
    var androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'download_channel',
      'Download Notifications',
      channelDescription:
      'Channel for showing download status notifications',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: false,
    );
    var platformChannelSpecifics =
    NotificationDetails(android: androidPlatformChannelSpecifics);
    await flutterLocalNotificationsPlugin.show(
      0,
      title,
      body,
      platformChannelSpecifics,
      payload: 'item x',
    );
  }
}

class VideoPlayerScreen extends StatefulWidget {
  final String filePath;

  VideoPlayerScreen({required this.filePath});

  @override
  _VideoPlayerScreenState createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;
  late Future<void> _initializeVideoPlayerFuture;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.filePath));
    _initializeVideoPlayerFuture = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Video Player'),
      ),
      body: FutureBuilder(
        future: _initializeVideoPlayerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Center(
              child: AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              ),
            );
          } else {
            return Center(child: CircularProgressIndicator());
          }
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {
            if (_controller.value.isPlaying) {
              _controller.pause();
            } else {
              _controller.play();
            }
          });
        },
        child: Icon(
          _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
        ),
      ),
    );
  }
}
