import 'package:flutter/material.dart';

import '../utils/tag_utils.dart';

class TagInputSection extends StatefulWidget {
  final TextEditingController controller;
  final List<String> suggestions;
  final String labelText;
  final String helperText;

  const TagInputSection({
    super.key,
    required this.controller,
    this.suggestions = const [],
    this.labelText = 'Tags (optional)',
    this.helperText = 'Comma-separated tags. Use family names or your own keywords.',
  });

  @override
  State<TagInputSection> createState() => _TagInputSectionState();
}

class _TagInputSectionState extends State<TagInputSection> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant TagInputSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _replaceTags(List<String> tags) {
    widget.controller.text = joinTags(tags);
    widget.controller.selection = TextSelection.collapsed(
      offset: widget.controller.text.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tags = parseTags(widget.controller.text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: widget.controller,
          decoration: InputDecoration(
            labelText: widget.labelText,
            helperText: widget.helperText,
            hintText: 'mom, school, medical, vacation',
          ),
          minLines: 1,
          maxLines: 2,
        ),
        if (widget.suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.suggestions.map((suggestion) {
              return ActionChip(
                label: Text(suggestion),
                onPressed: () => _replaceTags([...tags, suggestion]),
              );
            }).toList(),
          ),
        ],
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tags.map((tag) {
              return Chip(
                label: Text(tag),
                onDeleted: () => _replaceTags([...tags]..remove(tag)),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}
