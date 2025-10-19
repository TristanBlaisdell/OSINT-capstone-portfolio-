// File: Chat_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pointycastle/export.dart' as pc;
import '../security/private_key_provider.dart';
import '../utils/key_manager.dart';
import '../security/encrypted_storage_manager.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../screens/video_player_screen.dart';
import 'dart:typed_data'; // ✅ for Uint8List



class Chat_screen extends StatefulWidget {
  final String chatId;

  const Chat_screen({Key? key, required this.chatId}) : super(key: key);

  @override
  State<Chat_screen> createState() => _Chat_screenState();
}

class _Chat_screenState extends State<Chat_screen> {
  final currentUser = FirebaseAuth.instance.currentUser!;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final _picker = ImagePicker();

  Future<String> _writeTempFile(Uint8List bytes,
      {required String filenameHint}) async {
    final tmp = await getTemporaryDirectory();
    final file = File('${tmp.path}/$filenameHint');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> _openVideo(Map<String, dynamic> msg) async {
    final uid = currentUser.uid;
    final wrapped = Map<String, dynamic>.from(msg['wrappedKeys'] as Map);
    final wrappedForMe = wrapped[uid] as String?;
    if (wrappedForMe == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No key for this user')));
      return;
    }

    final priv = Provider.of<PrivateKeyProvider>(context, listen: false).privateKey;
    if (priv == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unlock your key to view')));
      return;
    }

    final fileKey = KeyManager.decryptAESKeyWithRSA(wrappedForMe, priv);
    if (fileKey == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Decryption failed')));
      return;
    }

    // ✅ Stream-download & decrypt straight to a temp clear file (good for large videos)
    final decPath = await EncryptedStorageManager.downloadDecryptToFile(
      storagePath: msg['storagePath'],
      fileKey: fileKey,
    );

    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VideoPlayerScreen(filePath: decPath),
    ));
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Private Chat")),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(widget.chatId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data!.docs;

                return ListView.builder(
                  reverse: true,
                  controller: _scrollController,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final doc = messages[index];
                    final msg = doc.data() as Map<String, dynamic>;
                    final fromSelf = msg['senderId'] == currentUser.uid;

                    final type = msg['type'] as String? ?? 'text';
                    if (type == 'media') {
                      return FutureBuilder<Widget>(
                        future: _renderMedia(msg),
                        builder: (context, snap) {
                          final child = switch (snap.connectionState) {
                            ConnectionState.done =>
                            snap.data ?? const Text('[Failed to render]'),
                            _ => const Text('[Decrypting media…]'),
                          };
                          return _bubble(fromSelf, child);
                        },
                      );
                    }

                    // default: text (supports BOTH your old 1:1 schema and optional new 'type:text')
                    final privateKey = Provider
                        .of<PrivateKeyProvider>(context)
                        .privateKey;
                    return FutureBuilder<String>(
                      future: privateKey == null
                          ? Future.value('[Encrypted]')
                          : decryptHybridMessage(
                        msg,
                        currentUser.uid,
                        privateKey,
                      ),
                      builder: (context, snap) {
                        final displayedText = snap.connectionState ==
                            ConnectionState.done
                            ? (snap.data ?? '[Decryption failed]')
                            : '[Decrypting…]';
                        return _bubble(
                          fromSelf,
                          Text(
                            displayedText,
                            style: TextStyle(
                                color: fromSelf ? Colors.white : Colors.black),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                        hintText: 'Type a message...'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  onPressed: _sendMediaWithImagePicker,
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- UI helpers ----------

  Widget _bubble(bool fromSelf, Widget child) {
    return Align(
      alignment: fromSelf ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: fromSelf ? Colors.blueAccent : Colors.grey[300],
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      ),
    );
  }

  // ---------- SEND TEXT (keeps your existing 1:1 schema) ----------

  void _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    final privateKey = Provider
        .of<PrivateKeyProvider>(context, listen: false)
        .privateKey;
    if (privateKey == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Unlock your private key to send messages.')),
      );
      return;
    }

    // Chat members
    final chatRef = FirebaseFirestore.instance.collection('chats').doc(
        widget.chatId);
    final chatDoc = await chatRef.get();
    final members = List<String>.from(chatDoc['members']);
    if (members.length < 2) return;

    // Current schema is 1:1; keep compatible (pick recipient)
    final recipientId = members.firstWhere((id) => id != currentUser.uid,
        orElse: () => '');
    if (recipientId.isEmpty) return;

    // Get keys
    final users = FirebaseFirestore.instance.collection('users');
    final recipientDoc = await users.doc(recipientId).get();
    final senderDoc = await users.doc(currentUser.uid).get();
    final recipientPublicKeyPem = recipientDoc['publicKey'] as String?;
    final senderPublicKeyPem = senderDoc['publicKey'] as String?;
    if (recipientPublicKeyPem == null || senderPublicKeyPem == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Public key missing for sender or recipient.')),
      );
      return;
    }
    final recipientPublicKey = KeyManager.parsePublicKeyFromBase64(
        recipientPublicKeyPem);
    final senderPublicKey = KeyManager.parsePublicKeyFromBase64(
        senderPublicKeyPem);

    // Encrypt text with fresh AES key
    final aesKey = KeyManager.generateRandomAESKey();
    final encryptedMessage = KeyManager.encryptWithAES(content, aesKey);

    // Wrap key for both sides (legacy 1:1 fields)
    final encryptedKeyForRecipient = KeyManager.encryptAESKeyWithRSA(
        aesKey, recipientPublicKey);
    final encryptedKeyForSender = KeyManager.encryptAESKeyWithRSA(
        aesKey, senderPublicKey);

    final messageData = {
      'type': 'text', // NEW: mark as text; old readers will ignore this
      'senderId': currentUser.uid,
      'encryptedMessage': encryptedMessage,
      'aesKeyForRecipient': encryptedKeyForRecipient,
      'aesKeyForSender': encryptedKeyForSender,
      'timestamp': FieldValue.serverTimestamp(),
    };

    // Send
    final msgRef = chatRef.collection('messages').doc();
    await msgRef.set(messageData);

    // Update last message
    await chatRef.update({'lastMessage': messageData});

    _messageController.clear();
    _scrollController.animateTo(
      0.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  // ---------- SEND MEDIA (images/videos) ----------

  Future<void> _sendMediaWithImagePicker() async {
    // Let user pick an image OR a video (ask images first, then fallback to video)
    XFile? picked = await _picker.pickImage(source: ImageSource.gallery);
    picked ??= await _picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return;

    // Chat + members
    final chatRef = FirebaseFirestore.instance.collection('chats').doc(widget.chatId);
    final chatDoc = await chatRef.get();
    final members = List<String>.from(chatDoc['members']);
    if (members.isEmpty) return;

    // Build uid -> RSAPublicKey map (works for 1:1 and groups)
    final usersCol = FirebaseFirestore.instance.collection('users');
    final pubKeysByUid = <String, pc.RSAPublicKey>{};
    for (final uid in members) {
      final u = await usersCol.doc(uid).get();
      final b64 = u['publicKey'] as String;
      pubKeysByUid[uid] = KeyManager.parsePublicKeyFromBase64(b64);
    }

    // Create message docId first for a stable storage path
    final msgRef = chatRef.collection('messages').doc();

    // Decide if it’s a video (by file extension is fine here)
    final lowerName = picked.name.toLowerCase();
    final isVideo = lowerName.endsWith('.mp4') ||
        lowerName.endsWith('.mov') ||
        lowerName.endsWith('.m4v') ||
        lowerName.endsWith('.3gp') ||
        lowerName.endsWith('.webm');

    Map<String, dynamic> msgData;

    if (isVideo) {
      // ✅ NEW: streaming encryption+upload for VIDEO
      msgData = await EncryptedStorageManager.encryptUploadFileAndBuildMsg(
        inputFile: File(picked.path),
        chatId: widget.chatId,
        messageId: msgRef.id,
        pubKeysByUid: pubKeysByUid,
        originalFilename: picked.name,
      );
    } else {
      // Keep IMAGE path in-memory (small)
      final bytes = await picked.readAsBytes();
      msgData = await EncryptedStorageManager.encryptUploadAndBuildMsg(
        plaintextBytes: bytes,
        chatId: widget.chatId,
        messageId: msgRef.id,
        pubKeysByUid: pubKeysByUid,
        filenameForMime: picked.name,
        maxCacheSecs: 120,
      );
    }

    // Write Firestore message
    await msgRef.set({
      'senderId': currentUser.uid,
      ...msgData, // includes: type='media', storagePath, mimeType, wrappedKeys, timestamp
    });

    // Update last message
    await chatRef.update({
      'lastMessage': {'type': 'media', 'timestamp': FieldValue.serverTimestamp()},
    });
  }


  // ---------- DECRYPT TEXT (supports old/new schemas) ----------

  Future<String> decryptHybridMessage(Map<String, dynamic> messageData,
      String currentUserId,
      pc.RSAPrivateKey privateKey,) async {
    // Prefer wrappedKeys map if present (group-ready), else legacy 1:1 fields
    String? encryptedAESKeyBase64;
    if (messageData['wrappedKeys'] != null) {
      final map = Map<String, dynamic>.from(messageData['wrappedKeys'] as Map);
      encryptedAESKeyBase64 = map[currentUserId] as String?;
    } else {
      final isSender = messageData['senderId'] == currentUserId;
      encryptedAESKeyBase64 = isSender
          ? messageData['aesKeyForSender']
          : messageData['aesKeyForRecipient'];
    }

    final encryptedMessageBase64 = messageData['encryptedMessage'];
    try {
      if (encryptedAESKeyBase64 == null || encryptedMessageBase64 == null) {
        throw Exception('Missing key or message');
      }
      final aesKey = KeyManager.decryptAESKeyWithRSA(
          encryptedAESKeyBase64, privateKey);
      if (aesKey == null) throw Exception('AES key unwrap failed');

      final decryptedMessage = KeyManager.decryptWithAES(
          encryptedMessageBase64, aesKey);
      return decryptedMessage ?? '[decryption failed]';
    } catch (e) {
      print('[❌] Decryption failed: $e');
      return '[decryption failed]';
    }
  }

  // ---------- DECRYPT & RENDER MEDIA ----------

  Future<Widget> _renderMedia(Map<String, dynamic> msg) async {
    final uid = currentUser.uid;

    final wrapped = Map<String, dynamic>.from(msg['wrappedKeys'] as Map);
    final wrappedForMe = wrapped[uid] as String?;
    if (wrappedForMe == null) return const Text('[No key for user]');

    final priv = Provider
        .of<PrivateKeyProvider>(context, listen: false)
        .privateKey;
    if (priv == null) return const Text('[Unlock to view]');

    final fileKey = KeyManager.decryptAESKeyWithRSA(wrappedForMe, priv);
    if (fileKey == null) return const Text('[Decryption failed]');

    final mime = (msg['mimeType'] as String?) ?? 'application/octet-stream';

    // Images: decrypt inline so they render in the list
    if (mime.startsWith('image/')) {
      final bytes = await EncryptedStorageManager.downloadAndDecrypt(
        storagePath: msg['storagePath'],
        fileKey: fileKey,
        maxSizeBytes: 25 * 1024 * 1024,
      );
      return Image.memory(bytes, fit: BoxFit.cover);
    }

    // Videos: don't decrypt during list build — tap to open the player
    if (mime.startsWith('video/')) {
      return InkWell(
        onTap: () => _openVideo(msg),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.play_circle_fill, size: 28),
            SizedBox(width: 8),
            Text('Play video'),
          ],
        ),
      );
    }

    return const Text('[File received]');
  }
}
