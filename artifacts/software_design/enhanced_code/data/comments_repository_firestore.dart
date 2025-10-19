import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import '../models/comment.dart'; // adjust path to your comment.dart

class CommentsRepositoryFirestore {
  final fs.FirebaseFirestore db;
  CommentsRepositoryFirestore({fs.FirebaseFirestore? instance})
      : db = instance ?? fs.FirebaseFirestore.instance;

  /// Create or upsert a comment document in the flat collection.
  Future<void> upsertComment(Comment c) async {
    await db.collection('comments').doc(c.id).set(c.toMap(), fs.SetOptions(merge: true));
  }

  /// Fetch a parent comment to compute depth/ancestors (or return null).
  Future<Map<String, dynamic>?> getParent(String parentId) async {
    final doc = await db.collection('comments').doc(parentId).get();
    return doc.exists ? doc.data() : null;
  }

  /// Increment reply_count on parent and (optionally) a thread-level post doc if you keep one in Firestore.
  Future<void> bumpCounters({required String threadId, String? parentId}) async {
    final batch = db.batch();
    if (parentId != null) {
      final parentRef = db.collection('comments').doc(parentId);
      batch.update(parentRef, {'reply_count': fs.FieldValue.increment(1)});
    }
    // Optional: if you also mirror a posts/{threadId} doc:
    // final postRef = db.collection('posts').doc(threadId);
    // batch.update(postRef, {'comment_count': fs.FieldValue.increment(1)});
    await batch.commit();
  }

  // ---------- Voting dual-write ----------
  Future<void> voteComment({
    required String commentId,
    required String userId,
    required int newValue, // -1 or +1 (toggle-only)
  }) async {
    final commentRef = db.collection('comments').doc(commentId);
    final voteRef = commentRef.collection('votes').doc(userId);

    await db.runTransaction((tx) async {
      final commentSnap = await tx.get(commentRef);
      if (!commentSnap.exists) return;

      final voteSnap = await tx.get(voteRef);
      final prev = voteSnap.exists ? (voteSnap.data()?['value'] ?? 0) as int : 0;
      if (prev == newValue) return;

      final delta = newValue - prev; // -2, -1, +1, +2
      tx.update(commentRef, {'score': fs.FieldValue.increment(delta)});
      tx.set(voteRef, {
        'value': newValue,
        'at': fs.FieldValue.serverTimestamp(),
      });
    });
  }

  /// Update moderation flags on a comment (merge-style).
  Future<void> updateCommentFlags({
    required String commentId,
    bool? isRemoved,
    bool? isLocked,
  }) async {
    final updates = <String, Object?>{};
    if (isRemoved != null) updates['is_removed'] = isRemoved;
    if (isLocked != null) updates['is_locked'] = isLocked;
    if (updates.isEmpty) return;
    await db.collection('comments').doc(commentId).update(updates);
  }

  /// Record a moderation action (audit log).
  Future<void> logModeration({
    required String actorId,
    required String action, // 'remove' | 'restore' | 'lock' | 'unlock'
    required String targetCommentId,
    required String threadId,
    String? reason,
  }) async {
    await db.collection('moderation_actions').add({
      'actor_id': actorId,
      'action': action,
      'target_comment_id': targetCommentId,
      'thread_id': threadId,
      'reason': reason,
      'at': fs.FieldValue.serverTimestamp(),
    });
  }
}
