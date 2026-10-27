import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../auth/auth_controller.dart';
import '../screens/login_screen.dart';

IconData postTypeIcon(Post p) {
  if (p.isVideo) return Icons.videocam_outlined;
  if (p.isAudio) return Icons.graphic_eq;
  if (p.isText) return Icons.notes;
  return Icons.photo_outlined;
}

/// Asks for a reason (signing in first if needed) and sends the report to the moderators.
Future<void> reportPostFlow(BuildContext context, Post post) async {
  final auth = context.read<AuthController>();
  final api = context.read<ApiClient>();
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  if (!auth.signedIn) {
    final ok = await navigator.push<bool>(MaterialPageRoute(builder: (_) => const LoginScreen()));
    if (ok != true || !context.mounted) return;
  }
  final reason = await showDialog<String>(context: context, builder: (_) => const _ReportDialog());
  if (reason == null || reason.trim().isEmpty) return;
  try {
    await api.reportPost(post.id, reason);
    messenger.showSnackBar(const SnackBar(content: Text('Thanks. A moderator will take a look.')));
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog();

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Report this post'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 500,
        maxLines: 3,
        decoration: const InputDecoration(hintText: 'What is wrong with it?'),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _controller.text.trim().isEmpty ? null : () => Navigator.pop(context, _controller.text),
          child: const Text('Send report'),
        ),
      ],
    );
  }
}
