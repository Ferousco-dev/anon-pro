import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/connectivity_provider.dart';

class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  bool _isOnline = true;
  bool _showBanner = false;
  bool _showBackOnline = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<ConnectivityProvider>();
      _isOnline = provider.isOnline;

      if (!_isOnline) {
        // app started offline
        setState(() {
          _showBanner = true;
          _showBackOnline = false;
        });
      }

      provider.addListener(_onConnectivityChanged);
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    context.read<ConnectivityProvider>().removeListener(_onConnectivityChanged);
    super.dispose();
  }

  void _onConnectivityChanged() {
    final provider = context.read<ConnectivityProvider>();
    final nowOnline = provider.isOnline;

    if (_isOnline != nowOnline) {
      if (!nowOnline) {
        // went offline
        setState(() {
          _showBanner = true;
          _showBackOnline = false;
        });
        _hideTimer?.cancel();
      } else {
        // back online
        setState(() {
          _showBanner = true;
          _showBackOnline = true;
        });

        _hideTimer?.cancel();
        _hideTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _showBanner = false;
              _showBackOnline = false;
            });
          }
        });
      }
      _isOnline = nowOnline;
    }
  }

  void _dismissBanner() {
    _hideTimer?.cancel();
    setState(() {
      _showBanner = false;
      _showBackOnline = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_showBanner) return const SizedBox.shrink();

    final backgroundColor = _showBackOnline
        ? Colors.green.withOpacity(0.32)
        : Colors.red.withOpacity(0.32);
    final icon = _showBackOnline ? Icons.wifi : Icons.wifi_off;
    final text = _showBackOnline ? 'Back Online' : 'Offline';

    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _dismissBanner,
                child: const Icon(Icons.close, size: 18, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
