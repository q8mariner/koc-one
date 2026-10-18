// End-to-end encryption of 160 reports (compatible with the ORT dashboard WebCrypto code).
// AES-256-GCM per report → blob = iv(12) | ciphertext | tag(16), base64.
// The AES key is wrapped with the ORT RSA public key (RSA-OAEP, SHA-1 / MGF1-SHA-1).
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

class SecureReport {
  final Uint8List _key;
  final RSAPublicKey _pub;

  SecureReport._(this._key, this._pub);

  factory SecureReport.forJwk(Map<String, dynamic> jwk) {
    final n = _b64urlToBigInt(jwk['n'] as String);
    final e = _b64urlToBigInt(jwk['e'] as String);
    return SecureReport._(_random(32), RSAPublicKey(n, e));
  }

  static Uint8List _random(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
  }

  static BigInt _b64urlToBigInt(String s) {
    final bytes = base64Url.decode(base64Url.normalize(s));
    var result = BigInt.zero;
    for (final b in bytes) {
      result = (result << 8) | BigInt.from(b);
    }
    return result;
  }

  /// base64(RSA-OAEP(aesKey))
  String wrappedKey() {
    final oaep = OAEPEncoding(RSAEngine())..init(true, PublicKeyParameter<RSAPublicKey>(_pub));
    return base64Encode(oaep.process(_key));
  }

  Uint8List sealBytes(Uint8List plain) {
    final iv = _random(12);
    final gcm = GCMBlockCipher(AESEngine())..init(true, AEADParameters(KeyParameter(_key), 128, iv, Uint8List(0)));
    final ct = gcm.process(plain);
    final out = Uint8List(iv.length + ct.length)
      ..setAll(0, iv)
      ..setAll(iv.length, ct);
    return out;
  }

  String sealJson(Map<String, dynamic> data) => base64Encode(sealBytes(Uint8List.fromList(utf8.encode(jsonEncode(data)))));
}
