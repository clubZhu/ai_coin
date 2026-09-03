import 'package:flutter/material.dart';

import 'core/app_theme.dart';
import 'data/position_repository.dart';
import 'features/app_shell.dart';

class CryptoPilotApp extends StatelessWidget {
  const CryptoPilotApp({super.key, this.positionRepository});

  final PositionRepository? positionRepository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CryptoPilot',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: AppShell(positionRepository: positionRepository),
    );
  }
}
