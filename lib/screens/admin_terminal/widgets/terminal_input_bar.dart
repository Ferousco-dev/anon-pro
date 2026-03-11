import 'package:flutter/material.dart';

/// Bottom input bar for the terminal with a `$` prefix.
/// Calls [onSubmit] when ENTER is pressed.
class TerminalInputBar extends StatefulWidget {
  final ValueChanged<String> onSubmit;
  final bool enabled;

  const TerminalInputBar({
    super.key,
    required this.onSubmit,
    this.enabled = true,
  });

  @override
  State<TerminalInputBar> createState() => _TerminalInputBarState();
}

class _TerminalInputBarState extends State<TerminalInputBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  void _handleSubmit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSubmit(text);
    _controller.clear();
    // Keep focus on input after submit
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0A0A0A),
        border: Border(
          top: BorderSide(color: Color(0xFF00FF66), width: 0.5),
        ),
      ),
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Row(
        children: [
          const Text(
            '\$ ',
            style: TextStyle(
              color: Color(0xFF00FF66),
              fontFamily: 'monospace',
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              enabled: widget.enabled,
              style: const TextStyle(
                color: Color(0xFF00FF66),
                fontFamily: 'monospace',
                fontSize: 14,
              ),
              cursorColor: const Color(0xFF00FF66),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Enter command...',
                hintStyle: TextStyle(
                  color: Color(0xFF336633),
                  fontFamily: 'monospace',
                  fontSize: 14,
                ),
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _handleSubmit(),
              autocorrect: false,
              enableSuggestions: false,
            ),
          ),
          IconButton(
            onPressed: widget.enabled ? _handleSubmit : null,
            icon: Icon(
              Icons.send_rounded,
              color: widget.enabled
                  ? const Color(0xFF00FF66)
                  : const Color(0xFF336633),
              size: 20,
            ),
            splashRadius: 20,
          ),
        ],
      ),
    );
  }
}
