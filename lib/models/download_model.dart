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
