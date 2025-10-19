import 'package:cloud_firestore/cloud_firestore.dart';

class Comment {
  final String id;
  final String threadId;
  final String? parentId;
  final int depth;
  final String sortKey;
  final String body;
  final String authorId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int score;
  final int replyCount;
  final bool isRemoved;
  final bool isLocked;
  final List<String> ancestors;

  Comment({
    required this.id,
    required this.threadId,
    this.parentId,
    required this.depth,
    required this.sortKey,
    required this.body,
    required this.authorId,
    required this.createdAt,
    required this.updatedAt,
    required this.score,
    required this.replyCount,
    required this.isRemoved,
    required this.isLocked,
    required this.ancestors,
  });

  factory Comment.fromMap(Map<String, dynamic> map, String id) {
    return Comment(
      id: id,
      threadId: map['thread_id'] ?? '',
      parentId: map['parent_id'],
      depth: (map['depth'] ?? 0) as int,
      sortKey: map['sort_key'] ?? '',
      body: map['body'] ?? '',
      authorId: map['author_id'] ?? '',
      createdAt: (map['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (map['updated_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      score: (map['score'] ?? 0) as int,
      replyCount: (map['reply_count'] ?? 0) as int,
      isRemoved: (map['is_removed'] ?? false) as bool,
      isLocked: (map['is_locked'] ?? false) as bool,
      ancestors: List<String>.from(map['ancestors'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'thread_id': threadId,
      'parent_id': parentId,
      'depth': depth,
      'sort_key': sortKey,
      'body': body,
      'author_id': authorId,
      'created_at': Timestamp.fromDate(createdAt),
      'updated_at': Timestamp.fromDate(updatedAt),
      'score': score,
      'reply_count': replyCount,
      'is_removed': isRemoved,
      'is_locked': isLocked,
      'ancestors': ancestors,
    };
  }
}


