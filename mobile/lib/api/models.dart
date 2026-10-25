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
  final String type; // IMAGE | VIDEO | AUDIO
  final String mediaUrl; // path on the API server, e.g. /media/2026/10/x.png
  final String? caption;
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
    required this.caption,
    required this.lat,
    required this.lng,
    required this.accuracyM,
    required this.status,
    required this.createdAt,
    required this.rejectReason,
    required this.distanceM,
  });

  bool get isImage => type == 'IMAGE';

  factory Post.fromJson(Map<String, dynamic> json) => Post(
        id: json['id'] as String,
        authorId: json['authorId'] as String,
        type: json['type'] as String,
        mediaUrl: json['mediaUrl'] as String,
        caption: json['caption'] as String?,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        accuracyM: (json['accuracyM'] as num?)?.toDouble(),
        status: json['status'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
        rejectReason: json['rejectReason'] as String?,
        distanceM: (json['distanceM'] as num?)?.toDouble(),
      );
}
