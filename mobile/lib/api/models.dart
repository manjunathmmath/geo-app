class Me {
  final String id;
  final String email;
  final String role;

  const Me({required this.id, required this.email, required this.role});

  bool get isAdmin => role == 'ADMIN';

  factory Me.fromJson(Map<String, dynamic> json) => Me(
        id: json['id'] as String,
        email: (json['email'] as String?) ?? '',
        role: json['role'] as String,
      );
}

class Post {
  final String id;
  final String authorId;
  final String type; // IMAGE | VIDEO | AUDIO | TEXT
  final String? mediaUrl; // path on the API server, e.g. /media/2026/10/x.png; null for text posts
  final String? thumbUrl; // small preview of a photo or video; null for audio, text or when none could be made
  final String? caption; // photo / audio / video posts
  final String? text; // text posts
  final double lat;
  final double lng;
  final double? accuracyM;
  final String status; // PENDING | APPROVED | REJECTED
  final DateTime createdAt;
  final String? rejectReason;
  final double? distanceM;

  const Post({
    required this.id,
    required this.authorId,
    required this.type,
    required this.mediaUrl,
    required this.thumbUrl,
    required this.caption,
    required this.text,
    required this.lat,
    required this.lng,
    required this.accuracyM,
    required this.status,
    required this.createdAt,
    required this.rejectReason,
    required this.distanceM,
  });

  bool get isImage => type == 'IMAGE';
  bool get isVideo => type == 'VIDEO';
  bool get isAudio => type == 'AUDIO';
  bool get isText => type == 'TEXT';

  /// A short label for lists: the caption, the start of the text, or a note that there is none.
  String get title {
    final t = isText ? text : caption;
    if (t == null || t.trim().isEmpty) return '(no caption)';
    return t.trim();
  }

  factory Post.fromJson(Map<String, dynamic> json) => Post(
        id: json['id'] as String,
        authorId: json['authorId'] as String,
        type: json['type'] as String,
        mediaUrl: json['mediaUrl'] as String?,
        thumbUrl: json['thumbUrl'] as String?,
        caption: json['caption'] as String?,
        text: json['text'] as String?,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        accuracyM: (json['accuracyM'] as num?)?.toDouble(),
        status: json['status'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
        rejectReason: json['rejectReason'] as String?,
        distanceM: (json['distanceM'] as num?)?.toDouble(),
      );
}
