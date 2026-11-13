// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:castaway_mobile/bloc/bloc.dart';
import 'package:castaway_mobile/core/environment.dart';
import 'package:castaway_mobile/entities/app_settings.dart';
import 'package:castaway_mobile/entities/search_providers.dart';
import 'package:castaway_mobile/services/settings/settings_service.dart';
import 'package:castaway_mobile/services/castaway/castaway_service.dart';
import 'package:castaway_mobile/ui/themes.dart';
import 'package:logging/logging.dart';
import 'package:rxdart/rxdart.dart';

class SettingsBloc extends Bloc {
  final log = Logger('SettingsBloc');
  final SettingsService _settingsService;
  final BehaviorSubject<AppSettings> _settings = BehaviorSubject<AppSettings>.seeded(AppSettings.sensibleDefaults());
  final BehaviorSubject<bool> _darkMode = BehaviorSubject<bool>();
  final BehaviorSubject<String> _theme = BehaviorSubject<String>();
  final BehaviorSubject<bool> _markDeletedAsPlayed = BehaviorSubject<bool>();
  final BehaviorSubject<bool> _deleteDownloadedPlayedEpisodes = BehaviorSubject<bool>();
  final BehaviorSubject<bool> _storeDownloadOnSDCard = BehaviorSubject<bool>();
  final BehaviorSubject<double> _playbackSpeed = BehaviorSubject<double>();
  final BehaviorSubject<String> _searchProvider = BehaviorSubject<String>();
  final BehaviorSubject<bool> _externalLinkConsent = BehaviorSubject<bool>();
  final BehaviorSubject<bool> _autoOpenNowPlaying = BehaviorSubject<bool>();
  final BehaviorSubject<bool> _showFunding = BehaviorSubject<bool>();
  final BehaviorSubject<bool> _trimSilence = BehaviorSubject<bool>();
  final BehaviorSubject<bool> _volumeBoost = BehaviorSubject<bool>();
  final BehaviorSubject<int> _fastForwardInterval = BehaviorSubject<int>();
  final BehaviorSubject<int> _rewindInterval = BehaviorSubject<int>();
  final BehaviorSubject<int> _autoUpdatePeriod = BehaviorSubject<int>();
  final BehaviorSubject<int> _layoutMode = BehaviorSubject<int>();
  final BehaviorSubject<String?> _castawayServer = BehaviorSubject<String?>();
  final BehaviorSubject<String?> _castawayApiKey = BehaviorSubject<String?>();
  final BehaviorSubject<int?> _castawayUserId = BehaviorSubject<int?>();
  final BehaviorSubject<String?> _castawayUsername = BehaviorSubject<String?>();
  final BehaviorSubject<String?> _castawayEmail = BehaviorSubject<String?>();
  final BehaviorSubject<List<String>> _bottomBarOrder = BehaviorSubject<List<String>>();
  final BehaviorSubject<bool> _autoDownloadWifiOnly = BehaviorSubject<bool>();
  final BehaviorSubject<bool> _preferServerDownloadSource = BehaviorSubject<bool>();
  final BehaviorSubject<bool> _castawayUseGravatar = BehaviorSubject<bool>();
  final BehaviorSubject<int> _autoDownloadQueueCount = BehaviorSubject<int>();
  final BehaviorSubject<bool> _mirrorServerDownloads = BehaviorSubject<bool>();
  final BehaviorSubject<int> _deleteDownloadsAfterDays = BehaviorSubject<int>();
  final BehaviorSubject<String> _playButtonStyle = BehaviorSubject<String>();
  final BehaviorSubject<bool> _artworkAccentColors = BehaviorSubject<bool>();
  final BehaviorSubject<String> _language = BehaviorSubject<String>();
  var _currentSettings = AppSettings.sensibleDefaults();

  SettingsBloc(this._settingsService) {
    _init();
    // Check if we need to fetch user details for existing login
    _fetchUserDetailsIfNeeded();
  }

  /// Refreshes the account details mirrored from the server: username and email when
  /// missing, and the Gravatar setting every start so a change made elsewhere applies.
  Future<void> _fetchUserDetailsIfNeeded() async {
    final userId = _currentSettings.castawayUserId;
    if (_currentSettings.castawayServer == null || _currentSettings.castawayApiKey == null || userId == null) {
      return;
    }

    try {
      final castawayService = CastawayService();
      castawayService.setCredentials(_currentSettings.castawayServer!, _currentSettings.castawayApiKey!);

      final userDetails = await castawayService.getUserDetails(userId);
      if (userDetails == null) return;

      if (_currentSettings.castawayUsername == null || _currentSettings.castawayUsername!.isEmpty) {
        setCastawayUsername(userDetails['Username'] ?? userDetails['username'] ?? '');
        setCastawayEmail(userDetails['Email'] ?? userDetails['email'] ?? '');
      }
      setCastawayUseGravatar(userDetails['UseGravatar'] == true);
    } catch (e) {
      // Silently fail - don't break the app if this fails
      print('Failed to fetch user details on startup: $e');
    }
  }

  void _init() {
    /// Load all settings
    // Add our available search providers.
    var providers = <SearchProvider>[SearchProvider(key: 'itunes', name: 'iTunes')];

    if (podcastIndexKey.isNotEmpty) {
      providers.add(SearchProvider(key: 'podcastindex', name: 'PodcastIndex'));
    }

    _currentSettings = AppSettings(
      theme: ThemeRegistry.normalizeKey(_settingsService.theme),
      markDeletedEpisodesAsPlayed: _settingsService.markDeletedEpisodesAsPlayed,
      deleteDownloadedPlayedEpisodes: _settingsService.deleteDownloadedPlayedEpisodes,
      storeDownloadsSDCard: _settingsService.storeDownloadsSDCard,
      playbackSpeed: _settingsService.playbackSpeed,
      searchProvider: _settingsService.searchProvider,
      searchProviders: providers,
      externalLinkConsent: _settingsService.externalLinkConsent,
      autoOpenNowPlaying: _settingsService.autoOpenNowPlaying,
      showFunding: _settingsService.showFunding,
      autoUpdateEpisodePeriod: _settingsService.autoUpdateEpisodePeriod,
      trimSilence: _settingsService.trimSilence,
      volumeBoost: _settingsService.volumeBoost,
      fastForwardInterval: _settingsService.fastForwardInterval,
      rewindInterval: _settingsService.rewindInterval,
      layout: _settingsService.layoutMode,
      castawayServer: _settingsService.castawayServer,
      castawayApiKey: _settingsService.castawayApiKey,
      castawayUserId: _settingsService.castawayUserId,
      castawayUsername: _settingsService.castawayUsername,
      castawayEmail: _settingsService.castawayEmail,
      bottomBarOrder: _settingsService.bottomBarOrder,
      autoDownloadWifiOnly: _settingsService.autoDownloadWifiOnly,
      preferServerDownloadSource: _settingsService.preferServerDownloadSource,
      castawayUseGravatar: _settingsService.castawayUseGravatar,
      autoDownloadQueueCount: _settingsService.autoDownloadQueueCount,
      mirrorServerDownloads: _settingsService.mirrorServerDownloads,
      deleteDownloadsAfterDays: _settingsService.deleteDownloadsAfterDays,
      playButtonStyle: _settingsService.playButtonStyle,
      artworkAccentColors: _settingsService.artworkAccentColors,
      language: _settingsService.language,
    );

    _settings.add(_currentSettings);

    _darkMode.listen((bool darkMode) {
      _currentSettings = _currentSettings.copyWith(theme: darkMode ? 'Dark' : 'Light');
      _settings.add(_currentSettings);
      _settingsService.themeDarkMode = darkMode;
    });

    _theme.listen((String theme) {
      _currentSettings = _currentSettings.copyWith(theme: theme);
      _settings.add(_currentSettings);
      _settingsService.theme = theme;
      
      // Sync with server if authenticated
      _syncThemeToServer(theme);
    });

    _markDeletedAsPlayed.listen((bool mark) {
      _currentSettings = _currentSettings.copyWith(markDeletedEpisodesAsPlayed: mark);
      _settings.add(_currentSettings);
      _settingsService.markDeletedEpisodesAsPlayed = mark;
    });

    _deleteDownloadedPlayedEpisodes.listen((bool delete) {
      _currentSettings = _currentSettings.copyWith(deleteDownloadedPlayedEpisodes: delete);
      _settings.add(_currentSettings);
      _settingsService.deleteDownloadedPlayedEpisodes = delete;
    });

    _storeDownloadOnSDCard.listen((bool sdcard) {
      _currentSettings = _currentSettings.copyWith(storeDownloadsSDCard: sdcard);
      _settings.add(_currentSettings);
      _settingsService.storeDownloadsSDCard = sdcard;
    });

    _playbackSpeed.listen((double speed) {
      _currentSettings = _currentSettings.copyWith(playbackSpeed: speed);
      _settings.add(_currentSettings);
      _settingsService.playbackSpeed = speed;
    });

    _autoOpenNowPlaying.listen((bool autoOpen) {
      _currentSettings = _currentSettings.copyWith(autoOpenNowPlaying: autoOpen);
      _settings.add(_currentSettings);
      _settingsService.autoOpenNowPlaying = autoOpen;
    });

    _showFunding.listen((show) {
      // If the setting has not changed, don't bother updating it
      if (show != _currentSettings.showFunding) {
        _currentSettings = _currentSettings.copyWith(showFunding: show);
        _settingsService.showFunding = show;
      }

      _settings.add(_currentSettings);
    });

    _searchProvider.listen((search) {
      _currentSettings = _currentSettings.copyWith(searchProvider: search);
      _settings.add(_currentSettings);
      _settingsService.searchProvider = search;
    });

    _externalLinkConsent.listen((consent) {
      // If the setting has not changed, don't bother updating it
      if (consent != _settingsService.externalLinkConsent) {
        _currentSettings = _currentSettings.copyWith(externalLinkConsent: consent);
        _settingsService.externalLinkConsent = consent;
      }

      _settings.add(_currentSettings);
    });

    _autoUpdatePeriod.listen((period) {
      _currentSettings = _currentSettings.copyWith(autoUpdateEpisodePeriod: period);
      _settings.add(_currentSettings);
      _settingsService.autoUpdateEpisodePeriod = period;
    });

    _trimSilence.listen((trim) {
      _currentSettings = _currentSettings.copyWith(trimSilence: trim);
      _settings.add(_currentSettings);
      _settingsService.trimSilence = trim;
    });

    _volumeBoost.listen((boost) {
      _currentSettings = _currentSettings.copyWith(volumeBoost: boost);
      _settings.add(_currentSettings);
      _settingsService.volumeBoost = boost;
    });

    _fastForwardInterval.listen((seconds) {
      _currentSettings = _currentSettings.copyWith(fastForwardInterval: seconds);
      _settings.add(_currentSettings);
      _settingsService.fastForwardInterval = seconds;
    });

    _rewindInterval.listen((seconds) {
      _currentSettings = _currentSettings.copyWith(rewindInterval: seconds);
      _settings.add(_currentSettings);
      _settingsService.rewindInterval = seconds;
    });

    _castawayServer.listen((server) {
      _currentSettings = _currentSettings.copyWith(castawayServer: server);
      _settings.add(_currentSettings);
      _settingsService.castawayServer = server;
    });

    _castawayApiKey.listen((apiKey) {
      _currentSettings = _currentSettings.copyWith(castawayApiKey: apiKey);
      _settings.add(_currentSettings);
      _settingsService.castawayApiKey = apiKey;
    });

    _castawayUserId.listen((userId) {
      _currentSettings = _currentSettings.copyWith(castawayUserId: userId);
      _settings.add(_currentSettings);
      _settingsService.castawayUserId = userId;
    });

    _castawayUsername.listen((username) {
      _currentSettings = _currentSettings.copyWith(castawayUsername: username);
      _settings.add(_currentSettings);
      _settingsService.castawayUsername = username;
    });

    _castawayEmail.listen((email) {
      _currentSettings = _currentSettings.copyWith(castawayEmail: email);
      _settings.add(_currentSettings);
      _settingsService.castawayEmail = email;
    });

    _layoutMode.listen((mode) {
      _currentSettings = _currentSettings.copyWith(layout: mode);
      _settings.add(_currentSettings);
      _settingsService.layoutMode = mode;
    });

    _bottomBarOrder.listen((order) {
      _currentSettings = _currentSettings.copyWith(bottomBarOrder: order);
      _settings.add(_currentSettings);
      _settingsService.bottomBarOrder = order;
    });

    _autoDownloadWifiOnly.listen((value) {
      _currentSettings = _currentSettings.copyWith(autoDownloadWifiOnly: value);
      _settings.add(_currentSettings);
      _settingsService.autoDownloadWifiOnly = value;
    });

    _preferServerDownloadSource.listen((value) {
      _currentSettings = _currentSettings.copyWith(preferServerDownloadSource: value);
      _settings.add(_currentSettings);
      _settingsService.preferServerDownloadSource = value;
    });

    _castawayUseGravatar.listen((value) {
      _currentSettings = _currentSettings.copyWith(castawayUseGravatar: value);
      _settings.add(_currentSettings);
      _settingsService.castawayUseGravatar = value;
    });

    _autoDownloadQueueCount.listen((value) {
      _currentSettings = _currentSettings.copyWith(autoDownloadQueueCount: value);
      _settings.add(_currentSettings);
      _settingsService.autoDownloadQueueCount = value;
    });

    _mirrorServerDownloads.listen((value) {
      _currentSettings = _currentSettings.copyWith(mirrorServerDownloads: value);
      _settings.add(_currentSettings);
      _settingsService.mirrorServerDownloads = value;
    });

    _deleteDownloadsAfterDays.listen((value) {
      _currentSettings = _currentSettings.copyWith(deleteDownloadsAfterDays: value);
      _settings.add(_currentSettings);
      _settingsService.deleteDownloadsAfterDays = value;
    });

    _playButtonStyle.listen((value) {
      _currentSettings = _currentSettings.copyWith(playButtonStyle: value);
      _settings.add(_currentSettings);
      _settingsService.playButtonStyle = value;
    });

    _artworkAccentColors.listen((value) {
      _currentSettings = _currentSettings.copyWith(artworkAccentColors: value);
      _settings.add(_currentSettings);
      _settingsService.artworkAccentColors = value;
    });

    _language.listen((value) {
      _currentSettings = _currentSettings.copyWith(language: value);
      _settings.add(_currentSettings);
      _settingsService.language = value;
    });
  }

  Stream<AppSettings> get settings => _settings.stream;

  void Function(bool) get darkMode => _darkMode.add;

  void Function(bool) get storeDownloadonSDCard => _storeDownloadOnSDCard.add;

  void Function(bool) get markDeletedAsPlayed => _markDeletedAsPlayed.add;

  void Function(bool) get deleteDownloadedPlayedEpisodes => _deleteDownloadedPlayedEpisodes.add;

  void Function(double) get setPlaybackSpeed => _playbackSpeed.add;

  void Function(bool) get setAutoOpenNowPlaying => _autoOpenNowPlaying.add;

  void Function(String) get setSearchProvider => _searchProvider.add;

  void Function(bool) get setExternalLinkConsent => _externalLinkConsent.add;

  void Function(bool) get setShowFunding => _showFunding.add;

  void Function(int) get autoUpdatePeriod => _autoUpdatePeriod.add;

  void Function(bool) get trimSilence => _trimSilence.add;

  void Function(bool) get volumeBoost => _volumeBoost.add;

  void Function(int) get setFastForwardInterval => _fastForwardInterval.add;

  void Function(int) get setRewindInterval => _rewindInterval.add;

  void Function(int) get layoutMode => _layoutMode.add;

  void Function(String?) get setCastawayServer => _castawayServer.add;

  void Function(String?) get setCastawayApiKey => _castawayApiKey.add;

  void Function(int?) get setCastawayUserId => _castawayUserId.add;

  void Function(String?) get setCastawayUsername => _castawayUsername.add;

  void Function(String?) get setCastawayEmail => _castawayEmail.add;

  void Function(List<String>) get setBottomBarOrder => _bottomBarOrder.add;

  void Function(bool) get setAutoDownloadWifiOnly => _autoDownloadWifiOnly.add;

  void Function(bool) get setPreferServerDownloadSource => _preferServerDownloadSource.add;

  void Function(bool) get setCastawayUseGravatar => _castawayUseGravatar.add;

  void Function(int) get setAutoDownloadQueueCount => _autoDownloadQueueCount.add;

  void Function(bool) get setMirrorServerDownloads => _mirrorServerDownloads.add;

  void Function(int) get setDeleteDownloadsAfterDays => _deleteDownloadsAfterDays.add;

  void Function(String) get setPlayButtonStyle => _playButtonStyle.add;

  void Function(bool) get setArtworkAccentColors => _artworkAccentColors.add;

  void Function(String) get setLanguage => _language.add;

  void Function(String) get setTheme => _theme.add;

  AppSettings get currentSettings => _settings.value;

  Future<void> _syncThemeToServer(String theme) async {
    try {
      // Only sync if we have Castaway credentials
      if (_currentSettings.castawayServer != null &&
          _currentSettings.castawayApiKey != null &&
          _currentSettings.castawayUserId != null) {
        
        final castawayService = CastawayService();
        castawayService.setCredentials(
          _currentSettings.castawayServer!,
          _currentSettings.castawayApiKey!,
        );
        
        await castawayService.setUserTheme(_currentSettings.castawayUserId!, theme);
        log.info('Theme synced to server: $theme');
      }
    } catch (e) {
      log.warning('Failed to sync theme to server: $e');
      // Don't throw - theme should still work locally
    }
  }

  Future<void> fetchThemeFromServer() async {
    try {
      // Only fetch if we have Castaway credentials
      if (_currentSettings.castawayServer != null &&
          _currentSettings.castawayApiKey != null &&
          _currentSettings.castawayUserId != null) {
        
        final castawayService = CastawayService();
        castawayService.setCredentials(
          _currentSettings.castawayServer!,
          _currentSettings.castawayApiKey!,
        );
        
        final serverTheme = await castawayService.getUserTheme(_currentSettings.castawayUserId!);
        if (serverTheme != null && serverTheme.isNotEmpty) {
          final theme = ThemeRegistry.normalizeKey(serverTheme);
          // Update local theme without syncing back to server
          _settingsService.theme = theme;
          _currentSettings = _currentSettings.copyWith(theme: theme);
          _settings.add(_currentSettings);
          log.info('Theme fetched from server: $serverTheme');
        }
      }
    } catch (e) {
      log.warning('Failed to fetch theme from server: $e');
      // Don't throw - continue with local theme
    }
  }

  @override
  void dispose() {
    _darkMode.close();
    _theme.close();
    _markDeletedAsPlayed.close();
    _deleteDownloadedPlayedEpisodes.close();
    _storeDownloadOnSDCard.close();
    _playbackSpeed.close();
    _searchProvider.close();
    _externalLinkConsent.close();
    _autoOpenNowPlaying.close();
    _showFunding.close();
    _trimSilence.close();
    _volumeBoost.close();
    _fastForwardInterval.close();
    _rewindInterval.close();
    _autoUpdatePeriod.close();
    _layoutMode.close();
    _castawayServer.close();
    _castawayApiKey.close();
    _castawayUserId.close();
    _castawayUsername.close();
    _castawayEmail.close();
    _bottomBarOrder.close();
    _autoDownloadWifiOnly.close();
    _preferServerDownloadSource.close();
    _castawayUseGravatar.close();
    _autoDownloadQueueCount.close();
    _mirrorServerDownloads.close();
    _deleteDownloadsAfterDays.close();
    _playButtonStyle.close();
    _artworkAccentColors.close();
    _language.close();
    _settings.close();
  }
}
