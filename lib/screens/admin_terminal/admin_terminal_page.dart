import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'controllers/terminal_controller.dart';
import 'widgets/terminal_output_view.dart';
import 'widgets/terminal_input_bar.dart';

/// The main admin terminal page — CLI-style console interface.
///
/// Security: This page is not in the navigation stack after exit.
/// All history is cleared on dispose.
class AdminTerminalPage extends StatefulWidget {
  const AdminTerminalPage({super.key});

  @override
  State<AdminTerminalPage> createState() => _AdminTerminalPageState();
}

class _AdminTerminalPageState extends State<AdminTerminalPage> {
  late final TerminalController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TerminalController();
    _controller.showBanner();

    // Force dark status bar
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  }

  @override
  void dispose() {
    // Security: clear all history on exit
    _controller.clearHistory();
    _controller.dispose();
    super.dispose();
  }

  void _onCommandSubmitted(String command) {
    _controller.processCommand(command);
  }

  void _exitTerminal() {
    // Clear history before leaving
    _controller.clearHistory();
    // Pop back — the route was pushed with pushReplacement from passkey page,
    // so there's no terminal trace in the back stack
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exitTerminal();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF000000),
        appBar: AppBar(
          backgroundColor: const Color(0xFF000000),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Color(0xFF00FF66), size: 22),
            onPressed: _exitTerminal,
          ),
          title: const Row(
            children: [
              Icon(Icons.terminal, color: Color(0xFF00FF66), size: 18),
              SizedBox(width: 8),
              Text(
                'ADMIN TERMINAL',
                style: TextStyle(
                  color: Color(0xFF00FF66),
                  fontFamily: 'monospace',
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          centerTitle: false,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(
              height: 0.5,
              color: const Color(0xFF00FF66).withOpacity(0.3),
            ),
          ),
        ),
        body: Column(
          children: [
            // Scrollable output console
            Expanded(
              child: ListenableBuilder(
                listenable: _controller,
                builder: (context, _) {
                  return TerminalOutputView(controller: _controller);
                },
              ),
            ),

            // Processing indicator
            ListenableBuilder(
              listenable: _controller,
              builder: (context, _) {
                if (!_controller.isProcessing) {
                  return const SizedBox.shrink();
                }
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Color(0xFF00FF66),
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Processing...',
                        style: TextStyle(
                          color: Color(0xFF336633),
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // Command input bar
            ListenableBuilder(
              listenable: _controller,
              builder: (context, _) {
                return TerminalInputBar(
                  onSubmit: _onCommandSubmitted,
                  enabled: !_controller.isProcessing,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
