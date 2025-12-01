import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class VideoService {
  final YoutubeExplode _yt = YoutubeExplode();
  // Simple in-memory cache for video URLs to avoid repeated API calls.
  static final Map<String, String> _urlCache = {};

  Future<String> getStreamUrl(String videoId) async {
    // Return the cached URL if it exists.
    if (_urlCache.containsKey(videoId)) {
      return _urlCache[videoId]!;
    }

    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      // Get the highest quality muxed stream.
      final streamInfo = manifest.muxed.withHighestBitrate();
      final url = streamInfo.url.toString();
      
      // Cache the URL before returning.
      _urlCache[videoId] = url;

      return url;
    } catch (e) {
      // If something goes wrong, re-throw the exception to be handled by the caller.
      print('Error getting video stream: $e');
      rethrow;
    }
  }

  // Helper to extract video ID from various YouTube URL formats.
  String? convertToVideoId(String url) {
    try {
      return VideoId(url).value;
    } catch (_) {
      return null;
    }
  }
}
