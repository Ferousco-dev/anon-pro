import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/constants.dart';
import '../qa/anonymous_questions_screen.dart';
import '../confession_rooms/confession_rooms_screen.dart';
import 'streak_progress_screen.dart';
import 'notification_settings_screen.dart';
import 'growth_center_screen.dart';
import 'privacy_policy_screen.dart';

class ProfileMenuScreen extends StatefulWidget {
  final String userId;

  const ProfileMenuScreen({
    super.key,
    required this.userId,
  });

  @override
  State<ProfileMenuScreen> createState() => _ProfileMenuScreenState();
}

class _ProfileMenuScreenState extends State<ProfileMenuScreen> {
  @override
  Widget build(BuildContext context) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isOwner = currentUserId != null && currentUserId == widget.userId;

    return Scaffold(
      backgroundColor: AppConstants.black,
      appBar: AppBar(
        backgroundColor: AppConstants.darkGray,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Menu',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            children: [
              // Q&A Section
              _buildMenuCard(
                icon: Icons.help_outline_rounded,
                title: 'Q&A Room',
                description: 'Manage and answer questions from your followers',
                color: AppConstants.primaryBlue,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (ctx) => AnonymousQuestionsScreen(
                        userId: widget.userId,
                        isOwner: true,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),

              // Confession Rooms Section
              _buildMenuCard(
                icon: Icons.chat_bubble_outline,
                title: 'Confession Rooms',
                description: 'Join topic-based discussion rooms',
                color: Colors.purple,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (ctx) => ConfessionRoomsScreen(
                        userId: widget.userId,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),

              if (isOwner) ...[
                // Streak Section
                _buildMenuCard(
                  icon: Icons.local_fire_department_rounded,
                  title: 'Streak',
                  description: 'Track your engagement streak',
                  color: Colors.orange,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (ctx) => StreakProgressScreen(
                          userId: widget.userId,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
              ],
              _buildMenuCard(
                icon: Icons.rocket_launch_rounded,
                title: 'Growth Center',
                description: 'Checklist, daily challenges, achievements',
                color: Colors.teal,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (ctx) => const GrowthCenterScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              _buildMenuCard(
                icon: Icons.privacy_tip_rounded,
                title: 'Privacy Policy',
                description: 'How we collect and use data',
                color: Colors.blueGrey,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (ctx) => const PrivacyPolicyScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),

              // Policy Section
              _buildMenuCard(
                icon: Icons.policy_outlined,
                title: 'Policy',
                description: 'Read our app policies and guidelines',
                color: Colors.red,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (ctx) => const PolicyScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),

              if (isOwner)
                _buildMenuCard(
                  icon: Icons.notifications_active_rounded,
                  title: 'Notifications',
                  description: 'Manage push notification settings',
                  color: AppConstants.primaryBlue,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (ctx) => NotificationSettingsScreen(
                          userId: widget.userId,
                        ),
                      ),
                    );
                  },
                ),

              const SizedBox(height: 40),

              // Version info at bottom
              Center(
                child: Text(
                  'anonpro v1.10',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuCard({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppConstants.mediumGray,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: color.withOpacity(0.3),
            width: 1.5,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: color,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),

            // Title & Description
            Expanded(
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
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // Arrow
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: color,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

// Policy Screen
class PolicyScreen extends StatelessWidget {
  const PolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.black,
      appBar: AppBar(
        backgroundColor: AppConstants.darkGray,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Policies & Terms',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Privacy Policy
              _buildPolicySection(
                title: '📋 PRIVACY POLICY',
                content: '''Last Updated: March 14, 2026

AnonPro ("we," "us," "our," or "Company") operates the AnonPro mobile application (the "App"). This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use the App.

INFORMATION WE COLLECT
• Account Information: Email, username, password (hashed and encrypted)
• Profile Information: Avatar, bio, display name, verification status
• Usage Data: Posts, comments, likes, followers, streaks, karma points
• Device Information: Device type, OS version, unique device identifiers
• Communication Data: Messages, Q&A responses (encrypted)
• Analytics: App usage patterns, feature interactions, crash reports

ANONYMOUS POSTS
Anonymous posts are stored WITHOUT personally identifiable information. We cannot link anonymous posts to user accounts. Only platform admins can view metadata for policy enforcement purposes.

HOW WE USE YOUR DATA
• To provide and improve the App
• To personalize your experience
• To communicate about policy violations
• To prevent fraud and abuse
• To comply with legal obligations

DATA SECURITY
• All transmissions use industry-standard encryption (HTTPS/TLS)
• Private messages use end-to-end encryption
• Passwords are securely hashed
• Data stored on secure Supabase servers with regular backups

THIRD-PARTY SERVICES
We use:
• Supabase for database & authentication
• Firebase for push notifications
• Analytics tools for usage insights
None of these services receive personal data without your consent.

DATA RETENTION
• Active accounts: Data retained while account is active
• Deleted accounts: Permanently deleted after 30 days
• Posts/Messages: Retained until deletion by user

YOUR RIGHTS
• Access your personal data
• Correct inaccurate information
• Request data deletion (subject to legal holds)
• Opt-out of analytics
• Port your data

CHILDREN'S PRIVACY
AnonPro is only for users 13+ years old (or legal age in your region). We do not knowingly collect data from children under 13. If we discover such data, we will delete it immediately.

CHANGES TO THIS POLICY
We may update this policy. Changes become effective upon posting. Continued use implies acceptance.''',
              ),
              const SizedBox(height: 28),

              // Terms of Service
              _buildPolicySection(
                title: '⚖️ TERMS OF SERVICE',
                content: '''Last Updated: March 14, 2026

AGREEMENT TO TERMS
By accessing and using AnonPro, you accept and agree to be bound by these Terms. If you disagree with any part, you may not use the App.

USER ELIGIBILITY
• You must be at least 13 years old (or legal age in your jurisdiction)
• You must be able to enter into binding contracts
• You are responsible for maintaining account confidentiality

USER ACCOUNTS
• You are responsible for all activities under your account
• You agree to provide accurate, complete information
• You will not share your account with others
• Impersonation or misrepresentation is prohibited
• Account deletion is permanent after 30 days

USER-GENERATED CONTENT
You retain rights to content you create. By posting on AnonPro, you grant us a license to:
• Store and display your content
• Use for analytics and moderation
• You may not post:
  - Illegal content
  - Explicit/sexual material involving minors
  - Violence or threats
  - Hate speech or discrimination
  - Doxxing or personal information about others
  - Spam or misleading content
  - Copyrighted material without permission

ANONYMOUS POSTING
• Anonymous posts cannot be attributed to users
• You remain subject to community guidelines while anonymous
• Admins may investigate anonymous posts for policy violations

PROHIBITED CONDUCT
You agree NOT to:
• Harass, threaten, or abuse other users
• Circumvent security or moderation features
• Collect data without permission
• Reverse engineer or hack the App
• Impersonate others
• Spam or post repetitive content
• Violate any applicable laws

CONTENT REMOVAL & ACCOUNT TERMINATION
We reserve the right to:
• Remove prohibited content without notice
• Suspend or terminate accounts violating policies
• Ban repeat violators (permanent or temporary)
• Not liable for removed content
Violations are determined at our sole discretion.

DISCLAIMER OF WARRANTIES
THE APP IS PROVIDED "AS IS" WITHOUT WARRANTY. WE DISCLAIM ALL WARRANTIES, EXPRESS OR IMPLIED, INCLUDING MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.

LIMITATION OF LIABILITY
TO THE FULLEST EXTENT PERMITTED BY LAW, ANONPRO SHALL NOT BE LIABLE FOR:
• Data loss or corruption
• Unauthorized access
• Service interruptions
• User actions or content
• Third-party services
• Indirect, incidental, or consequential damages

INDEMNIFICATION
You agree to indemnify us from claims arising from your use of the App, violation of policies, or infringement of others' rights.

MODIFICATIONS
We may modify these Terms at any time. Continued use implies acceptance.

GOVERNING LAW
These Terms are governed by applicable law. Any disputes shall be resolved in appropriate courts.''',
              ),
              const SizedBox(height: 28),

              // Community Guidelines
              _buildPolicySection(
                title: '👥 COMMUNITY GUIDELINES',
                content: '''Last Updated: March 14, 2026

PURPOSE
Our community guidelines ensure AnonPro remains a safe, respectful space for genuine connection.

CORE VALUES
• Respect: Treat others with dignity
• Privacy: Protect identities and personal information
• Safety: Zero tolerance for violence or threats
• Authenticity: Be honest in interactions
• Inclusivity: Respect all backgrounds and beliefs

PROHIBITED CONTENT & BEHAVIOR

Violence & Harm
✗ Threats of violence against individuals or groups
✗ Instructions for self-harm or suicide
✗ Graphic violence or gore
✓ DO: Report violent content immediately

Harassment & Abuse
✗ Targeted harassment or bullying
✗ Coordinated attacks
✗ Sexual harassment or unwanted advances
✓ DO: Use block/report features

Hate & Discrimination
✗ Content attacking people based on protected characteristics
✗ Slurs or dehumanizing language
✗ Conspiracy theories targeting groups
✓ DO: Report hate speech

Sexual Content
✗ Explicit sexual material or pornography
✗ Sexual content involving minors (SEVERE VIOLATION)
✗ Non-consensual intimate images
✓ DO: Report immediately

Dangerous & Illegal
✗ Instructions for illegal activities
✗ Sale of illegal items
✗ Promotion of drug use
✓ DO: Contact authorities if needed

Misinformation
✗ False health claims (vaccines, treatments)
✗ Election misinformation
✗ Dangerous pseudoscience
✓ DO: Share verified sources

Spam
✗ Repetitive commercial spam
✗ Multi-level marketing schemes
✗ Bot networks and artificial engagement
✗ Phishing or scams
✓ DO: Report spam immediately

Privacy Violations
✗ Sharing others' personal information (doxxing)
✗ Sharing intimate content without consent
✗ Revealing anonymous identities
✓ DO: Protect others' privacy

ENFORCEMENT ACTIONS
Violations result in:
Level 1: Warning (first minor offense)
Level 2: Content removal (repeated violations)
Level 3: Account suspension (7-30 days)
Level 4: Permanent ban (severe violations)

SEVERE VIOLATIONS (Immediate Permanent Ban)
• Sexual content involving minors
• Real threats of violence
• Coordinated harassment campaigns
• Non-consensual intimate images
• Extreme hate speech

APPEALS PROCESS
Banned users can appeal via support@anonpro.app with explanation. Admins review within 7 business days.''',
              ),
              const SizedBox(height: 28),

              // Data & Privacy
              _buildPolicySection(
                title: '🔒 DATA & SECURITY',
                content: '''ENCRYPTION & SECURITY
✓ HTTPS/TLS for all communications
✓ End-to-end encryption for private messages
✓ Bcrypt password hashing
✓ Regular security audits
✓ Secure Supabase PostgreSQL backend

ANONYMOUS DATA PROTECTION
• Anonymous posts do NOT contain:
  - IP addresses visible to users
  - Device information
  - Location data
• Only encrypted transaction logs (admin-only access)
• Metadata only viewable for policy enforcement

DATA WE DON'T COLLECT
✗ Location data (unless explicitly enabled)
✗ Browsing history outside app
✗ Contacts or calendar access
✗ Phone numbers (unless provided)
✗ Biometric data
✗ Health/fitness information

DATA SHARING
We DO NOT share data with:
✗ Advertisers
✗ Data brokers
✗ Marketing companies
✗ Social media platforms (unless you explicitly connect)
✗ Third parties without your consent (except as legally required)

DATA DELETION POLICY
• Delete individual posts anytime
• Delete account → all data deleted after 30 days
• Bans may retain minimal data for fraud prevention
• Cannot recover deleted data

GDPR COMPLIANCE (EU USERS)
• Right to access your data
• Right to correct inaccuracies
• Right to erasure ("right to be forgotten")
• Right to data portability
• Right to restrict processing
Contact: privacy@anonpro.app

CCPA COMPLIANCE (CALIFORNIA USERS)
You have the right to:
• Know what data we collect
• Delete your personal information
• Opt-out of data sales (we don't sell data)
• Non-discrimination for exercising rights
Contact: ccpa@anonpro.app''',
              ),
              const SizedBox(height: 28),

              // Account & Moderation
              _buildPolicySection(
                title: '⚙️ ACCOUNT & MODERATION',
                content: '''ACCOUNT SECURITY
• You are responsible for maintaining account security
• Do not share passwords or login details
• Enable 2-factor authentication (when available)
• Report unauthorized access immediately
• We will never ask for your password

VERIFICATION PROGRAM
• Verified users receive a badge
• Granted at admin discretion for trusted members
• Based on community contribution and standing
• Can be revoked for policy violations

STREAKS & GAMIFICATION
• Streaks track consecutive days of engagement
• Broken by missed days (streaks reset to 0)
• Used for motivation and community recognition
• No financial value or rewards

KARMA SYSTEM
• Reflects community trust through post/comment interactions
• High karma ≠ immunity from rules
• Can be lost due to violations
• Used to determine visibility and eligibility

MODERATION PROCESS
1. Report submitted by user or detected by automated systems
2. Reviewed by moderation team (24-48 hours)
3. Action taken if violation confirmed
4. User notified of action
5. Appeal available within 30 days

ADMIN CONDUCT
• Admins must enforce policies equally
• Admins subject to same rules as users
• Conflicts of interest reported to leadership
• Separate appeals process for admin actions''',
              ),
              const SizedBox(height: 28),

              // Liability & Disclaimers
              _buildPolicySection(
                title: '⚠️ LIABILITY & DISCLAIMERS',
                content: '''AS-IS SERVICE
The App is provided "AS IS" without warranties. We do not guarantee:
• Uninterrupted availability
• Accurate or complete information
• Absence of harmful code
• Third-party service reliability

USER RESPONSIBILITY
You use the App at your own risk. You are responsible for:
• Verifying information before relying on it
• Protecting your account
• Your content and actions
• Complying with all laws

LIMITATION OF LIABILITY
AnonPro is NOT liable for:
• Data loss or corruption
• Service interruptions or downtime
• Unauthorized access (except due to our negligence)
• User actions or third-party conduct
• Indirect, incidental, consequential damages
Even if we've been advised of possibility.

THIRD-PARTY SERVICES
We are not responsible for:
• Third-party services (Supabase, Firebase)
• Links to external websites
• User-to-user interactions
• Content hosted by third parties

EMERGENCY RESPONSE
In emergencies (imminent harm, illegal activity), we will:
• Cooperate with law enforcement
• Provide minimal data necessary
• Preserve anonymity where possible
• Comply with legal process

CHANGES & DISCONTINUATION
We reserve the right to:
• Modify the App
• Change features or functionality
• Restrict access
• Discontinue the service (with notice if possible)''',
              ),
              const SizedBox(height: 28),

              // Contact & Support
              _buildPolicySection(
                title: '📧 CONTACT & SUPPORT',
                content: '''SUPPORT
For technical issues, feedback, or account inquiries:
• Email: support@anonpro.app
• In-app support form: Settings > Help > Contact Support
• Response time: 3-5 business days

REPORT VIOLATIONS
To report content violations:
• Use in-app report button on posts/profiles
• Email: moderation@anonpro.app
• For emergencies: Contact law enforcement

DATA & PRIVACY REQUESTS
Subject Access Requests (GDPR/CCPA):
• Email: privacy@anonpro.app
• Include account email and request type
• Response within 30-45 days

LEGAL INQUIRIES
For law enforcement or legal requests:
• Email: legal@anonpro.app
• Preserve all legal documents
• We comply with lawful requests only

APPEALS
To appeal moderation decisions:
• Email: appeals@anonpro.app
• Include username, date, action taken
• Explain why you believe it was unfair
• Review completed within 14 days

FEEDBACK & SUGGESTIONS
We welcome feedback:
• In-app feedback form: Settings > Feedback
• Email: feedback@anonpro.app
• Vote on features: Community > Feature Requests''',
              ),

              const SizedBox(height: 40),

              // Version info at bottom
              Center(
                child: Column(
                  children: [
                    Text(
                      'By using AnonPro, you agree to these policies.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'anonpro v1.10',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPolicySection({
    required String title,
    required String content,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppConstants.primaryBlue,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          content,
          style: TextStyle(
            color: Colors.grey[300],
            fontSize: 13,
            height: 1.7,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}
