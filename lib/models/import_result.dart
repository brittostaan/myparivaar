/// Represents a single row-level validation error returned by the Edge Function.
class RowError {
  const RowError({
    required this.row,
    required this.field,
    required this.message,
  });

  final int    row;
  final String field;
  final String message;

  factory RowError.fromJson(Map<String, dynamic> json) => RowError(
        row:     json['row']     as int,
        field:   json['field']   as String,
        message: json['message'] as String,
      );

  @override
  String toString() => 'Row $row [$field]: $message';
}

/// Result of a preview action — validated rows and any errors.
class ImportPreviewResult {
  const ImportPreviewResult({
    required this.type,
    required this.validRows,
    required this.errors,
    required this.validCount,
    required this.errorCount,
  });

  final String                        type;
  final List<Map<String, dynamic>>    validRows;
  final List<RowError>                errors;
  final int                           validCount;
  final int                           errorCount;

  bool get hasErrors => errorCount > 0;
  bool get isClean   => errorCount == 0;

  factory ImportPreviewResult.fromJson(Map<String, dynamic> json) =>
      ImportPreviewResult(
        type:       json['type']        as String,
        validCount: json['valid_count'] as int,
        errorCount: json['error_count'] as int,
        validRows:  (json['valid_rows'] as List)
            .cast<Map<String, dynamic>>(),
        errors: (json['errors'] as List)
            .map((e) => RowError.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Result of a commit action — import summary returned after rows are written.
class ImportCommitResult {
  const ImportCommitResult({
    required this.type,
    required this.imported,
    required this.batchId,
  });

  final String type;
  final int    imported;
  final String batchId;

  factory ImportCommitResult.fromJson(Map<String, dynamic> json) =>
      ImportCommitResult(
        type:     json['type']     as String,
        imported: json['imported'] as int,
        batchId:  json['batch_id'] as String,
      );
}
