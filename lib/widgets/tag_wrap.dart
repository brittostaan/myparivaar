import 'package:flutter/material.dart';

class TagWrap extends StatelessWidget {
  final List<String> tags;
  final int maxVisible;

  const TagWrap({
    super.key,
    required this.tags,
    this.maxVisible = 3,
  });

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) {
      return const SizedBox.shrink();
    }

    final visibleTags = tags.take(maxVisible).toList();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final tag in visibleTags)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              '#$tag',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Color(0xFF475569),
              ),
            ),
          ),
        if (tags.length > maxVisible)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              '+${tags.length - maxVisible}',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Color(0xFF475569),
              ),
            ),
          ),
      ],
    );
  }
}
