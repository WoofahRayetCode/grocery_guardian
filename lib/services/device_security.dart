import 'package:flutter/material.dart';

class DeviceSecurity {
  /// Returns true if the device appears rooted/jailbroken/emulated.
  /// Note: Detection disabled - flutter_jailbreak_detection incompatible with current AGP.
  /// Consider using: safe_device, flutter_jailbreak_checker, or freerasp when available.
  static Future<bool> isCompromised() async {
    // TODO: Replace with compatible plugin when available
    return false;
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

  // Alternative plugins to consider:
  // - safe_device: ^1.1.4 (actively maintained)
  // - flutter_jailbreak_checker: ^1.0.0
  // - freerasp: commercial with free tier
}
