import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:my_tik_taki/services/firebase_service.dart';
import 'package:my_tik_taki/services/notification_service.dart';
import 'package:my_tik_taki/ui/splash_screen.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterDownloader.initialize(debug: false);
  await FirebaseService.initialize();
  await NotificationService(FlutterLocalNotificationsPlugin()).initialize();

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Tik Taki',
      home: SplashScreen(),
    );
  }
}
