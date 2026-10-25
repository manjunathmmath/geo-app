import 'package:flutter_test/flutter_test.dart';
import 'package:geo_mobile/api/models.dart';
import 'package:geo_mobile/util.dart';

void main() {
  test('Post.fromJson reads an API post, including a missing distance and caption', () {
    final post = Post.fromJson({
      'id': 'p1',
      'authorId': 'u1',
      'type': 'IMAGE',
      'mediaUrl': '/media/2026/10/a.png',
      'caption': null,
      'lat': 12.9716,
      'lng': 77,
      'accuracyM': 5,
      'status': 'APPROVED',
      'createdAt': '2026-10-25T09:51:59.611813Z',
      'rejectReason': null,
      'distanceM': null,
    });
    expect(post.isImage, isTrue);
    expect(post.caption, isNull);
    expect(post.lng, 77.0);
    expect(post.accuracyM, 5.0);
    expect(post.distanceM, isNull);
  });

  test('Post.fromJson keeps the distance and rejection reason when present', () {
    final post = Post.fromJson({
      'id': 'p2',
      'authorId': 'u1',
      'type': 'AUDIO',
      'mediaUrl': '/media/a.wav',
      'caption': 'Bells',
      'lat': 1.5,
      'lng': 2.5,
      'accuracyM': null,
      'status': 'REJECTED',
      'createdAt': '2026-10-25T09:51:59Z',
      'rejectReason': 'Not allowed',
      'distanceM': 11.9,
    });
    expect(post.isImage, isFalse);
    expect(post.distanceM, 11.9);
    expect(post.rejectReason, 'Not allowed');
  });

  test('status labels are readable for creators', () {
    expect(statusLabel('PENDING'), 'In review');
    expect(statusLabel('APPROVED'), 'Published');
    expect(statusLabel('REJECTED'), 'Rejected');
  });

  test('Me.isAdmin follows the role', () {
    expect(const Me(id: '1', email: 'a@b.c', role: 'ADMIN').isAdmin, isTrue);
    expect(const Me(id: '1', email: 'a@b.c', role: 'CREATOR').isAdmin, isFalse);
  });
}
