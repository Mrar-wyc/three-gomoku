import 'package:flutter/material.dart';

import 'app.dart';
import 'services/settings_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsService.load();
  runApp(const GomokuApp());
}
