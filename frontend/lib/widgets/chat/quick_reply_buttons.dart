import 'package:flutter/material.dart';

class QuickReplyButtons extends StatelessWidget {
  final List<String> replies;
  final Function(String) onTap;

  const QuickReplyButtons({
    super.key,
    required this.replies,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: replies.map((reply) {
        return ActionChip(
          label: Text(reply),
          onPressed: () => onTap(reply),
          backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
          labelStyle: TextStyle(
            color: Theme.of(context).colorScheme.primary,
          ),
        );
      }).toList(),
    );
  }
} 