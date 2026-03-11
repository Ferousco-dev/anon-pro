import 'package:flutter/material.dart';

/// ASCII-art banner displayed at the top of the terminal on load.
class TerminalBanner extends StatelessWidget {
  const TerminalBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 12, bottom: 4, left: 12, right: 12),
      child: Text(
        '===================================\n'
        '  ADMIN TERMINAL v1.0\n'
        '  Authorized Access Only\n'
        '  Type "help" to see commands\n'
        '===================================',
        style: TextStyle(
          color: Color(0xFF00FF66),
          fontFamily: 'monospace',
          fontSize: 13,
          height: 1.5,
        ),
      ),
    );
  }
}
