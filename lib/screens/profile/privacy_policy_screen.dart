import 'package:flutter/material.dart';
import '../../utils/constants.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.black,
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        backgroundColor: AppConstants.black,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _Section(
            title: 'Overview',
            body:
                'AnonPro is built for anonymous sharing and respectful communities. '
                'This policy explains what data we collect and how we use it.',
          ),
          _Section(
            title: 'Data We Collect',
            body:
                'Account data (email, alias, display name), content data (posts, '
                'comments, messages), device data for troubleshooting, and '
                'notification tokens for push delivery.',
          ),
          _Section(
            title: 'How We Use Data',
            body:
                'To operate app features, prevent abuse, and improve performance.',
          ),
          _Section(
            title: 'Sharing',
            body:
                'We do not sell personal data. We use trusted service providers '
                '(Supabase, Firebase) to run the app.',
          ),
          _Section(
            title: 'Your Choices',
            body:
                'You can update profile info, manage notifications, and request '
                'account deletion by contacting support.',
          ),
          _Section(
            title: 'Contact',
            body: 'support@anonpro.app',
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;

  const _Section({
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              color: AppConstants.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
