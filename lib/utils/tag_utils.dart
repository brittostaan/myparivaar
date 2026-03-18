List<String> parseTags(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];

  final seen = <String>{};
  final tags = <String>[];

  for (final part in raw.split(',')) {
    final normalized = part.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) continue;
    final key = normalized.toLowerCase();
    if (seen.add(key)) {
      tags.add(normalized);
    }
  }

  return tags;
}

String joinTags(List<String>? tags) {
  if (tags == null || tags.isEmpty) return '';
  return tags.join(', ');
}
