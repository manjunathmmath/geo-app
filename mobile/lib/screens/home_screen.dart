import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../widgets/sign_in_prompt.dart';
import 'login_screen.dart';
import 'my_posts_screen.dart';
import 'nearby_screen.dart';
import 'post_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('GeoApp'),
        actions: [
          if (!auth.signedIn)
            TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<bool>(builder: (_) => const LoginScreen())),
              child: const Text('Sign in'),
            )
          else
            PopupMenuButton<String>(
              icon: const Icon(Icons.account_circle_outlined),
              tooltip: 'Account',
              itemBuilder: (_) => [
                PopupMenuItem<String>(enabled: false, child: Text(auth.user!.email)),
                const PopupMenuItem<String>(value: 'out', child: Text('Sign out')),
              ],
              onSelected: (_) => auth.logout(),
            ),
        ],
      ),
      // IndexedStack keeps each tab's state (for example a chosen photo) while you switch tabs.
      body: IndexedStack(
        index: _index,
        children: [
          NearbyScreen(active: _index == 0),
          auth.signedIn
              ? PostScreen(active: _index == 1)
              : const SignInPrompt(message: 'Sign in to post something at your location.'),
          auth.signedIn
              ? MyPostsScreen(active: _index == 2)
              : const SignInPrompt(message: 'Sign in to see your posts and whether they were approved.'),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.near_me_outlined), selectedIcon: Icon(Icons.near_me), label: 'Nearby'),
          NavigationDestination(icon: Icon(Icons.add_a_photo_outlined), selectedIcon: Icon(Icons.add_a_photo), label: 'Post'),
          NavigationDestination(icon: Icon(Icons.list_alt_outlined), selectedIcon: Icon(Icons.list_alt), label: 'My posts'),
        ],
      ),
    );
  }
}
