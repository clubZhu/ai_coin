import 'package:flutter/material.dart';

import 'app.dart';
import 'core/app_system_ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSystemUi.configure();
  runApp(const CryptoPilotApp());
}
