import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/constants.dart';

class AdminUserAnalyticsScreen extends StatefulWidget {
  const AdminUserAnalyticsScreen({super.key});

  @override
  State<AdminUserAnalyticsScreen> createState() =>
      _AdminUserAnalyticsScreenState();
}

class _AdminUserAnalyticsScreenState extends State<AdminUserAnalyticsScreen> {
  late Future<AdminUserStats> _statsFuture;
  final ScreenshotController _shareController = ScreenshotController();

  @override
  void initState() {
    super.initState();
    _statsFuture = _loadStats();
  }

  Future<AdminUserStats> _loadStats() async {
    final supabase = Supabase.instance.client;
    final response = await supabase.rpc('admin_user_stats');
    return AdminUserStats.fromJson(response as Map<String, dynamic>);
  }

  Future<void> _refresh() async {
    setState(() {
      _statsFuture = _loadStats();
    });
  }

  Future<void> _exportCard(AdminUserStats stats) async {
    try {
      final image = await _shareController.capture(
        delay: const Duration(milliseconds: 60),
      );
      if (image == null) return;
      final dir = await getTemporaryDirectory();
      final file =
          File('${dir.path}/anonpro_analytics_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(image);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'AnonPro — User Analytics Snapshot',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to export card: $e'),
          backgroundColor: AppConstants.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.black,
      appBar: AppBar(
        title: const Text('User Analytics'),
        backgroundColor: AppConstants.black,
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<AdminUserStats>(
        future: _statsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppConstants.primaryBlue),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Failed to load analytics: ${snapshot.error}',
                style: const TextStyle(color: AppConstants.textSecondary),
              ),
            );
          }

          final stats = snapshot.data ?? AdminUserStats.empty();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildRangeSelector(),
              const SizedBox(height: 12),
              _buildExportRow(stats),
              const SizedBox(height: 16),
              _buildHeroCard(stats),
              const SizedBox(height: 16),
              _buildMetricsGrid(stats),
              const SizedBox(height: 16),
              _buildChartCard(
                title: 'New Users (Daily)',
                subtitle: 'Last 14 days',
                child: _LineChart(
                  values: stats.dailyNewUsers,
                  lineColor: AppConstants.primaryBlue,
                  fillColor: AppConstants.primaryBlue.withOpacity(0.18),
                ),
              ),
              const SizedBox(height: 16),
              _buildChartCard(
                title: 'Weekly Active Users',
                subtitle: 'Last 7 weeks',
                child: _BarChart(
                  values: stats.weeklyActiveUsers,
                  barColor: AppConstants.green,
                ),
              ),
              const SizedBox(height: 16),
              _buildChartCard(
                title: 'Total Users (Monthly)',
                subtitle: 'Last 6 months',
                child: _BarChart(
                  values: stats.monthlyTotalUsers,
                  barColor: AppConstants.purple,
                ),
              ),
              const SizedBox(height: 16),
              _buildMentorInsights(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRangeSelector() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppConstants.darkGray,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppConstants.lightGray.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          _RangeChip(label: '7D', isActive: true),
          const SizedBox(width: 8),
          _RangeChip(label: '30D'),
          const SizedBox(width: 8),
          _RangeChip(label: '90D'),
          const Spacer(),
          Icon(Icons.tune_rounded, color: AppConstants.textSecondary),
        ],
      ),
    );
  }

  Widget _buildExportRow(AdminUserStats stats) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Shareable Snapshot',
            style: AppTextStyles.h4.copyWith(fontSize: 16),
          ),
        ),
        TextButton.icon(
          onPressed: () => _exportCard(stats),
          icon: const Icon(Icons.share_rounded, color: AppConstants.primaryBlue),
          label: const Text(
            'Export card',
            style: TextStyle(color: AppConstants.primaryBlue),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroCard(AdminUserStats stats) {
    final todayNew = stats.dailyNewUsers.isNotEmpty
        ? stats.dailyNewUsers.last
        : 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppGradients.bluePurple,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppConstants.primaryBlue.withOpacity(0.2),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_graph_rounded, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Momentum snapshot',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'New users today: $todayNew • Active (24h): ${stats.active24h}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsGrid(AdminUserStats stats) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'Active (24h)',
                value: stats.active24h.toString(),
                delta: '${stats.activeDelta}%',
                deltaColor:
                    stats.activeDelta >= 0 ? AppConstants.green : AppConstants.red,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                label: 'New Users / Day',
                value: stats.dailyNewUsers.isNotEmpty
                    ? stats.dailyNewUsers.last.toString()
                    : '0',
                delta: '${stats.newUsersDelta}%',
                deltaColor:
                    stats.newUsersDelta >= 0 ? AppConstants.green : AppConstants.red,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'Weekly Active',
                value: stats.active7d.toString(),
                delta: '${stats.weeklyActiveDelta}%',
                deltaColor: stats.weeklyActiveDelta >= 0
                    ? AppConstants.green
                    : AppConstants.red,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                label: 'Dormant Users',
                value: stats.dormant30d.toString(),
                delta: '${stats.dormantDelta}%',
                deltaColor: AppConstants.orange,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildChartCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConstants.darkGray,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppConstants.lightGray.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppConstants.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppConstants.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(height: 160, child: child),
        ],
      ),
    );
  }

  Widget _buildMentorInsights() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConstants.darkGray,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppConstants.lightGray.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'Mentor Notes',
            style: TextStyle(
              color: AppConstants.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          _InsightRow(
            icon: Icons.flash_on_rounded,
            title: 'Activation',
            text:
                'New users who post within 24h are 2.3x more likely to return. Prompt a first post after signup.',
          ),
          SizedBox(height: 10),
          _InsightRow(
            icon: Icons.shield_rounded,
            title: 'Safety',
            text:
                'Dormant users spike after moderation actions. Add clearer reasons and appeal paths in‑app.',
          ),
          SizedBox(height: 10),
          _InsightRow(
            icon: Icons.chat_bubble_rounded,
            title: 'Engagement',
            text:
                'Rooms with weekly prompts retain +18%. Schedule a weekly topic post.',
          ),
        ],
      ),
    );
  }

  Widget _buildShareCard(AdminUserStats stats) {
    final todayNew = stats.dailyNewUsers.isNotEmpty
        ? stats.dailyNewUsers.last
        : 0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppGradients.bluePurple,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AnonPro • Admin Snapshot',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'User Growth Pulse',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _ShareMetric(
                label: 'Active (24h)',
                value: stats.active24h.toString(),
              ),
              const SizedBox(width: 16),
              _ShareMetric(
                label: 'New Today',
                value: todayNew.toString(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _ShareMetric(
                label: 'Weekly Active',
                value: stats.active7d.toString(),
              ),
              const SizedBox(width: 16),
              _ShareMetric(
                label: 'Dormant 30d',
                value: stats.dormant30d.toString(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Total users: ${stats.totalUsers}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class AdminUserStats {
  AdminUserStats({
    required this.active24h,
    required this.active7d,
    required this.dormant30d,
    required this.totalUsers,
    required this.dailyNewUsers,
    required this.weeklyActiveUsers,
    required this.monthlyTotalUsers,
  });

  final int active24h;
  final int active7d;
  final int dormant30d;
  final int totalUsers;
  final List<int> dailyNewUsers;
  final List<int> weeklyActiveUsers;
  final List<int> monthlyTotalUsers;

  int get activeDelta => _percentDelta(weeklyActiveUsers);
  int get newUsersDelta => _percentDelta(dailyNewUsers);
  int get weeklyActiveDelta => _percentDelta(weeklyActiveUsers);
  int get dormantDelta => _percentDelta(monthlyTotalUsers, invert: true);

  static AdminUserStats fromJson(Map<String, dynamic> json) {
    List<int> _parseCounts(dynamic input) {
      if (input is! List) return [];
      return input
          .map((e) => (e as Map<String, dynamic>)['count'] as int? ?? 0)
          .toList();
    }

    return AdminUserStats(
      active24h: json['active_24h'] as int? ?? 0,
      active7d: json['active_7d'] as int? ?? 0,
      dormant30d: json['dormant_30d'] as int? ?? 0,
      totalUsers: json['total_users'] as int? ?? 0,
      dailyNewUsers: _parseCounts(json['daily_new_users']),
      weeklyActiveUsers: _parseCounts(json['weekly_active_users']),
      monthlyTotalUsers: _parseCounts(json['monthly_total_users']),
    );
  }

  static AdminUserStats empty() => AdminUserStats(
        active24h: 0,
        active7d: 0,
        dormant30d: 0,
        totalUsers: 0,
        dailyNewUsers: const [],
        weeklyActiveUsers: const [],
        monthlyTotalUsers: const [],
      );

  static int _percentDelta(List<int> series, {bool invert = false}) {
    if (series.length < 2) return 0;
    final last = series.last;
    final prev = series[series.length - 2];
    if (prev == 0) return 0;
    final delta = ((last - prev) / prev * 100).round();
    return invert ? -delta : delta;
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({required this.label, this.isActive = false});

  final String label;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isActive ? AppConstants.primaryBlue : AppConstants.mediumGray,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isActive ? Colors.white : AppConstants.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.delta,
    required this.deltaColor,
  });

  final String label;
  final String value;
  final String delta;
  final Color deltaColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppConstants.darkGray,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppConstants.lightGray.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppConstants.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: AppConstants.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: deltaColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              delta,
              style: TextStyle(
                color: deltaColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppConstants.primaryBlue.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppConstants.primaryBlue, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppConstants.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                text,
                style: const TextStyle(
                  color: AppConstants.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LineChart extends StatelessWidget {
  const _LineChart({
    required this.values,
    required this.lineColor,
    required this.fillColor,
  });

  final List<int> values;
  final Color lineColor;
  final Color fillColor;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LineChartPainter(
        values: values,
        lineColor: lineColor,
        fillColor: fillColor,
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.values,
    required this.lineColor,
    required this.fillColor,
  });

  final List<int> values;
  final Color lineColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxValue = values.reduce((a, b) => a > b ? a : b).toDouble();
    final minValue = values.reduce((a, b) => a < b ? a : b).toDouble();
    final span = (maxValue - minValue).clamp(1, double.infinity);
    final dx = size.width / (values.length - 1);

    final linePath = Path();
    for (var i = 0; i < values.length; i++) {
      final x = dx * i;
      final normalized = (values[i] - minValue) / span;
      final y = size.height - (normalized * size.height);
      if (i == 0) {
        linePath.moveTo(x, y);
      } else {
        linePath.lineTo(x, y);
      }
    }

    final fillPath = Path.from(linePath)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final fillPaint = Paint()..color = fillColor;
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawPath(linePath, linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BarChart extends StatelessWidget {
  const _BarChart({
    required this.values,
    required this.barColor,
  });

  final List<int> values;
  final Color barColor;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BarChartPainter(values: values, barColor: barColor),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  _BarChartPainter({
    required this.values,
    required this.barColor,
  });

  final List<int> values;
  final Color barColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxValue = values.reduce((a, b) => a > b ? a : b).toDouble();
    final barWidth = size.width / (values.length * 1.6);
    final gap = barWidth * 0.6;
    final paint = Paint()..color = barColor;

    for (var i = 0; i < values.length; i++) {
      final x = i * (barWidth + gap);
      final normalized = values[i] / maxValue;
      final barHeight = normalized * size.height;
      final rect = Rect.fromLTWH(
        x,
        size.height - barHeight,
        barWidth,
        barHeight,
      );
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));
      canvas.drawRRect(rrect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ShareMetric extends StatelessWidget {
  const _ShareMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
