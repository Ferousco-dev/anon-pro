import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/constants.dart';

class ModerationKeywordsScreen extends StatefulWidget {
  const ModerationKeywordsScreen({super.key});

  @override
  State<ModerationKeywordsScreen> createState() =>
      _ModerationKeywordsScreenState();
}

class _ModerationKeywordsScreenState extends State<ModerationKeywordsScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  List<Map<String, dynamic>> _keywords = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadKeywords();
  }

  Future<void> _loadKeywords() async {
    try {
      setState(() => _isLoading = true);
      final response = await _client
          .from('moderation_keywords')
          .select('*')
          .order('created_at', ascending: false);
      setState(() {
        _keywords = List<Map<String, dynamic>>.from(response as List);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showKeywordSheet({Map<String, dynamic>? keyword}) async {
    final controller =
        TextEditingController(text: keyword?['keyword'] as String? ?? '');
    String severity = keyword?['severity'] as String? ?? 'medium';
    bool isActive = keyword?['is_active'] as bool? ?? true;

    await showModalBottomSheet(
      context: context,
      backgroundColor: AppConstants.darkGray,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final inset = MediaQuery.of(context).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: inset + 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                keyword == null ? 'Add Keyword' : 'Edit Keyword',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Keyword',
                  labelStyle: TextStyle(color: AppConstants.textSecondary),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: severity,
                dropdownColor: AppConstants.darkGray,
                decoration: const InputDecoration(
                  labelText: 'Severity',
                  labelStyle: TextStyle(color: AppConstants.textSecondary),
                ),
                items: const [
                  DropdownMenuItem(value: 'low', child: Text('Low')),
                  DropdownMenuItem(value: 'medium', child: Text('Medium')),
                  DropdownMenuItem(value: 'high', child: Text('High')),
                ],
                onChanged: (value) {
                  severity = value ?? 'medium';
                },
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                value: isActive,
                onChanged: (value) => isActive = value,
                activeColor: AppConstants.primaryBlue,
                title: const Text('Active',
                    style: TextStyle(color: Colors.white)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (keyword != null)
                    TextButton(
                      onPressed: () async {
                        await _client
                            .from('moderation_keywords')
                            .delete()
                            .eq('id', keyword['id']);
                        if (mounted) Navigator.pop(context);
                        await _loadKeywords();
                      },
                      child: const Text('Delete',
                          style: TextStyle(color: Colors.redAccent)),
                    ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: () async {
                      final text = controller.text.trim();
                      if (text.isEmpty) return;
                      if (keyword == null) {
                        await _client.from('moderation_keywords').insert({
                          'keyword': text,
                          'severity': severity,
                          'is_active': isActive,
                          'created_by': _client.auth.currentUser?.id,
                        });
                      } else {
                        await _client.from('moderation_keywords').update({
                          'keyword': text,
                          'severity': severity,
                          'is_active': isActive,
                        }).eq('id', keyword['id']);
                      }
                      if (mounted) Navigator.pop(context);
                      await _loadKeywords();
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.black,
      appBar: AppBar(
        title: const Text('Moderation Keywords'),
        backgroundColor: AppConstants.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _showKeywordSheet(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppConstants.primaryBlue),
            )
          : RefreshIndicator(
              onRefresh: _loadKeywords,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _keywords.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final keyword = _keywords[index];
                  return ListTile(
                    tileColor: AppConstants.darkGray,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    title: Text(
                      keyword['keyword'] as String,
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      '${keyword['severity']} • ${keyword['is_active'] == true ? 'Active' : 'Off'}',
                      style:
                          const TextStyle(color: AppConstants.textSecondary),
                    ),
                    trailing: const Icon(Icons.edit, color: Colors.white70),
                    onTap: () => _showKeywordSheet(keyword: keyword),
                  );
                },
              ),
            ),
    );
  }
}
