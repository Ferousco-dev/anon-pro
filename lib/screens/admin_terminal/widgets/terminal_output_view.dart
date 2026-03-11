import 'package:flutter/material.dart';
import '../controllers/terminal_controller.dart';

/// Scrollable output console that displays command history and responses.
/// Auto-scrolls to the bottom when new output is added.
class TerminalOutputView extends StatefulWidget {
  final TerminalController controller;

  const TerminalOutputView({super.key, required this.controller});

  @override
  State<TerminalOutputView> createState() => _TerminalOutputViewState();
}

class _TerminalOutputViewState extends State<TerminalOutputView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onOutputChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onOutputChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onOutputChanged() {
    // Auto-scroll to bottom after a frame so the new items are rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.controller.outputLines;

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final line = lines[index];
        final isCommand = line.startsWith('\$');
        final isError = line.startsWith('ERROR:') || line.startsWith('ACCESS DENIED');
        final isSuccess = line.startsWith('SUCCESS:');

        Color textColor;
        if (isCommand) {
          textColor = const Color(0xFF00FF66); // bright green
        } else if (isError) {
          textColor = const Color(0xFFFF3B30); // red
        } else if (isSuccess) {
          textColor = const Color(0xFF34C759); // green
        } else {
          textColor = const Color(0xFF00FF66).withOpacity(0.85);
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 1),
          child: Text(
            line,
            style: TextStyle(
              color: textColor,
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.4,
              fontWeight: isCommand ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        );
      },
    );
  }
}
