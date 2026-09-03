import 'package:flutter/material.dart';

import 'core/app_theme.dart';
import 'features/app_shell.dart';

class CryptoPilotApp extends StatelessWidget {
  const CryptoPilotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CryptoPilot',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const AppShell(),
    );
  }
}
