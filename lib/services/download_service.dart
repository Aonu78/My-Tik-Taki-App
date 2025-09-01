import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:my_tik_taki/models/download_model.dart';
import 'package:permission_handler/permission_handler.dart';

class DownloadService {
  final StreamController<DownloadModel> _downloadController =
      StreamController<DownloadModel>.broadcast();

  Stream<DownloadModel> get downloadStream => _downloadController.stream;

  Future<void> downloadBase64File(String base64String, String fileName,
      Function(DownloadModel) onProgress) async {
    bool permissionGranted = await _requestPermission();
    if (permissionGranted) {
      final appDocDir = Directory('/storage/emulated/0/Download');
      final filePath = '${appDocDir.path}/$fileName';
      final bytes = base64Decode(base64String);
      File file = File(filePath);
      await file.writeAsBytes(bytes);

      var download = DownloadModel(
          fileName: fileName,
          progress: 100,
          isComplete: true,
          filePath: filePath);
      onProgress(download);
      _downloadController.add(download);
    }
  }

  Future<bool> _requestPermission() async {
    var status = await Permission.manageExternalStorage.status;
    if (status.isGranted) {
      return true;
    } else {
      status = await Permission.manageExternalStorage.request();
      return status.isGranted;
    }
  }

  void dispose() {
    _downloadController.close();
  }

  String generateRandomString(int length) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random();
    return List.generate(length, (index) => chars[rand.nextInt(chars.length)])
        .join();
  }
}
