import 'package:flutter/material.dart';

/// Deliberate per-account consent. Dismissal is always a refusal; accepting
/// creates private readable copies, it never grants public-link access.
Future<bool> askDiagnosticConsent(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Enable readable diagnostics?'),
        content: const SingleChildScrollView(
          child: Text(
            'Koop will keep a readable health report and up to 48 hours of '
            'heart rate, movement and beat intervals in Drive → Koop → Diagnostics. '
            'These diagnostic copies are not passphrase-encrypted. Your full backups stay encrypted.\n\n'
            'Use the same Google account in Codex, then paste the report link once. '
            'When you ask for help, the connected chat can read updated reports '
            'if its Drive permissions allow access. Koop does not send data to a chat automatically.\n\n'
            'Reports update while Koop is open after sync, at most every 15 minutes. '
            'Only changed hourly recordings upload. Turning this off stops updates; '
            'existing copies remain in Drive until you delete the Diagnostics folder.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Enable diagnostics'),
          ),
        ],
      ),
    ) ??
    false;
