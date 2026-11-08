import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import 'backup_store.dart';
import 'google_config.dart';

/// Google hesabına bağlanıp Drive yedek deposunu açar.
abstract interface class DriveConnection {
  /// Google Cloud ayarı yapılmış mı (yapılmadıysa yedekleme kullanılamaz).
  bool get isConfigured;

  /// Hesap seçtirir ve Drive izni ister. Bağlanan hesabın e-postasını döndürür.
  /// Kullanıcı vazgeçerse `null`.
  Future<String?> connect();

  /// Ekran göstermeden bağlantıyı tazeler (uygulama açılışında). Başarırsa e-posta.
  Future<String?> restoreSilently();

  /// Drive deposunu açar. [interactive] false iken ekran gösterilmez; bağlantı
  /// yoksa [BackupNeedsSignIn] fırlatılır.
  Future<BackupStore> open({required bool interactive});

  /// Süresi dolmuş erişim anahtarını unutur (bir sonraki [open] yenisini alır).
  Future<void> forgetToken();

  /// Bağlantıyı ve verilen izni kaldırır.
  Future<void> disconnect();
}

/// Sessizce bağlanılamadı; kullanıcının yedekleme ekranından bağlanması gerekiyor.
class BackupNeedsSignIn implements Exception {
  const BackupNeedsSignIn();
}

class GoogleDriveConnection implements DriveConnection {
  static const _scopes = [drive.DriveApi.driveAppdataScope];

  final _signIn = GoogleSignIn.instance;
  Future<void>? _initialized;
  GoogleSignInAccount? _account;
  String? _token;

  Future<void> _init() =>
      _initialized ??= _signIn.initialize(serverClientId: googleServerClientId);

  @override
  bool get isConfigured => googleServerClientId.isNotEmpty;

  @override
  Future<String?> connect() async {
    await _init();
    try {
      final account = await _signIn.authenticate(scopeHint: _scopes);
      await account.authorizationClient.authorizeScopes(_scopes);
      _account = account;
      return account.email;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  @override
  Future<String?> restoreSilently() async {
    await _init();
    _account ??= await _signIn.attemptLightweightAuthentication();
    return _account?.email;
  }

  @override
  Future<BackupStore> open({required bool interactive}) async {
    await _init();
    var account = _account;
    if (account == null) {
      if (!interactive) throw const BackupNeedsSignIn();
      account = _account = await _signIn.authenticate(scopeHint: _scopes);
    }
    var authorization = await account.authorizationClient
        .authorizationForScopes(_scopes);
    if (authorization == null) {
      if (!interactive) throw const BackupNeedsSignIn();
      authorization = await account.authorizationClient.authorizeScopes(
        _scopes,
      );
    }
    _token = authorization.accessToken;
    return DriveBackupStore(
      drive.DriveApi(authorization.authClient(scopes: _scopes)),
    );
  }

  @override
  Future<void> forgetToken() async {
    final token = _token;
    _token = null;
    final account = _account;
    if (token != null && account != null) {
      await account.authorizationClient.clearAuthorizationToken(
        accessToken: token,
      );
    }
  }

  @override
  Future<void> disconnect() async {
    await _init();
    _account = null;
    _token = null;
    try {
      await _signIn.disconnect();
    } on GoogleSignInException {
      // İzin zaten kalkmışsa da bağlantı kesilmiş sayılır.
    }
  }
}
