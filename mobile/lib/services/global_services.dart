// lib/services/global_services.dart
import 'package:castaway_mobile/services/nowplaying/nowplaying_service.dart';
import 'package:castaway_mobile/services/offline/offline_action_queue.dart';
import 'package:castaway_mobile/services/castaway/castaway_audio_service.dart';
import 'package:castaway_mobile/services/castaway/castaway_service.dart';

/// Global service access point for the app
class GlobalServices {
  static CastawayAudioService? _castawayAudioService;
  static CastawayService? _castawayService;
  static OfflineActionQueue? _offlineActionQueue;
  static NowPlayingService? _nowPlayingService;

  /// Set the global services (called from CastawayPodcastApp)
  static void initialize({
    required CastawayAudioService castawayAudioService,
    required CastawayService castawayService,
    OfflineActionQueue? offlineActionQueue,
    NowPlayingService? nowPlayingService,
  }) {
    _castawayAudioService = castawayAudioService;
    _castawayService = castawayService;
    _offlineActionQueue = offlineActionQueue;
    _nowPlayingService = nowPlayingService;
  }

  /// Get the global now-playing (cross-device awareness) service instance
  static NowPlayingService? get nowPlayingService => _nowPlayingService;

  /// Get the global offline action queue instance
  static OfflineActionQueue? get offlineActionQueue => _offlineActionQueue;
  
  /// Update global service credentials (called when user logs in or settings change)
  static void setCredentials(String server, String apiKey) {
    _castawayService?.setCredentials(server, apiKey);
  }
  
  /// Get the global CastawayAudioService instance
  static CastawayAudioService? get castawayAudioService => _castawayAudioService;
  
  /// Get the global CastawayService instance
  static CastawayService? get castawayService => _castawayService;
  
  /// Clear services (for testing or cleanup)
  static void clear() {
    _castawayAudioService = null;
    _castawayService = null;
    _offlineActionQueue = null;
  }
}