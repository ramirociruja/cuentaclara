// lib/utils/navigation.dart
import 'package:flutter/material.dart';

class Nav {
  static final navigatorKey = GlobalKey<NavigatorState>();

  static Future<T?> pushReplacementTo<T>(Route<T> route) async {
    return navigatorKey.currentState?.pushReplacement(route);
  }

  static Future<T?> pushAndRemoveAll<T>(Route<T> route) async {
    return navigatorKey.currentState?.pushAndRemoveUntil(route, (r) => false);
  }

  static ScaffoldMessengerState? get messenger =>
      ScaffoldMessenger.maybeOf(navigatorKey.currentContext!);
}
