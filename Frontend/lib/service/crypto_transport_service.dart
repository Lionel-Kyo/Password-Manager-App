import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:x509/x509.dart' as x509;
import 'package:asn1lib/asn1lib.dart';
import 'package:pointycastle/export.dart' as pc;

class CryptoTransportService {
  final _x25519 = X25519();

  final _hkdf = Hkdf(
    hmac: Hmac(Sha256()),
    outputLength: 32,
  );

  final _aes = AesGcm.with256bits();

  SimpleKeyPair? _clientKeyPair;
  SecretKey? _sessionKey;

  static const int x25519PublicKeyLength = 32;
  static const int aesGcmNonceSize = 12;
  static const int aesGcmMacSize = 16;

  Future<String> createHandshakePayload() async {
    _clientKeyPair = await _x25519.newKeyPair();
    _sessionKey = null;
    final pubKey = await _clientKeyPair!.extractPublicKey();

    if (pubKey.bytes.length != x25519PublicKeyLength) {
      throw Exception(
        'Invalid X25519 public key length',
      );
    }

    return jsonEncode({
      'action': 'handshake',
      'client_public_key': base64Encode(pubKey.bytes),
    });
  }

  Future<void> processHandshakeResponse(
    String responseJson,
    String expectedCertPem,
  ) async {
    if (_clientKeyPair == null) {
      throw Exception('Handshake failed: Client key pair not initialized');
    }

    final decoded = jsonDecode(responseJson);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Handshake failed: Invalid response');
    }

    final resp = decoded;
    if (resp['status'] != 'ok') {
      throw Exception('Handshake rejected by server: ${resp['status']}');
    }

    final serverPubKeyB64 = resp['server_public_key'];
    final certB64 = resp['certificate'];
    final signatureB64 = resp['signature'];

    if (serverPubKeyB64 is! String || certB64 is! String || signatureB64 is! String) {
      throw Exception('Handshake failed: Missing handshake fields');
    }

    final serverPubKeyBytes = base64Decode(serverPubKeyB64);

    if (serverPubKeyBytes.length != x25519PublicKeyLength) {
      throw Exception('Handshake failed: Invalid server public key length');
    }

    final certPemString =utf8.decode(base64Decode(certB64));
    final signatureBytes = base64Decode(signatureB64);

    if (expectedCertPem.trim() != certPemString.trim()) {
      throw Exception('Handshake failed: Certificate pinning mismatch');
    }

    final pemObjects = x509.parsePem(expectedCertPem);
    final certificates = pemObjects.whereType<x509.X509Certificate>();

    if (certificates.isEmpty) {
      throw Exception(
        'Handshake failed: No X509 certificate found',
      );
    }

    final cert = certificates.first;
    final now = DateTime.now().toUtc();
    final validity = cert.tbsCertificate.validity;

    if (validity == null) {
      throw Exception(
        'Handshake failed: Certificate missing validity information',
      );
    }

    if (now.isBefore(validity.notBefore) || now.isAfter(validity.notAfter)) {
      throw Exception('Handshake failed: Server certificate expired or not yet valid');
    }

    final clientPubKey = await _clientKeyPair!.extractPublicKey();

    final signedData = Uint8List.fromList([
      ...serverPubKeyBytes,
      ...clientPubKey.bytes,
    ]);

    final hashedData = Uint8List.fromList((await Sha256().hash(signedData)).bytes);

    // Parse ECDSA signature
    final asn1Parser = ASN1Parser(signatureBytes);
    final seq = asn1Parser.nextObject() as ASN1Sequence;

    if (seq.elements.length != 2) {
      throw Exception('Handshake failed: Invalid ECDSA signature');
    }

    final r =(seq.elements[0] as ASN1Integer).valueAsBigInteger;
    final s = (seq.elements[1] as ASN1Integer).valueAsBigInteger;
    final ecSignature = pc.ECSignature(r, s);

    // Extract certificate public key
    final subjectPubKeyInfo = cert.tbsCertificate.subjectPublicKeyInfo;

    if (subjectPubKeyInfo == null) {
      throw Exception('Handshake failed: Certificate is missing public key information');
    }

    final publicKey = subjectPubKeyInfo.subjectPublicKey;

    if (publicKey is! x509.EcPublicKey) {
      throw Exception('Handshake failed: Certificate public key is not an EC key');
    }

    final domainParams = pc.ECDomainParameters('prime256v1');

    final q = domainParams.curve.createPoint(publicKey.xCoordinate, publicKey.yCoordinate);
    final pcPublicKey = pc.ECPublicKey(q, domainParams);
    final verifier = pc.ECDSASigner(null, null)..init(false, pc.PublicKeyParameter<pc.ECPublicKey>(pcPublicKey));

    final isSignatureValid = verifier.verifySignature(
      hashedData,
      ecSignature,
    );

    if (!isSignatureValid) {
      throw Exception('Handshake failed: Invalid server signature');
    }

    // Derive session key
    await _computeSessionKey(
      serverPubKeyBytes,
    );
  }

  Future<void> _computeSessionKey(
    List<int> serverPubKeyBytes,
  ) async {
    if (serverPubKeyBytes.length !=
        x25519PublicKeyLength) {
      throw Exception('Invalid server X25519 public key');
    }

    if (_clientKeyPair == null) {
      throw Exception('Client key pair is not initialized');
    }

    final serverPubKey = SimplePublicKey(
      serverPubKeyBytes,
      type: KeyPairType.x25519,
    );

    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: _clientKeyPair!,
      remotePublicKey: serverPubKey,
    );

    _sessionKey = await _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: const [],
      info: utf8.encode(
        'websocket-ecc-aes-handshake',
      ),
    );
  }

  Future<String> encryptPayload(
    Map<String, dynamic> payload,
  ) async {
    final sessionKey = _sessionKey;

    if (sessionKey == null) {
      throw Exception('Session key uninitialized');
    }

    final jsonBytes = utf8.encode(jsonEncode(payload));

    final secretBox = await _aes.encrypt(
      jsonBytes,
      secretKey: sessionKey,
    );

    final combined = Uint8List.fromList([
      ...secretBox.nonce,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);

    return jsonEncode({
      'payload': base64Encode(combined),
    });
  }

  Future<Map<String, dynamic>> decryptEnvelope(
    String encryptedPayload,
  ) async {
    final sessionKey = _sessionKey;

    if (sessionKey == null) {
      throw Exception(
        'Session key uninitialized',
      );
    }

    final combined = base64Decode(encryptedPayload);

    if (combined.length < aesGcmNonceSize + aesGcmMacSize) {
      throw Exception('Encrypted payload too short');
    }

    final nonce = combined.sublist(0, aesGcmNonceSize);
    final cipherText = combined.sublist(aesGcmNonceSize, combined.length - aesGcmMacSize);
    final macBytes = combined.sublist(combined.length - aesGcmMacSize);

    final secretBox = SecretBox(
      cipherText,
      nonce: nonce,
      mac: Mac(macBytes),
    );

    final decryptedBytes = await _aes.decrypt(secretBox, secretKey: sessionKey,);
    final decoded = jsonDecode(utf8.decode(decryptedBytes));

    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid decrypted response payload');
    }

    return decoded;
  }

  void dispose() {
    _sessionKey = null;
    _clientKeyPair = null;
  }
}
