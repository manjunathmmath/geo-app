import 'package:flutter_test/flutter_test.dart';
import 'package:geo_mobile/api/models.dart';
import 'package:geo_mobile/util.dart';

Map<String, dynamic> _json({
  String type = 'IMAGE',
  String? mediaUrl = '/media/2026/10/a.png',
  String? thumbUrl,
  String? caption,
  String? text,
  Object? distance,
}) =>
    {
      'id': 'p1',
      'authorId': 'u1',
      'type': type,
      'mediaUrl': mediaUrl,
      'thumbUrl': thumbUrl,
      'caption': caption,
      'text': text,
      'lat': 12.9716,
      'lng': 77,
      'accuracyM': 5,
      'status': 'APPROVED',
      'createdAt': '2026-10-25T09:51:59.611813Z',
      'rejectReason': null,
      'distanceM': distance,
    };

void main() {
  test('an image post is read from the API, including a missing distance and caption', () {
    final post = Post.fromJson(_json());
    expect(post.isImage, isTrue);
    expect(post.isText, isFalse);
    expect(post.caption, isNull);
    expect(post.lng, 77.0);
    expect(post.accuracyM, 5.0);
    expect(post.distanceM, isNull);
    expect(post.title, '(no caption)');
  });

  test('audio and video posts keep their distance and caption', () {
    final audio = Post.fromJson(_json(type: 'AUDIO', mediaUrl: '/media/a.wav', caption: 'Bells', distance: 11.9));
    expect(audio.isAudio, isTrue);
    expect(audio.distanceM, 11.9);
    expect(audio.title, 'Bells');
    final video = Post.fromJson(_json(type: 'VIDEO', mediaUrl: '/media/a.mp4', thumbUrl: '/media/a.mp4.thumb.jpg'));
    expect(video.isVideo, isTrue);
    expect(video.thumbUrl, '/media/a.mp4.thumb.jpg');
    expect(Post.fromJson(_json()).thumbUrl, isNull);
  });

  test('a text post has words and no file', () {
    final post = Post.fromJson(_json(type: 'TEXT', mediaUrl: null, text: '  The chai is best after 5 pm  '));
    expect(post.isText, isTrue);
    expect(post.mediaUrl, isNull);
    expect(post.text, '  The chai is best after 5 pm  ');
    expect(post.title, 'The chai is best after 5 pm');
  });

  test('status labels are readable for creators', () {
    expect(statusLabel('PENDING'), 'In review');
    expect(statusLabel('APPROVED'), 'Published');
    expect(statusLabel('REJECTED'), 'Rejected');
  });

  test('durations are shown as minutes and seconds', () {
    expect(formatDuration(const Duration(seconds: 7)), '0:07');
    expect(formatDuration(const Duration(seconds: 90)), '1:30');
    expect(formatDuration(const Duration(milliseconds: -5)), '0:00');
  });

  test('relative times read naturally', () {
    final now = DateTime.now();
    expect(timeAgo(now.subtract(const Duration(seconds: 20))), 'just now');
    expect(timeAgo(now.subtract(const Duration(minutes: 5, seconds: 5))), '5 min ago');
    expect(timeAgo(now.subtract(const Duration(hours: 3, minutes: 1))), '3 h ago');
    expect(timeAgo(now.subtract(const Duration(days: 2, hours: 1))), '2 d ago');
  });

  test('GPS quality follows the thresholds the server uses', () {
    expect(gpsQuality(8), GpsQuality.good);
    expect(gpsQuality(30), GpsQuality.good);
    expect(gpsQuality(31), GpsQuality.fair);
    expect(gpsQuality(100), GpsQuality.fair);
    expect(gpsQuality(100.5), GpsQuality.poor);
  });

  test('Me.isAdmin follows the role', () {
    expect(const Me(id: '1', email: 'a@b.c', role: 'ADMIN').isAdmin, isTrue);
    expect(const Me(id: '1', email: 'a@b.c', role: 'CREATOR').isAdmin, isFalse);
  });
}
