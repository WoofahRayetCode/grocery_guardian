import 'package:flutter/material.dart';
import 'package:flutter_jailbreak_detection/flutter_jailbreak_detection.dart';

class DeviceSecurity {
  /// Returns true if the device appears rooted/jailbroken/emulated.
  static Future<bool> isCompromised() async {
    try {
      final jailbroken = await FlutterJailbreakDetection.jailbroken;
      final developerMode = await FlutterJailbreakDetection.developerMode;
      return jailbroken || developerMode;
    } catch (e) {
      debugPrint('DeviceSecurity check failed: $e');
      return false;
    }
  }

  static Future<void> warnIfCompromised(BuildContext context) async {
    final compromised = await isCompromised();
    if (!context.mounted) return;
    if (compromised) {
      final cs = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Security warning: device appears rooted/jailbroken or in developer mode.'),
          backgroundColor: cs.errorContainer,
        ),
      );
    }
  }
}
