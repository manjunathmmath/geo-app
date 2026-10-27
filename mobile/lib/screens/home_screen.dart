import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../auth/auth_controller.dart';
import 'compose_screen.dart';
import 'here_screen.dart';
import 'login_screen.dart';
import 'me_screen.dart';
import 'post_chooser.dart';

/// Two tabs, Here and Me, with the + button between them for posting.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  Future<void> _newPost() async {
    final auth = context.read<AuthController>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    if (!auth.signedIn) {
      final ok = await navigator.push<bool>(MaterialPageRoute(builder: (_) => const LoginScreen()));
      if (ok != true || !mounted) return;
    }
    final mode = await showPostChooser(context);
    if (mode == null || !mounted) return;
    final post = await navigator.push<Post>(MaterialPageRoute(builder: (_) => ComposeScreen(mode: mode)));
    if (post == null || !mounted) return;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(post.status == 'APPROVED' ? 'Published. People nearby can see it now.' : 'Sent for review. A moderator will check it.'),
        action: SnackBarAction(label: 'View', onPressed: () => setState(() => _index = 1)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        // IndexedStack keeps each tab's scroll position and state while you switch tabs.
        children: [
          HereScreen(active: _index == 0, onPost: _newPost),
          MeScreen(active: _index == 1),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _newPost,
        tooltip: 'New post',
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            Expanded(child: _NavButton(icon: Icons.near_me_outlined, selectedIcon: Icons.near_me, label: 'Here', selected: _index == 0, onTap: () => setState(() => _index = 0))),
            const SizedBox(width: 72), // the space under the + button
            Expanded(child: _NavButton(icon: Icons.person_outline, selectedIcon: Icons.person, label: 'Me', selected: _index == 1, onTap: () => setState(() => _index = 1))),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.selectedIcon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? selectedIcon : icon, color: color),
            Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
          ],
        ),
      ),
    );
  }
}
