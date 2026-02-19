import 'dart:convert';

import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class CloudAuthService {
  // Google
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['https://www.googleapis.com/auth/drive.readonly'],
  );
  GoogleSignInAccount? _googleAccount;

  // Dropbox
  final FlutterAppAuth _appAuth = const FlutterAppAuth();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  String? _dropboxAccessToken;
  String? _dropboxRefreshToken;
  DateTime? _dropboxTokenExpiry;

  bool get isGoogleConnected => _googleAccount != null;
  bool get isDropboxConnected => _dropboxAccessToken != null;

  // --- Google ---

  Future<bool> signInGoogle() async {
    try {
      _googleAccount = await _googleSignIn.signIn();
      return _googleAccount != null;
    } catch (e) {
      return false;
    }
  }

  Future<void> signOutGoogle() async {
    await _googleSignIn.signOut();
    _googleAccount = null;
  }

  Future<bool> restoreGoogleSession() async {
    try {
      _googleAccount = await _googleSignIn.signInSilently();
      return _googleAccount != null;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, String>> getGoogleAuthHeaders() async {
    if (_googleAccount == null) return {};
    final auth = await _googleAccount!.authentication;
    return {'Authorization': 'Bearer ${auth.accessToken}'};
  }

  // --- Dropbox ---

  Future<bool> signInDropbox() async {
    try {
      final result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          AppConfig.dropboxAppKey,
          AppConfig.dropboxRedirectUri,
          serviceConfiguration: const AuthorizationServiceConfiguration(
            authorizationEndpoint: 'https://www.dropbox.com/oauth2/authorize',
            tokenEndpoint: 'https://api.dropboxapi.com/oauth2/token',
          ),
          scopes: ['files.metadata.read', 'files.content.read'],
          additionalParameters: {'token_access_type': 'offline'},
        ),
      );
      _dropboxAccessToken = result.accessToken;
      _dropboxRefreshToken = result.refreshToken;
      _dropboxTokenExpiry = result.accessTokenExpirationDateTime;
      await _persistDropboxTokens();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> signOutDropbox() async {
    _dropboxAccessToken = null;
    _dropboxRefreshToken = null;
    _dropboxTokenExpiry = null;
    await _secureStorage.delete(key: 'dropbox_access_token');
    await _secureStorage.delete(key: 'dropbox_refresh_token');
    await _secureStorage.delete(key: 'dropbox_token_expiry');
  }

  Future<bool> restoreDropboxSession() async {
    try {
      _dropboxAccessToken =
          await _secureStorage.read(key: 'dropbox_access_token');
      _dropboxRefreshToken =
          await _secureStorage.read(key: 'dropbox_refresh_token');
      final expiryStr =
          await _secureStorage.read(key: 'dropbox_token_expiry');
      if (expiryStr != null) {
        _dropboxTokenExpiry = DateTime.tryParse(expiryStr);
      }
      if (_dropboxAccessToken != null) {
        await _refreshDropboxIfNeeded();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, String>> getDropboxAuthHeaders() async {
    await _refreshDropboxIfNeeded();
    if (_dropboxAccessToken == null) return {};
    return {'Authorization': 'Bearer $_dropboxAccessToken'};
  }

  Future<void> _refreshDropboxIfNeeded() async {
    if (_dropboxRefreshToken == null) return;
    if (_dropboxTokenExpiry != null &&
        _dropboxTokenExpiry!.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
      return; // Token still valid
    }
    try {
      final response = await http.post(
        Uri.parse('https://api.dropboxapi.com/oauth2/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'refresh_token',
          'refresh_token': _dropboxRefreshToken!,
          'client_id': AppConfig.dropboxAppKey,
        },
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _dropboxAccessToken = data['access_token'];
        _dropboxTokenExpiry = DateTime.now()
            .add(Duration(seconds: data['expires_in'] as int));
        await _persistDropboxTokens();
      }
    } catch (_) {}
  }

  Future<void> _persistDropboxTokens() async {
    if (_dropboxAccessToken != null) {
      await _secureStorage.write(
          key: 'dropbox_access_token', value: _dropboxAccessToken!);
    }
    if (_dropboxRefreshToken != null) {
      await _secureStorage.write(
          key: 'dropbox_refresh_token', value: _dropboxRefreshToken!);
    }
    if (_dropboxTokenExpiry != null) {
      await _secureStorage.write(
          key: 'dropbox_token_expiry',
          value: _dropboxTokenExpiry!.toIso8601String());
    }
  }
}
