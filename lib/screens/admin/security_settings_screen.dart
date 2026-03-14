import 'package:flutter/material.dart';
import '../../utils/constants.dart';
import '../admin_terminal/services/terminal_command_service.dart';

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  late TerminalCommandService _commandService;
  final _newPasscodeController = TextEditingController();
  final _confirmPasscodeController = TextEditingController();
  bool _showPasscode = false;
  bool _isLoading = false;
  String? _resultMessage;
  bool _isSuccessMessage = false;

  @override
  void initState() {
    super.initState();
    _commandService = TerminalCommandService();
  }

  @override
  void dispose() {
    _newPasscodeController.dispose();
    _confirmPasscodeController.dispose();
    super.dispose();
  }

  void _showViewPasscodeDialog() async {
    try {
      setState(() => _isLoading = true);
      final result = await _commandService.execute('view passcode');
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppConstants.darkGray,
            title: const Text('Current Passcode'),
            content: SingleChildScrollView(
              child: Text(
                result,
                style: const TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 13,
                  color: Colors.white,
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showChangePasscodeDialog() {
    _newPasscodeController.clear();
    _confirmPasscodeController.clear();
    _resultMessage = null;
    _isSuccessMessage = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppConstants.darkGray,
          title: const Text('Change Admin Passcode'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Enter new passcode (4-20 characters)\nAlphanumeric + _-@!#\$%^&*()',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppConstants.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _newPasscodeController,
                  obscureText: !_showPasscode,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'New passcode',
                    hintStyle:
                        const TextStyle(color: AppConstants.textSecondary),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: AppConstants.lightGray,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: AppConstants.lightGray,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: AppConstants.primaryBlue,
                      ),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showPasscode ? Icons.visibility : Icons.visibility_off,
                        color: AppConstants.textSecondary,
                      ),
                      onPressed: () {
                        setDialogState(() => _showPasscode = !_showPasscode);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmPasscodeController,
                  obscureText: !_showPasscode,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Confirm passcode',
                    hintStyle:
                        const TextStyle(color: AppConstants.textSecondary),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: AppConstants.lightGray,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: AppConstants.lightGray,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: AppConstants.primaryBlue,
                      ),
                    ),
                  ),
                ),
                if (_resultMessage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _isSuccessMessage
                          ? Colors.green.withOpacity(0.15)
                          : Colors.red.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _isSuccessMessage ? Colors.green : Colors.red,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      _resultMessage!,
                      style: TextStyle(
                        fontSize: 12,
                        color: _isSuccessMessage ? Colors.green : Colors.red,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryBlue,
              ),
              onPressed: _isLoading
                  ? null
                  : () async {
                      setDialogState(() => _resultMessage = null);

                      if (_newPasscodeController.text.isEmpty ||
                          _confirmPasscodeController.text.isEmpty) {
                        setDialogState(() {
                          _resultMessage = 'Please fill all fields';
                          _isSuccessMessage = false;
                        });
                        return;
                      }

                      if (_newPasscodeController.text !=
                          _confirmPasscodeController.text) {
                        setDialogState(() {
                          _resultMessage = 'Passcodes do not match';
                          _isSuccessMessage = false;
                        });
                        return;
                      }

                      setDialogState(() => _isLoading = true);

                      try {
                        final result = await _commandService.execute(
                          'change passcode ${_newPasscodeController.text}',
                        );

                        setDialogState(() {
                          if (result.contains('SUCCESS')) {
                            _resultMessage = 'Passcode changed successfully! ✓';
                            _isSuccessMessage = true;
                            Future.delayed(const Duration(seconds: 2), () {
                              if (ctx.mounted) {
                                Navigator.pop(ctx);
                              }
                            });
                          } else {
                            _resultMessage = result
                                .replaceAll('ERROR: ', '')
                                .replaceAll('FAILED', 'Failed');
                            _isSuccessMessage = false;
                          }
                        });
                      } catch (e) {
                        setDialogState(() {
                          _resultMessage = 'Error: $e';
                          _isSuccessMessage = false;
                        });
                      } finally {
                        setDialogState(() => _isLoading = false);
                      }
                    },
              child: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('Change'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.black,
      appBar: AppBar(
        title: const Text('Security Settings'),
        backgroundColor: AppConstants.black,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppConstants.primaryBlue.withOpacity(0.1),
              border:
                  Border.all(color: AppConstants.primaryBlue.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🔐 Admin Terminal Security',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Manage your admin terminal passcode. Keep it secure and change it regularly.',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppConstants.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // View Current Passcode
          _buildSecurityCard(
            title: 'View Current Passcode',
            subtitle: 'Display your admin terminal passcode',
            icon: Icons.visibility_outlined,
            onTap: _showViewPasscodeDialog,
            isLoading: _isLoading,
          ),
          const SizedBox(height: 12),

          // Change Passcode
          _buildSecurityCard(
            title: 'Change Passcode',
            subtitle: 'Update your admin terminal passcode',
            icon: Icons.lock_outline_rounded,
            onTap: _showChangePasscodeDialog,
            isLoading: _isLoading,
            isDanger: true,
          ),
          const SizedBox(height: 24),

          // Security Tips
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Security Tips',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildTip('• Use a strong passcode (at least 8 characters)'),
                _buildTip('• Mix uppercase, lowercase, numbers, and symbols'),
                _buildTip('• Never share your admin terminal passcode'),
                _buildTip('• Change your passcode monthly'),
                _buildTip('• All changes are logged for audit purposes'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    required bool isLoading,
    bool isDanger = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppConstants.darkGray,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDanger
              ? Colors.red.withOpacity(0.3)
              : AppConstants.lightGray.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDanger
                        ? Colors.red.withOpacity(0.15)
                        : AppConstants.primaryBlue.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    color: isDanger ? Colors.red : AppConstants.primaryBlue,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppConstants.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppConstants.primaryBlue,
                          ),
                        ),
                      )
                    : Icon(
                        Icons.chevron_right,
                        color:
                            isDanger ? Colors.red : AppConstants.textSecondary,
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTip(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          color: AppConstants.textSecondary,
          height: 1.5,
        ),
      ),
    );
  }
}
