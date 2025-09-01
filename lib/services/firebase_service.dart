import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

class FirebaseService {
  static Future<void> initialize() async {
    try {
      await Firebase.initializeApp();
      FirebaseAnalytics analytics = FirebaseAnalytics.instance;
      await analytics.logEvent(
        name: 'app_open',
        parameters: {'platform': 'android'},
      );
    } catch (e) {
      debugPrint("Error initializing Firebase: $e");
    }
  }
}
