// File: lib/security/encrypted_storage_manager.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:mime/mime.dart';
import 'package:pointycastle/export.dart' as pc;

import '../utils/key_manager.dart';

class EncryptedStorageManager {
  /// Encrypt bytes in memory with AES-GCM (nonce||ct||tag), upload to Storage,
  /// and return Firestore message payload (incl. per-user wrapped keys).
  static Future<Map<String, dynamic>> encryptUploadAndBuildMsg({
    required Uint8List plaintextBytes,
    required String chatId,
    required String messageId, // precreated doc id
    required Map<String, pc.RSAPublicKey> pubKeysByUid, // uid -> public key
    String? filenameForMime,
    int? maxCacheSecs, // e.g. 120
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final storagePath = 'chats/$chatId/messages/$messageId.bin';
    print('[Storage][UPLOAD] uid=$uid path=$storagePath');

    // 1) Encrypt (AES-256 GCM, returns nonce||ct||tag)
    final fileKey = KeyManager.generateRandomAESKey();
    final encrypted = KeyManager.encryptBytesAesGcm(fileKey, plaintextBytes);

    // 2) Upload to Storage
    final ref = FirebaseStorage.instance.ref(storagePath);
    final mime = lookupMimeType(
      filenameForMime ?? '',
      headerBytes: plaintextBytes.take(12).toList(),
    ) ??
        'application/octet-stream';

    try {
      await ref.putData(
        encrypted,
        SettableMetadata(
          contentType: mime,
          cacheControl: maxCacheSecs != null ? 'public,max-age=$maxCacheSecs' : null,
        ),
      );
      print('[Storage][UPLOAD] success (${encrypted.length} bytes, mime=$mime)');
    } on FirebaseException catch (e) {
      print('[Storage][UPLOAD] FAILED code=${e.code} msg=${e.message}');
      rethrow;
    }

    // 3) Wrap key for each participant
    final wrapped = <String, String>{};
    pubKeysByUid.forEach((userId, pubKey) {
      wrapped[userId] = KeyManager.encryptAESKeyWithRSA(fileKey, pubKey);
    });

    // 4) Return message doc data (small metadata only)
    return {
      'type': 'media',
      'storagePath': storagePath,
      'fileSize': encrypted.length,
      'mimeType': mime,
      'wrappedKeys': wrapped, // { uid: base64(RSA-OAEP(fileKey)) }
      'timestamp': FieldValue.serverTimestamp(),
    };
  }

  /// Download ciphertext (nonce||ct||tag) and decrypt to bytes using fileKey.
  static Future<Uint8List> downloadAndDecrypt({
    required String storagePath,
    required Uint8List fileKey,
    int maxSizeBytes = 25 * 1024 * 1024, // 25MB cap; raise for larger videos
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    print('[Storage][DOWNLOAD] uid=$uid path=$storagePath max=$maxSizeBytes');

    final ref = FirebaseStorage.instance.ref(storagePath);
    Uint8List? encrypted;
    try {
      encrypted = await ref.getData(maxSizeBytes);
    } on FirebaseException catch (e) {
      print('[Storage][DOWNLOAD] FAILED code=${e.code} msg=${e.message}');
      rethrow;
    }

    if (encrypted == null) {
      throw StateError('Download returned null');
    }

    final plain = KeyManager.decryptBytesAesGcm(fileKey, encrypted);
    if (plain == null) {
      throw StateError('Decryption failed');
    }

    print('[Storage][DOWNLOAD] success (${plain.length} bytes)');
    return plain;
  }

  // ====== STREAMING UPLOAD (videos): encrypt from a File and upload with putFile ======
  // AES-GCM streaming: write nonce first, then ct, then tag (emitted by doFinal).
  static Future<Map<String, dynamic>> encryptUploadFileAndBuildMsg({
    required File inputFile,
    required String chatId,
    required String messageId,
    required Map<String, pc.RSAPublicKey> pubKeysByUid,
    String? originalFilename,
    int chunkSize = 256 * 1024, // 256KB
  }) async {
    // 1) Create AES-GCM state
    final key32 = KeyManager.generateRandomAESKey(); // 32 bytes
    final nonce = KeyManager.randomBytes(12);
    final gcm = pc.GCMBlockCipher(pc.AESEngine());
    final params = pc.AEADParameters(pc.KeyParameter(key32), 128, nonce, Uint8List(0));
    gcm.init(true, params);

    // 2) Stream encrypt into a temp file: [nonce][ct...][tag]
    final encPath = _tmpPath('enc_${messageId}.bin');
    final encSink = File(encPath).openWrite();
    encSink.add(nonce); // prefix nonce

    final raf = await inputFile.open();
    try {
      final buf = Uint8List(chunkSize);
      while (true) {
        final n = await raf.readInto(buf, 0, buf.length);
        if (n == 0) break;
        final chunk = (n == buf.length) ? buf : Uint8List.sublistView(buf, 0, n);

        // processBytes requires output buffer sized for getOutputSize(len)
        final out = Uint8List(gcm.getOutputSize(chunk.length));
        final produced = gcm.processBytes(chunk, 0, chunk.length, out, 0);
        if (produced > 0) encSink.add(out.sublist(0, produced));
      }

      // doFinal writes the auth tag (and any final block) to out buffer
      final tail = Uint8List(gcm.getOutputSize(0));
      final tailLen = gcm.doFinal(tail, 0);
      if (tailLen > 0) encSink.add(tail.sublist(0, tailLen));
    } finally {
      await encSink.close();
      await raf.close();
    }

    // 3) Upload encrypted file
    final storagePath = 'chats/$chatId/messages/$messageId.bin';
    final ref = FirebaseStorage.instance.ref(storagePath);
    final guessedMime =
        lookupMimeType(originalFilename ?? inputFile.path) ?? 'application/octet-stream';

    await ref.putFile(
      File(encPath),
      SettableMetadata(
        contentType: guessedMime,
        cacheControl: 'public,max-age=120',
      ),
    );

    // 4) Wrap key for each participant
    final wrapped = <String, String>{};
    pubKeysByUid.forEach((uid, pubKey) {
      wrapped[uid] = KeyManager.encryptAESKeyWithRSA(key32, pubKey);
    });

    final encSize = await File(encPath).length();

    return {
      'type': 'media',
      'storagePath': storagePath,
      'fileSize': encSize,
      'mimeType': guessedMime,
      'wrappedKeys': wrapped,
      'timestamp': FieldValue.serverTimestamp(),
    };
  }

  // ====== STREAMING DOWNLOAD (videos): download encrypted -> decrypt to temp clear file ======
  // Returns the path to a decrypted temp file you can hand to video_player.
  static Future<String> downloadDecryptToFile({
    required String storagePath,
    required Uint8List fileKey,
    int chunkSize = 256 * 1024,
  }) async {
    final encPath = _tmpPath('dl_${_safe(storagePath)}.bin');
    final decPath = _tmpPath('dec_${_safe(storagePath)}');

    // 1) Download encrypted to disk
    final ref = FirebaseStorage.instance.ref(storagePath);
    await ref.writeToFile(File(encPath));

    // 2) Open for streaming decrypt
    final raf = await File(encPath).open();
    try {
      // Read nonce (12 bytes)
      final nonce = Uint8List(12);
      final readNonce = await raf.readInto(nonce, 0, 12);
      if (readNonce != 12) {
        throw StateError('Corrupt blob: missing nonce');
      }

      final gcm = pc.GCMBlockCipher(pc.AESEngine());
      final params =
      pc.AEADParameters(pc.KeyParameter(fileKey), 128, nonce, Uint8List(0));
      gcm.init(false, params);

      final decSink = File(decPath).openWrite();
      try {
        final buf = Uint8List(chunkSize);
        while (true) {
          final n = await raf.readInto(buf, 0, buf.length);
          if (n == 0) break;
          final chunk = (n == buf.length) ? buf : Uint8List.sublistView(buf, 0, n);

          final out = Uint8List(gcm.getOutputSize(chunk.length));
          final produced = gcm.processBytes(chunk, 0, chunk.length, out, 0);
          if (produced > 0) decSink.add(out.sublist(0, produced));
        }

        final tail = Uint8List(gcm.getOutputSize(0));
        final tailLen = gcm.doFinal(tail, 0); // verifies tag; throws if wrong
        if (tailLen > 0) decSink.add(tail.sublist(0, tailLen));
      } finally {
        await decSink.close();
      }
    } finally {
      await raf.close();
    }

    return decPath;
  }

  // ---- tiny helpers ----
  static String _tmpPath(String name) {
    final dir = Directory.systemTemp;
    return '${dir.path}/${name.replaceAll(RegExp(r"[^A-Za-z0-9._-]"), "_")}';
    // If you prefer app cache dir: use path_provider.getTemporaryDirectory() in caller.
  }

  static String _safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
}
