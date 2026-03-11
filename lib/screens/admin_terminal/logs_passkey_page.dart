import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/terminal_security_service.dart';
import 'admin_terminal_page.dart';

/// Passkey authentication page shown before accessing the admin terminal.
///
/// Displays a PIN-style input. On correct passkey → navigates to AdminTerminalPage.
/// On wrong passkey → shows error. Logs failed attempts and enforces rate limiting.
class LogsPasskeyPage extends StatefulWidget {
  const LogsPasskeyPage({super.key});

  @override
  State<LogsPasskeyPage> createState() => _LogsPasskeyPageState();
}

class _LogsPasskeyPageState extends State<LogsPasskeyPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final TerminalSecurityService _securityService = TerminalSecurityService();

  String? _errorMessage;
  bool _isValidating = false;
  bool _obscureText = true;

  // Shake animation for incorrect passkey
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );

    // Auto-focus the input
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _validatePasskey() async {
    final passkey = _controller.text.trim();
    if (passkey.isEmpty) return;

    setState(() {
      _isValidating = true;
      _errorMessage = null;
    });

    final error = await _securityService.validatePasskey(passkey);

    if (!mounted) return;

    if (error == null) {
      // Success — navigate to terminal, replacing this route so it's not in the stack
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const AdminTerminalPage(),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 300),
        ),
      );
    } else {
      // Failed
      setState(() {
        _isValidating = false;
        _errorMessage = error;
      });
      _controller.clear();
      _shakeController.forward().then((_) => _shakeController.reset());
      HapticFeedback.heavyImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Colors.white54, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Lock icon
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF00FF66).withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  color: Color(0xFF00FF66),
                  size: 32,
                ),
              ),
              const SizedBox(height: 24),

              // Title
              const Text(
                'SYSTEM ACCESS',
                style: TextStyle(
                  color: Color(0xFF00FF66),
                  fontFamily: 'monospace',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter admin passkey to continue',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 32),

              // Passkey input
              AnimatedBuilder(
                animation: _shakeAnimation,
                builder: (context, child) {
                  final shake = _shakeAnimation.value *
                      10 *
                      (1 - _shakeAnimation.value);
                  return Transform.translate(
                    offset: Offset(shake * ((_shakeAnimation.value * 10).toInt().isOdd ? 1 : -1), 0),
                    child: child,
                  );
                },
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _errorMessage != null
                          ? const Color(0xFFFF3B30)
                          : const Color(0xFF00FF66).withOpacity(0.4),
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          obscureText: _obscureText,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF00FF66),
                            fontFamily: 'monospace',
                            fontSize: 24,
                            letterSpacing: 12,
                          ),
                          cursorColor: const Color(0xFF00FF66),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: '• • • • • •',
                            hintStyle: TextStyle(
                              color: const Color(0xFF00FF66).withOpacity(0.2),
                              fontSize: 24,
                              letterSpacing: 8,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          onSubmitted: (_) => _validatePasskey(),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          _obscureText
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: const Color(0xFF00FF66).withOpacity(0.4),
                          size: 20,
                        ),
                        onPressed: () =>
                            setState(() => _obscureText = !_obscureText),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Submit button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isValidating ? null : _validatePasskey,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        const Color(0xFF00FF66).withOpacity(0.15),
                    foregroundColor: const Color(0xFF00FF66),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: const Color(0xFF00FF66).withOpacity(0.3),
                      ),
                    ),
                    elevation: 0,
                  ),
                  child: _isValidating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF00FF66),
                          ),
                        )
                      : const Text(
                          'AUTHENTICATE',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 24),

              // Error message
              if (_errorMessage != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF3B30).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFFFF3B30).withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFF3B30),
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
