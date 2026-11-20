import '../capture/capture_models.dart';

class WorkspacePhoto {
  const WorkspacePhoto(
    this.attachment,
    this.createdAt,
    this.aspectRatio, {
    this.title = '',
    this.label = '',
  });

  final PhotoAttachment attachment;
  final DateTime createdAt;
  final double aspectRatio;
  final String title, label;
  String get displayTitle => title.isEmpty ? attachment.name : title;
  String get id => attachment.id;

  Map<String, dynamic> toJson() => {
    ...attachment.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'aspectRatio': aspectRatio,
    if (title.isNotEmpty) 'title': title,
    if (label.isNotEmpty) 'label': label,
  };

  factory WorkspacePhoto.fromJson(dynamic value) {
    final ratio = (value['aspectRatio'] as num).toDouble();
    if (!ratio.isFinite || ratio <= 0) {
      throw const FormatException('Invalid photo aspect ratio');
    }
    return WorkspacePhoto(
      PhotoAttachment.fromJson(value),
      DateTime.parse(value['createdAt'] as String),
      ratio,
      title: value['title'] as String? ?? '',
      label: value['label'] as String? ?? '',
    );
  }
}

final workspacePhotos = <String, WorkspacePhoto>{};
