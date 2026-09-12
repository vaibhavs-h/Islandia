import 'package:flutter/material.dart';

import 'shell/island_shell.dart';

void main() {
  runApp(const IslandiaApp());
}

/// No Scaffold, no MaterialApp chrome — the window itself is the pill (see
/// MainFlutterWindow.swift), so anything this tree paints outside the Island
/// shell's own decoration must stay fully transparent.
class IslandiaApp extends StatelessWidget {
  const IslandiaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      home: Material(
        type: MaterialType.transparency,
        child: IslandShell(),
      ),
    );
  }
}
