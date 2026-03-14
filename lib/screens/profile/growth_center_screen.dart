import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/constants.dart';

class GrowthCenterScreen extends StatefulWidget {
  const GrowthCenterScreen({super.key});

  @override
  State<GrowthCenterScreen> createState() => _GrowthCenterScreenState();
}

class _GrowthCenterScreenState extends State<GrowthCenterScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  Map<String, dynamic> _onboarding = {};
  List<Map<String, dynamic>> _achievements = [];
  List<Map<String, dynamic>> _userAchievements = [];
  List<Map<String, dynamic>> _dailyChallenges = [];
  List<Map<String, dynamic>> _userChallenges = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null) return;

    try {
      setState(() => _isLoading = true);

      final onboardingRes = await _client
          .from('user_onboarding')
          .select()
          .eq('user_id', currentUser.id)
          .maybeSingle();
      if (onboardingRes == null) {
        await _client.from('user_onboarding').insert({
          'user_id': currentUser.id,
        });
      }
      final freshOnboarding = await _client
          .from('user_onboarding')
          .select()
          .eq('user_id', currentUser.id)
          .maybeSingle();

      final achievementsRes = await _client
          .from('achievements')
          .select()
          .eq('is_active', true);
      final userAchievementsRes = await _client
          .from('user_achievements')
          .select('achievement_id')
          .eq('user_id', currentUser.id);

      final dailyChallengesRes = await _client
          .from('daily_challenges')
          .select()
          .eq('is_active', true);
      final userChallengesRes = await _client
          .from('user_daily_challenges')
          .select('challenge_id, completed_at')
          .eq('user_id', currentUser.id)
          .eq('challenge_date', DateTime.now().toIso8601String().split('T').first);

      setState(() {
        _onboarding = freshOnboarding ?? {};
        _achievements = List<Map<String, dynamic>>.from(achievementsRes as List);
        _userAchievements =
            List<Map<String, dynamic>>.from(userAchievementsRes as List);
        _dailyChallenges =
            List<Map<String, dynamic>>.from(dailyChallengesRes as List);
        _userChallenges =
            List<Map<String, dynamic>>.from(userChallengesRes as List);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleOnboarding(String field, bool value) async {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null) return;
    await _client
        .from('user_onboarding')
        .update({field: value, 'updated_at': DateTime.now().toIso8601String()})
        .eq('user_id', currentUser.id);
    await _loadData();
  }

  bool _hasAchievement(String id) {
    return _userAchievements.any((a) => a['achievement_id'] == id);
  }

  bool _isChallengeCompleted(String id) {
    return _userChallenges.any((c) => c['challenge_id'] == id);
  }

  Future<void> _completeChallenge(String id) async {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null) return;
    await _client.from('user_daily_challenges').upsert({
      'user_id': currentUser.id,
      'challenge_id': id,
      'challenge_date': DateTime.now().toIso8601String().split('T').first,
      'completed_at': DateTime.now().toIso8601String(),
    });
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.black,
      appBar: AppBar(
        title: const Text('Growth Center'),
        backgroundColor: AppConstants.black,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppConstants.primaryBlue),
            )
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSectionTitle('Onboarding Checklist'),
                  _buildChecklistTile(
                    'Complete profile',
                    _onboarding['completed_profile'] == true,
                    (value) => _toggleOnboarding('completed_profile', value),
                  ),
                  _buildChecklistTile(
                    'Make first post',
                    _onboarding['first_post'] == true,
                    (value) => _toggleOnboarding('first_post', value),
                  ),
                  _buildChecklistTile(
                    'Follow someone',
                    _onboarding['first_follow'] == true,
                    (value) => _toggleOnboarding('first_follow', value),
                  ),
                  _buildChecklistTile(
                    'Send a DM',
                    _onboarding['first_dm'] == true,
                    (value) => _toggleOnboarding('first_dm', value),
                  ),
                  const SizedBox(height: 20),
                  _buildSectionTitle('Daily Challenges'),
                  ..._dailyChallenges.map((challenge) {
                    final id = challenge['id'] as String;
                    final done = _isChallengeCompleted(id);
                    return ListTile(
                      tileColor: AppConstants.darkGray,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      title: Text(
                        challenge['title'] as String,
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        challenge['description'] as String,
                        style:
                            const TextStyle(color: AppConstants.textSecondary),
                      ),
                      trailing: done
                          ? const Icon(Icons.check_circle,
                              color: Colors.greenAccent)
                          : ElevatedButton(
                              onPressed: () => _completeChallenge(id),
                              child: const Text('Complete'),
                            ),
                    );
                  }).toList(),
                  const SizedBox(height: 20),
                  _buildSectionTitle('Achievements'),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _achievements.map((achievement) {
                      final id = achievement['id'] as String;
                      final unlocked = _hasAchievement(id);
                      final icon = achievement['icon'] as String? ?? '🏆';
                      return Container(
                        width: 160,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppConstants.darkGray,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: unlocked
                                ? AppConstants.primaryBlue
                                : AppConstants.lightGray.withOpacity(0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(icon, style: const TextStyle(fontSize: 24)),
                            const SizedBox(height: 6),
                            Text(
                              achievement['title'] as String,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              achievement['description'] as String,
                              style: const TextStyle(
                                  color: AppConstants.textSecondary,
                                  fontSize: 12),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              unlocked ? 'Unlocked' : 'Locked',
                              style: TextStyle(
                                color: unlocked
                                    ? Colors.greenAccent
                                    : Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildChecklistTile(
    String title,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeColor: AppConstants.primaryBlue,
      title: Text(title, style: const TextStyle(color: Colors.white)),
    );
  }
}
