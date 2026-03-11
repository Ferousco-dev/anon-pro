import 'package:flutter/material.dart';
import '../../utils/constants.dart';
import '../../main.dart';

class StoriesScreen extends StatefulWidget {
  const StoriesScreen({super.key});

  @override
  State<StoriesScreen> createState() => _StoriesScreenState();
}

class _StoriesScreenState extends State<StoriesScreen> {
  @override
  void initState() {
    super.initState();
    // Navigate to current user's profile
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentUser = supabase.auth.currentUser;
      if (currentUser != null && currentUser.id.isNotEmpty) {
        print(
            'StoriesScreen: Navigating to profile with userId: ${currentUser.id}');
        Navigator.pushReplacementNamed(context, '/profile',
            arguments: currentUser.id);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please log in to view your profile'),
            backgroundColor: AppConstants.red,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.black,
      appBar: AppBar(
        backgroundColor: AppConstants.black,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Image.asset(
              'assets/images/anon.png',
              height: 32,
            ),
            const SizedBox(width: 8),
            const Text(
              'ANONPRO',
              style: TextStyle(
                color: AppConstants.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        centerTitle: false,
        actions: [
          IconButton(
            onPressed: () {
              // TODO: Navigate to search screen
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Search coming soon!')),
              );
            },
            icon: const Icon(Icons.search, color: AppConstants.white),
          ),
          IconButton(
            onPressed: () {
              final currentUser = supabase.auth.currentUser;
              if (currentUser != null && currentUser.id.isNotEmpty) {
                Navigator.pushNamed(context, '/profile',
                    arguments: currentUser.id);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please log in to view profile'),
                    backgroundColor: AppConstants.red,
                  ),
                );
              }
            },
            icon: const Icon(Icons.person, color: AppConstants.white),
          ),
        ],
      ),
      body: const Center(
        child: CircularProgressIndicator(
          color: AppConstants.primaryBlue,
        ),
      ),
    );
  }
}
