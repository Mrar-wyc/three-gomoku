import 'dart:async';

import 'package:flutter/services.dart';

import '../services/settings_service.dart';

/// 落子反馈的统一入口：按用户设置决定是否播放音效/震动。
class MoveFeedback {
  static void play() {
    if (SettingsService.sound) {
      unawaited(SystemSound.play(SystemSoundType.click));
    }
    if (SettingsService.haptic) {
      unawaited(HapticFeedback.lightImpact());
    }
  }
}
