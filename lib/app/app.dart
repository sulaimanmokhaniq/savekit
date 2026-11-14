import 'package:material_ui/material_ui.dart';

import '../core/theme/app_theme.dart';
import 'home_shell.dart';

class SaveKitApp extends StatelessWidget {
  const SaveKitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SaveKit',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const HomeShell(),
    );
  }
}
