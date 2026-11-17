// The phone used to show single sign-on errors as raw codes ("Authentication failed:
// email_not_verified"). Every code the server can send now has a message; this test reads the
// server's source so a new code without a message fails the build.

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:castaway_mobile/l10n/app_localizations.dart';
import 'package:castaway_mobile/services/castaway/oidc_service.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('en'));

  Set<String> serverCodes() {
    final source = File('../rust-api/src/handlers/auth.rs').readAsStringSync();
    return {
      ...RegExp(r'error=([a-z_]+)').allMatches(source).map((m) => m.group(1)!),
      ...RegExp(r'OidcAccount::Refuse\("([a-z_]+)"\)').allMatches(source).map((m) => m.group(1)!),
    };
  }

  test('every sign-in error the server can send has a message', () {
    final codes = serverCodes();
    expect(codes, containsAll(['email_not_verified', 'registration_disabled', 'account_linked_elsewhere', 'provider_error']));
    for (final code in codes) {
      expect(oidcErrorMessage(l, code, null), isNot(l.oidc_error_unknown(code)), reason: 'no message for "$code"');
    }
  });

  test('the provider\'s explanation is added when the server passes one on', () {
    expect(oidcErrorMessage(l, 'provider_error', 'access_denied: user cancelled'),
        '${l.oidc_error_provider_error} (access_denied: user cancelled)');
    expect(oidcErrorMessage(l, 'no_access', '  '), l.oidc_error_no_access);
  });

  test('an unknown code is still shown, so it can be reported', () {
    expect(oidcErrorMessage(l, 'brand_new_code', null), contains('brand_new_code'));
  });

  test('the callback reads the server\'s description parameter', () {
    final result = OidcService.parseCallback(
        'castaway://auth/callback?error=provider_error&description=consent%20required');
    expect(result.isSuccess, isFalse);
    expect(result.error, 'provider_error');
    expect(result.errorDescription, 'consent required');
  });
}
