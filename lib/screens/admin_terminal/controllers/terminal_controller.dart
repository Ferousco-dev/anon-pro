import 'package:flutter/foundation.dart';
import '../services/terminal_command_service.dart';

/// Manages terminal state: command history, output lines, and command execution.
/// Uses ChangeNotifier for Provider-based state management.
class TerminalController extends ChangeNotifier {
  final TerminalCommandService _commandService = TerminalCommandService();

  final List<String> _outputLines = [];
  bool _isProcessing = false;

  /// All output lines (banner + command echoes + responses).
  List<String> get outputLines => List.unmodifiable(_outputLines);

  /// Whether a command is currently being executed.
  bool get isProcessing => _isProcessing;

  /// Add the startup banner to the output.
  void showBanner() {
    _outputLines.addAll([
      '',
      '===================================',
      '  ADMIN TERMINAL v1.0',
      '  Authorized Access Only',
      '  Type "help" to see commands',
      '===================================',
      '',
    ]);
    notifyListeners();
  }

  /// Process a command string from the input bar.
  Future<void> processCommand(String rawInput) async {
    final input = rawInput.trim();
    if (input.isEmpty) return;

    // Echo the command
    _outputLines.add('\$ $input');
    _isProcessing = true;
    notifyListeners();

    try {
      final result = await _commandService.execute(input);

      if (result == '__CLEAR__') {
        _outputLines.clear();
        _isProcessing = false;
        notifyListeners();
        return;
      }

      // Split multi-line responses into individual lines
      if (result.isNotEmpty) {
        _outputLines.addAll(result.split('\n'));
      }
      // Add blank line after each command for readability
      _outputLines.add('');
    } catch (e) {
      _outputLines.add('ERROR: $e');
      _outputLines.add('');
    }

    _isProcessing = false;
    notifyListeners();
  }

  /// Clear all output history.
  void clearHistory() {
    _outputLines.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _outputLines.clear();
    super.dispose();
  }
}
