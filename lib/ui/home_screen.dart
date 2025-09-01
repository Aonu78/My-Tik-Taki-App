import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:my_tik_taki/models/download_model.dart';
import 'package:my_tik_taki/services/download_service.dart';
import 'package:my_tik_taki/services/notification_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final WebViewController _controller;
  final _downloadService = DownloadService();
  late final NotificationService _notificationService;
  final List<DownloadModel> _downloads = [];
  bool _isLoading = true;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _checkConnectivity();
    _downloadService.downloadStream.listen((download) {
      if (download.isComplete) {
        _notificationService.showDownloadNotification(download.fileName);
      }
      setState(() {
        _downloads.add(download);
      });
    });
  }

  Future<void> _initializeServices() async {
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    _notificationService = NotificationService(flutterLocalNotificationsPlugin);
    await _notificationService.initialize();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            setState(() {
              _isLoading = false;
            });
          },
          onNavigationRequest: (NavigationRequest request) {
            if (request.url.startsWith('blob:')) {
              _injectBlobHandler(request.url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..addJavaScriptChannel(
        'BlobHandler',
        onMessageReceived: (JavaScriptMessage message) async {
          String base64String = message.message;
          String fileNameFinal =
              '${_downloadService.generateRandomString(10)}.mp4';
          await _downloadService.downloadBase64File(base64String, fileNameFinal,
              (download) {
            setState(() {
              final existingDownloadIndex =
                  _downloads.indexWhere((d) => d.fileName == download.fileName);
              if (existingDownloadIndex != -1) {
                _downloads[existingDownloadIndex] = download;
              } else {
                _downloads.add(download);
              }
            });
          });
        },
      )
      ..loadRequest(Uri.parse('https://my-tik-taki.netlify.app/'));
  }

  @override
  void dispose() {
    _downloadService.dispose();
    super.dispose();
  }

  Future<void> _checkConnectivity() async {
    var connectivityResult = await (Connectivity().checkConnectivity());
    setState(() {
      _isOffline = connectivityResult.first == ConnectivityResult.none;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('My Tik Taki')),
      body: _isOffline
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                      'You are offline. Please check your internet connection.'),
                  SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      _checkConnectivity();
                      if (!_isOffline) {
                        _controller.reload();
                      }
                    },
                    child: Text('Retry'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      WebViewWidget(controller: _controller),
                      if (_isLoading)
                        Center(child: CircularProgressIndicator()),
                    ],
                  ),
                ),
                _buildFooter(),
              ],
            ),
    );
  }

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

  void _showDownloads() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Downloads'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              itemCount: _downloads.length,
              itemBuilder: (context, index) {
                final download = _downloads[index];
                return ListTile(
                  title: Text(download.fileName),
                  subtitle: download.isComplete
                      ? Text('Completed')
                      : LinearProgressIndicator(
                          value: download.progress / 100,
                        ),
                  trailing: IconButton(
                    icon: Icon(Icons.close),
                    onPressed: () {
                      setState(() {
                        _downloads.removeAt(index);
                      });
                    },
                  ),
                  onTap: () {
                    if (download.isComplete) {
                      // ignore: deprecated_member_use
                      Share.shareXFiles([XFile(download.filePath!)],
                          text: 'Check out this file: ${download.fileName}');
                    }
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
    _controller.runJavaScript(jsCode);
  }
}
