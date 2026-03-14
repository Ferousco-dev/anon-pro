import 'package:flutter/material.dart';
import '../../models/ai_knowledge_entry.dart';
import '../../services/ai_knowledge_admin_service.dart';
import '../../utils/constants.dart';

class AiKnowledgeAdminScreen extends StatefulWidget {
  const AiKnowledgeAdminScreen({super.key});

  @override
  State<AiKnowledgeAdminScreen> createState() => _AiKnowledgeAdminScreenState();
}

class _AiKnowledgeAdminScreenState extends State<AiKnowledgeAdminScreen> {
  final AiKnowledgeAdminService _service = AiKnowledgeAdminService();
  List<AiKnowledgeEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    setState(() => _loading = true);
    try {
      final entries = await _service.fetchEntries();
      setState(() => _entries = entries);
    } catch (e) {
      debugPrint('Failed to load AI knowledge entries: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _showEntrySheet({AiKnowledgeEntry? entry}) async {
    final topicController =
        TextEditingController(text: entry?.topic ?? '');
    final contentController =
        TextEditingController(text: entry?.content ?? '');
    final keywordsController = TextEditingController(
      text: entry?.keywords.join(', ') ?? '',
    );
    var isActive = entry?.isActive ?? true;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppConstants.mediumGray,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final viewInsets = MediaQuery.of(context).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: viewInsets + 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                entry == null ? 'Add Knowledge' : 'Edit Knowledge',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: topicController,
                decoration: const InputDecoration(
                  labelText: 'Topic (e.g., core, safety_privacy)',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentController,
                decoration: const InputDecoration(
                  labelText: 'Content',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
                style: const TextStyle(color: Colors.white),
                maxLines: 4,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: keywordsController,
                decoration: const InputDecoration(
                  labelText: 'Keywords (comma separated)',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 12),
              if (entry != null)
                SwitchListTile(
                  value: isActive,
                  activeColor: AppConstants.primaryBlue,
                  onChanged: (value) => setState(() => isActive = value),
                  title: const Text(
                    'Active',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (entry != null)
                    TextButton(
                      onPressed: () async {
                        await _service.deleteEntry(entry.id);
                        if (mounted) Navigator.pop(context);
                        await _loadEntries();
                      },
                      child: const Text(
                        'Delete',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: () async {
                      final topic = topicController.text.trim();
                      final content = contentController.text.trim();
                      if (topic.isEmpty || content.isEmpty) return;
                      final keywords = keywordsController.text
                          .split(',')
                          .map((k) => k.trim())
                          .where((k) => k.isNotEmpty)
                          .toList();

                      if (entry == null) {
                        await _service.createEntry(
                          topic: topic,
                          content: content,
                          keywords: keywords,
                        );
                      } else {
                        await _service.updateEntry(
                          id: entry.id,
                          topic: topic,
                          content: content,
                          keywords: keywords,
                          isActive: isActive,
                        );
                      }

                      if (mounted) Navigator.pop(context);
                      await _loadEntries();
                    },
                    child: Text(entry == null ? 'Add' : 'Save'),
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
        title: const Text('AI Knowledge'),
        backgroundColor: AppConstants.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _showEntrySheet(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadEntries,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _entries.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final entry = _entries[index];
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppConstants.darkGray,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppConstants.lightGray.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    entry.topic,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (!entry.isActive)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.redAccent.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Text(
                                        'Inactive',
                                        style: TextStyle(
                                          color: Colors.redAccent,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                entry.content,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.white),
                              onPressed: () => _showEntrySheet(entry: entry),
                            ),
                            Switch(
                              value: entry.isActive,
                              activeColor: AppConstants.primaryBlue,
                              onChanged: (value) async {
                                await _service.updateEntry(
                                  id: entry.id,
                                  isActive: value,
                                );
                                await _loadEntries();
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}
