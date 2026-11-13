// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:castaway_mobile/entities/app_settings.dart';
import 'package:castaway_mobile/ui/podcast/now_playing.dart';
import 'package:castaway_mobile/bloc/settings/settings_bloc.dart';
import 'package:castaway_mobile/entities/castaway_episode.dart';
import 'package:castaway_mobile/services/castaway/castaway_audio_service.dart';
import 'package:provider/provider.dart';

/// If we have the 'show now playing upon play' option set to true, launch
/// the [NowPlaying] widget automatically.
void optionalShowNowPlaying(BuildContext context, AppSettings settings) {
  if (settings.autoOpenNowPlaying && context.mounted) {
    showNowPlaying(context);
  }
}

/// Helper function to play a Castaway episode and automatically show the full screen player if enabled
Future<void> playCastawayEpisodeWithOptionalFullScreen(
  BuildContext context,
  CastawayAudioService audioService,
  CastawayEpisode episode, {
  bool resume = true,
}) async {
  await audioService.playCastawayEpisode(
    castawayEpisode: episode,
    resume: resume,
  );
  
  // Show full screen player if setting is enabled
  final settingsBloc = Provider.of<SettingsBloc>(context, listen: false);
  optionalShowNowPlaying(context, settingsBloc.currentSettings);
}