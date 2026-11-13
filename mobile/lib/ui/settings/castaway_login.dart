// lib/ui/settings/castaway_login.dart
import 'package:flutter/material.dart';
import 'package:castaway_mobile/bloc/settings/settings_bloc.dart';
import 'package:castaway_mobile/l10n/L.dart';
import 'package:castaway_mobile/services/castaway/castaway_service.dart';
import 'package:castaway_mobile/services/castaway/login_service.dart';
import 'package:castaway_mobile/bloc/podcast/audio_bloc.dart';
import 'package:castaway_mobile/ui/utils/local_download_utils.dart';
import 'package:castaway_mobile/ui/settings/settings_section_label.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:castaway_mobile/ui/icons/phosphor_icons.dart';

class CastawayLoginWidget extends StatefulWidget {
  const CastawayLoginWidget({Key? key}) : super(key: key);

  @override
  State<CastawayLoginWidget> createState() => _CastawayLoginWidgetState();
}

class _CastawayLoginWidgetState extends State<CastawayLoginWidget> {
  final _serverController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _mfaController = TextEditingController();

  bool _isLoading = false;
  bool _showMfaField = false;
  String _errorMessage = '';
  bool _isLoggedIn = false;
  String? _connectedServer;
  String? _tempServerUrl;
  String? _tempUsername;
  int? _tempUserId;
  String? _tempMfaSessionToken;

  @override
  void initState() {
    super.initState();
    // Initialize UI based on saved settings
    _loadSavedSettings();
  }

  void _loadSavedSettings() {
    var settingsBloc = Provider.of<SettingsBloc>(context, listen: false);
    var settings = settingsBloc.currentSettings;

    // Check if we have Castaway settings
    setState(() {
      _isLoggedIn = false;
      _connectedServer = null;

      // We'll add these properties to AppSettings in the next step
      if (settings.castawayServer != null &&
          settings.castawayServer!.isNotEmpty &&
          settings.castawayApiKey != null &&
          settings.castawayApiKey!.isNotEmpty) {
        _isLoggedIn = true;
        _connectedServer = settings.castawayServer;
      }
    });
  }

  Future<void> _connectToCastaway() async {
    if (!_showMfaField && (_serverController.text.isEmpty ||
        _usernameController.text.isEmpty ||
        _passwordController.text.isEmpty)) {
      setState(() {
        _errorMessage = L.of(context)!.fill_in_all_fields;
      });
      return;
    }

    if (_showMfaField && _mfaController.text.isEmpty) {
      setState(() {
        _errorMessage = L.of(context)!.enter_mfa_code;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      if (_showMfaField && _tempMfaSessionToken != null) {
        // Complete MFA login flow
        final mfaCode = _mfaController.text.trim();
        final result = await CastawayLoginService.completeMfaLogin(
          serverUrl: _tempServerUrl!,
          username: _tempUsername!,
          mfaSessionToken: _tempMfaSessionToken!,
          mfaCode: mfaCode,
        );
        
        if (result.isSuccess) {
          // Save the connection details including user ID
          var settingsBloc = Provider.of<SettingsBloc>(context, listen: false);
          settingsBloc.setCastawayServer(result.serverUrl!);
          settingsBloc.setCastawayApiKey(result.apiKey!);
          settingsBloc.setCastawayUserId(result.userId!);

          setState(() {
            _isLoggedIn = true;
            _connectedServer = _tempServerUrl;
            _showMfaField = false;
            _tempServerUrl = null;
            _tempUsername = null;
            _tempUserId = null;
            _tempMfaSessionToken = null;
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = result.errorMessage ?? L.of(context)!.mfa_verification_failed;
            _isLoading = false;
          });
        }
      } else {
        // Initial login flow
        final serverUrl = _serverController.text.trim();
        final username = _usernameController.text.trim();
        final password = _passwordController.text;

        final result = await CastawayLoginService.login(
          serverUrl,
          username,
          password,
        );

        if (result.isSuccess) {
          // Save the connection details including user ID
          var settingsBloc = Provider.of<SettingsBloc>(context, listen: false);
          settingsBloc.setCastawayServer(result.serverUrl!);
          settingsBloc.setCastawayApiKey(result.apiKey!);
          settingsBloc.setCastawayUserId(result.userId!);

          setState(() {
            _isLoggedIn = true;
            _connectedServer = serverUrl;
            _isLoading = false;
          });
        } else if (result.requiresMfa) {
          // Store MFA session info and show MFA field
          setState(() {
            _tempServerUrl = result.serverUrl;
            _tempUsername = result.username;
            _tempUserId = result.userId;
            _tempMfaSessionToken = result.mfaSessionToken;
            _showMfaField = true;
            _isLoading = false;
            _errorMessage = L.of(context)!.enter_mfa_code;
          });
        } else {
          setState(() {
            _errorMessage = result.errorMessage ?? L.of(context)!.login_failed;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = L.of(context)!.error_with_detail(e.toString());
        _isLoading = false;
      });
    }
  }

  void _resetMfa() {
    setState(() {
      _showMfaField = false;
      _tempServerUrl = null;
      _tempUsername = null;
      _tempUserId = null;
      _tempMfaSessionToken = null;
      _mfaController.clear();
      _errorMessage = '';
    });
  }

  void _logOut() {
    final settingsBloc = Provider.of<SettingsBloc>(context, listen: false);
    final navigator = Navigator.of(context);

    // Nothing from this account should keep playing or reporting.
    Provider.of<AudioBloc>(context, listen: false).transitionState(TransitionState.stop);
    LocalDownloadUtils.clearCache();

    // AuthWrapper swaps the home route to the login screen as soon as these
    // clear (the now-playing socket also disconnects off the same stream).
    settingsBloc.setCastawayServer(null);
    settingsBloc.setCastawayApiKey(null);
    settingsBloc.setCastawayUserId(null);
    settingsBloc.setCastawayUsername(null);
    settingsBloc.setCastawayEmail(null);

    // Settings is pushed above home; drop back to the root so the login screen
    // is what's actually showing.
    navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    // Add a divider label for the Castaway section
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsDividerLabel(label: L.of(context)!.castaway_server),
        const Divider(),
        if (_isLoggedIn) ...[
          // Show connected status
          ListTile(
            title: Text(L.of(context)!.castaway_connection),
            subtitle: Text(_connectedServer ?? ''),
            trailing: TextButton(
              onPressed: _logOut,
              child: Text(L.of(context)!.log_out),
            ),
          ),
        ] else ...[
          // Show login form
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _serverController,
                  decoration: InputDecoration(
                    labelText: L.of(context)!.server_url,
                    hintText: 'https://your-castaway-server.com',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: L.of(context)!.username,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: L.of(context)!.password,
                  ),
                  obscureText: true,
                  enabled: !_showMfaField,
                ),
                // MFA Field (shown when MFA is required)
                if (_showMfaField) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _mfaController,
                    decoration: InputDecoration(
                      labelText: L.of(context)!.mfa_code,
                      hintText: L.of(context)!.mfa_code_hint,
                      suffixIcon: IconButton(
                        icon: const Icon(PhosphorIconsRegular.x),
                        onPressed: _resetMfa,
                        tooltip: L.of(context)!.cancel_mfa,
                      ),
                    ),
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                  ),
                ],
                if (_errorMessage.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _connectToCastaway,
                    child: _isLoading
                        ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                        : Text(_showMfaField ? 'Verify MFA Code' : L.of(context)!.connect),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  void dispose() {
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _mfaController.dispose();
    super.dispose();
  }
}