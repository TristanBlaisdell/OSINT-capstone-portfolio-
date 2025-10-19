import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart' as rtdb;
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import '../models/comment.dart';                     // lib/models/comment.dart
import '../data/comments_repository_firestore.dart'; // lib/data/comments_repository_firestore.dart

class PostDetailScreen extends StatefulWidget {
  final Map<String, dynamic> post;

  const PostDetailScreen({Key? key, required this.post}) : super(key: key);

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  // track whether a parent still has more pages
  final Map<String, bool> _childHasMore = {};

  // optimistic UI for my vote per commentId: -1, 0, +1
  final Map<String, int> _myVotes = {};

  // --- Realtime DB roots
  final rtdb.DatabaseReference _postsRef =
  rtdb.FirebaseDatabase.instance.ref('forum_posts');
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  String _buildSortKey(int createdAtMs, String id) {
    // keyset-friendly (lexicographically sortable, stable tiebreaker)
    final padded = createdAtMs.toString().padLeft(13, '0');
    return '${padded}_$id';
  }

  // --- UI & layout
  String _sortOption = 'Top'; // Top | New | Old
  final Map<String, bool> _collapsedStates = {};
  final int maxIndent = 5;
  final double indentWidth = 16.0;

  // --- Pagination config
  final int _pageSize = 20;

  // Top-level paging state
  String? _topLastTs; // last loaded timestampMs (stringified)
  final List<MapEntry<String, Map<String, dynamic>>> _topSlice = [];

  // Children paging state
  final Map<String, String?> _childLastTs = {}; // parentId -> last timestampMs
  final Map<String, List<MapEntry<String, Map<String, dynamic>>>> _childSlices = {}; // parentId -> list

  // --- MOD ROLES ---
  String? _myRole; // 'Owner' | 'Moderator' | 'User'

  Future<void> _loadMyRoleOnce() async {
    if (_currentUser == null || _myRole != null) return;
    try {
      final doc = await fs.FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .get();
      _myRole = (doc.data()?['role'] as String?)?.trim(); // e.g. 'Moderator'
      if (mounted) setState(() {}); // reveal mod controls if applicable
    } catch (_) {
      // ignore; role stays null -> no mod controls
    }
  }

  bool _canModerate(String? authorUid) {
    if (_currentUser == null) return false;
    if (authorUid == _currentUser!.uid) return true;           // author can edit their own
    final role = _myRole ?? '';
    return role == 'Owner' || role == 'Moderator';             // mods/owners can moderate
  }

  Future<void> _modSetLock({
    required rtdb.DatabaseReference replyRef,
    required String commentId,
    required bool lock,
  }) async {
    // RTDB flag
    await replyRef.update({'is_locked': lock});

    // Firestore mirror + audit
    final repo = CommentsRepositoryFirestore();
    await repo.updateCommentFlags(commentId: commentId, isLocked: lock);
    await repo.logModeration(
      actorId: _currentUser!.uid,
      action: lock ? 'lock' : 'unlock',
      targetCommentId: commentId,
      threadId: widget.post['post_id'],
    );

    if (mounted) setState(() {});
  }

  Future<void> _modSetRemoved({
    required rtdb.DatabaseReference replyRef,
    required String commentId,
    required bool removed,
  }) async {
    // RTDB soft removal
    await replyRef.update({
      'is_removed': removed,
      if (removed) 'comment': 'Deleted',
      'edited': true,
    });

    // Firestore mirror + audit
    final repo = CommentsRepositoryFirestore();
    await repo.updateCommentFlags(commentId: commentId, isRemoved: removed);
    await repo.logModeration(
      actorId: _currentUser!.uid,
      action: removed ? 'remove' : 'restore',
      targetCommentId: commentId,
      threadId: widget.post['post_id'],
    );

    if (mounted) setState(() {});
  }


  @override
  void initState() {
    super.initState();
    _loadMyRoleOnce();          // <-- added
    _loadReplies(reset: true);  // existing
  }


  // ------------------------------------------------------------
  // Loading: top-level page (shallow)
  // ------------------------------------------------------------
  Future<void> _loadReplies({bool reset = false}) async {
    final base = _postsRef
        .child(widget.post['category'])
        .child(widget.post['post_id'])
        .child('replies');

    if (reset) {
      _topSlice.clear();
      _topLastTs = null;
    }

    rtdb.Query q = base.orderByChild('timestampMs');
    if (_topLastTs != null) {
      q = q.startAt(int.parse(_topLastTs!));
    }
    q = q.limitToFirst(_pageSize + 1); // +1 so we can drop the startAt duplicate

    final rtdb.DataSnapshot snap = await q.get();
    if (!snap.exists || snap.value == null) {
      if (mounted) setState(() {});
      return;
    }

    final map = Map<String, dynamic>.from(snap.value as Map);
    final entries = map.entries
        .map((e) => MapEntry(e.key, Map<String, dynamic>.from(e.value)))
        .toList();

    // sort oldest->newest by timestampMs to handle startAt
    entries.sort((a, b) => ((a.value['timestampMs'] ?? 0) as int)
        .compareTo((b.value['timestampMs'] ?? 0) as int));

    // If this is a continuation, drop the first (startAt duplicate)
    final page = (_topLastTs == null) ? entries : entries.skip(1).toList();

    // apply current sort to the page we show
    _sortEntriesInPlace(page);

    if (page.isNotEmpty) {
      _topSlice.addAll(page);
      _topLastTs = (page.last.value['timestampMs'] ?? 0).toString();
    }
    if (mounted) setState(() {});
  }

  // ------------------------------------------------------------
  // Loading: one page of children for a specific parent
  // ------------------------------------------------------------
  Future<void> _loadChildPage(
      rtdb.DatabaseReference parentRepliesRef,
      String parentId, {
        bool reset = false,
      }) async {
    _childSlices[parentId] ??= [];
    if (reset) {
      _childSlices[parentId]!.clear();
      _childLastTs[parentId] = null;
      _childHasMore[parentId] = true;
    }

    if (_childHasMore[parentId] == false) {
      if (mounted) setState(() {});
      return;
    }

    rtdb.Query q = parentRepliesRef.orderByChild('timestampMs');
    final last = _childLastTs[parentId];
    if (last != null) q = q.startAt(int.parse(last));
    q = q.limitToFirst(_pageSize + 1);

    final rtdb.DataSnapshot snap = await q.get();
    if (!snap.exists || snap.value == null) {
      _childHasMore[parentId] = false;
      if (mounted) setState(() {});
      return;
    }

    final map = Map<String, dynamic>.from(snap.value as Map);
    final entries = map.entries
        .map((e) => MapEntry(e.key, Map<String, dynamic>.from(e.value)))
        .toList();

    entries.sort((a, b) => ((a.value['timestampMs'] ?? 0) as int)
        .compareTo((b.value['timestampMs'] ?? 0) as int));

    var page = (last == null) ? entries : entries.skip(1).toList();
    _sortEntriesInPlace(page);

    // hasMore if raw page (after skipping) filled the page size
    _childHasMore[parentId] = page.length >= _pageSize;

    if (page.isNotEmpty) {
      _childSlices[parentId]!.addAll(page);
      _childLastTs[parentId] = (page.last.value['timestampMs'] ?? 0).toString();
    }

    if (mounted) setState(() {});
  }

  // load my existing vote for a comment (so icons can show active state)
  Future<void> _ensureMyVoteLoaded(String commentId, rtdb.DatabaseReference replyRef) async {
    if (_currentUser == null) return;
    if (_myVotes.containsKey(commentId)) return; // already cached
    final snap = await replyRef.child('votes').child(_currentUser!.uid).get();
    if (snap.exists && snap.value is int) {
      setState(() => _myVotes[commentId] = snap.value as int);
    } else {
      _myVotes[commentId] = 0; // cache zero to avoid re-fetching
    }
  }

// bump the displayed score in local lists (optimistic)
  void _bumpScoreLocal(String commentId, int delta) {
    // top-level
    for (var i = 0; i < _topSlice.length; i++) {
      if (_topSlice[i].key == commentId) {
        final v = _topSlice[i].value;
        v['score'] = ((v['score'] ?? 0) as int) + delta;
        setState(() {});
        return;
      }
    }
    // children
    for (final entry in _childSlices.entries) {
      final list = entry.value;
      for (var i = 0; i < list.length; i++) {
        if (list[i].key == commentId) {
          final v = list[i].value;
          v['score'] = ((v['score'] ?? 0) as int) + delta;
          setState(() {});
          return;
        }
      }
    }
  }

// the optimistic vote handler you call from the UI
  Future<void> _onVoteTap({
    required String commentId,
    required rtdb.DatabaseReference replyRef,
    required bool down,
  }) async {
    if (_currentUser == null) return;

    final prev = _myVotes[commentId] ?? 0;   // -1, 0, +1
    final next = down ? -1 : 1;
    if (prev == next) return;                // (simple toggle; unvote optional)

    final delta = next - prev;               // -2, -1, +1, +2
    _myVotes[commentId] = next;              // optimistic UI
    _bumpScoreLocal(commentId, delta);       // optimistic UI

    // RTDB source of truth (your existing transactional write)
    await _voteLimited(replyRef, down: down);

    // Firestore mirror (best-effort; don't block UI)
    Future.microtask(() async {
      try {
        final repo = CommentsRepositoryFirestore();
        await repo.voteComment(
          commentId: commentId,
          userId: _currentUser!.uid,
          newValue: next, // -1 or +1
        );
      } catch (e) {
        debugPrint('FS vote mirror failed: $e');
      }
    });
  }


// small helper just for vote chips with active color
  Widget _voteChip(IconData icon, String label, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: active ? Colors.blue : Colors.grey[700]),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ],
      ),
    );
  }


  String _replyControlLabel(String parentId, Map<String, dynamic> reply, bool isCollapsed) {
    final count = (reply['reply_count'] ?? 0) as int;
    if (isCollapsed) return count > 0 ? 'View replies ($count)' : 'View replies';
    if ((_childHasMore[parentId] ?? false) == true) return 'Load more replies';
    return 'Hide replies';
  }

  Future<void> _onReplyControlTap({
    required String parentId,
    required rtdb.DatabaseReference childRef,
    required bool isCollapsed,
  }) async {
    if (isCollapsed) {
      setState(() => _collapsedStates[parentId] = false);
      if ((_childSlices[parentId] ?? const []).isEmpty) {
        await _loadChildPage(childRef, parentId, reset: true);
      }
      return;
    }
    if ((_childHasMore[parentId] ?? false) == true) {
      await _loadChildPage(childRef, parentId, reset: false);
    } else {
      setState(() => _collapsedStates[parentId] = true);
    }
  }



  // ------------------------------------------------------------
  // Sorting helper used for both top-level and children pages
  // ------------------------------------------------------------
  void _sortEntriesInPlace(List<MapEntry<String, Map<String, dynamic>>> list) {
    if (_sortOption == 'Top') {
      list.sort((a, b) => ((b.value['score'] ?? b.value['upvotes'] ?? 0) as int)
          .compareTo((a.value['score'] ?? a.value['upvotes'] ?? 0) as int));
    } else if (_sortOption == 'New') {
      list.sort((a, b) => ((b.value['timestampMs'] ?? 0) as int)
          .compareTo((a.value['timestampMs'] ?? 0) as int));
    } else {
      list.sort((a, b) => ((a.value['timestampMs'] ?? 0) as int)
          .compareTo((b.value['timestampMs'] ?? 0) as int));
    }
  }

  // ------------------------------------------------------------
  // Add / Edit reply (RTDB)
  //  - containerRef: /.../replies  (where new child is pushed)
  //  - parentReplyRef: /.../replies/{replyId}  (null for top-level)
  // ------------------------------------------------------------
  void _addOrEditReply({
    required rtdb.DatabaseReference containerRef,
    rtdb.DatabaseReference? parentReplyRef,
    bool isEditing = false,
    String? editingReplyKey,
    String existingComment = '',
    VoidCallback? onFinish,
  }) {
    final TextEditingController ctrl =
    TextEditingController(text: isEditing ? existingComment : '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEditing ? 'Edit Reply' : 'Add Reply'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.multiline,
          maxLines: null,
          decoration: const InputDecoration(
            hintText: 'Type your message...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              if (ctrl.text.trim().isEmpty) return;
              if (_currentUser == null) return;

              try {
                // username (from Firestore users/{uid})
                final userDoc = await fs.FirebaseFirestore.instance
                    .collection('users')
                    .doc(_currentUser!.uid)
                    .get();
                final username = userDoc.data()?['username'] ?? 'Unknown';

                if (isEditing && editingReplyKey != null) {
                  // ---------- RTDB edit (author or mod) ----------
                  await containerRef.child(editingReplyKey).update({
                    'comment': ctrl.text.trim(),
                    'edited': true,
                    'updatedAt': DateTime.now().toIso8601String(),
                  });

                  // ✅ close UI immediately on RTDB success
                  if (mounted) Navigator.pop(context);
                  onFinish?.call();

                  // 🔁 refresh slice
                  if (parentReplyRef == null) {
                    await _loadReplies(reset: true);
                  } else {
                    final childRepliesRef = parentReplyRef.child('replies');
                    final pid = parentReplyRef.key!;
                    await _loadChildPage(childRepliesRef, pid, reset: true);
                  }

                  // ---------- Firestore best-effort mirror (edit) ----------
                  Future.microtask(() async {
                    try {
                      final repo = CommentsRepositoryFirestore();
                      await repo.upsertComment(
                        Comment(
                          id: editingReplyKey,
                          threadId: widget.post['post_id'],
                          parentId: parentReplyRef?.key,
                          depth: 0, // unchanged here; FS doc already has real depth
                          sortKey: '', // unchanged; ignored on merge
                          body: ctrl.text.trim(),
                          authorId: _currentUser!.uid,
                          createdAt: DateTime.now(), // ignored on merge
                          updatedAt: DateTime.now(),
                          score: 0, // ignored on merge
                          replyCount: 0, // ignored on merge
                          isRemoved: false, // ignored on merge
                          isLocked: false, // ignored on merge
                          ancestors: const [], // ignored on merge
                        ),
                      );
                    } catch (e) {
                      debugPrint('Firestore edit mirror failed: $e');
                    }
                  });

                } else {
                  // ---------- Step 4a: parent preview + lock guard ----------
                  String? parentUser;
                  String? parentExcerpt;

                  if (parentReplyRef != null) {
                    final parentSnap = await parentReplyRef.get();
                    if (parentSnap.exists && parentSnap.value is Map) {
                      final p = Map<String, dynamic>.from(parentSnap.value as Map);
                      if ((p['is_locked'] ?? false) == true) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Replies are locked for this comment.'),
                            ),
                          );
                        }
                        return;
                      }
                      parentUser = p['user']?.toString();
                      final txt = (p['comment']?.toString() ?? '');
                      parentExcerpt = txt.isEmpty
                          ? null
                          : (txt.length > 120 ? '${txt.substring(0, 120)}…' : txt);
                    }
                  }

                  // ---------- RTDB create (source of truth) ----------
                  final now = DateTime.now();
                  final data = {
                    'user': username,
                    'uid': _currentUser!.uid,
                    'comment': ctrl.text.trim(),
                    'timestamp': now.toIso8601String(),
                    'timestampMs': now.millisecondsSinceEpoch,
                    'upvotes': 0,
                    'downvotes': 0,
                    'score': 0,
                    'replies': {},
                    'reply_count': 0,
                    'is_removed': false,
                    'parent_user': parentUser,
                    'parent_excerpt': parentExcerpt,
                  };

                  final newRef = containerRef.push();
                  await newRef.set(data);

                  // bump RTDB counters
                  await _bumpCountersOnCreate(parentReplyRef: parentReplyRef);

                  // ✅ close UI immediately on RTDB success
                  if (mounted) Navigator.pop(context);
                  onFinish?.call();

                  // 🔁 refresh slice
                  if (parentReplyRef == null) {
                    await _loadReplies(reset: true);
                  } else {
                    final childRepliesRef = parentReplyRef.child('replies');
                    final pid = parentReplyRef.key!;
                    await _loadChildPage(childRepliesRef, pid, reset: true);
                  }

                  // ---------- Firestore dual-write (best-effort, background) ----------
                  Future.microtask(() async {
                    try {
                      final commentId = newRef.key!;
                      final repo = CommentsRepositoryFirestore();

                      List<String> ancestors = [];
                      int depth = 0;
                      final String threadId = widget.post['post_id'];
                      final String? parentId = parentReplyRef?.key;

                      if (parentId != null) {
                        final parentDoc = await repo.getParent(parentId);
                        if (parentDoc != null) {
                          final parentAnc = List<String>.from(parentDoc['ancestors'] ?? []);
                          ancestors = [...parentAnc, parentId];
                          depth = ((parentDoc['depth'] ?? parentAnc.length) as int) + 1;
                        } else {
                          ancestors = [parentId];
                          depth = ancestors.length;
                        }
                      }

                      final comment = Comment(
                        id: commentId,
                        threadId: threadId,
                        parentId: parentId,
                        depth: depth,
                        sortKey: _buildSortKey(now.millisecondsSinceEpoch, commentId),
                        body: ctrl.text.trim(),
                        authorId: _currentUser!.uid,
                        createdAt: now,
                        updatedAt: now,
                        score: 0,
                        replyCount: 0,
                        isRemoved: false,
                        isLocked: false,
                        ancestors: ancestors,
                      );

                      await repo.upsertComment(comment);
                      await repo.bumpCounters(threadId: threadId, parentId: parentId);
                    } catch (e) {
                      debugPrint('Firestore shadow write failed: $e');
                    }
                  });
                }
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error saving reply: $e')),
                );
              }
            },
            child: Text(isEditing ? 'Update' : 'Post'),
          ),
        ],
      ),
    );
  }


  // ------------------------------------------------------------
  // Delete (soft) with basic moderation check
  // ------------------------------------------------------------
  Future<void> _deleteReplyModerated(
      rtdb.DatabaseReference replyRef, {
        rtdb.DatabaseReference? parentReplyRef,
      }) async {
    try {
      await replyRef.update(
          {'comment': 'Deleted', 'edited': true, 'is_removed': true});
      // Note: Not decrementing counters to keep tree shape stable.
      if (parentReplyRef == null) {
        await _loadReplies(reset: true);
      } else {
        final childRepliesRef = parentReplyRef.child('replies');
        final pid = parentReplyRef.key!;
        await _loadChildPage(childRepliesRef, pid, reset: true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }


  // ------------------------------------------------------------
  // One-vote-per-user with score increment
  // votes/{uid} = -1|1 ; score = sum
  // ------------------------------------------------------------
  Future<void> _voteLimited(rtdb.DatabaseReference replyRef,
      {bool down = false}) async {
    if (_currentUser == null) return;
    final uid = _currentUser!.uid;
    final voteRef = replyRef.child('votes').child(uid);
    final rtdb.DataSnapshot current = await voteRef.get();
    final int newVal = down ? -1 : 1;

    if (current.exists) {
      final prev = (current.value ?? 0) as int;
      if (prev == newVal) return; // no-op
      final delta = newVal - prev;
      await voteRef.set(newVal);
      await _incScore(replyRef, delta);
    } else {
      await voteRef.set(newVal);
      await _incScore(replyRef, newVal);
    }
  }

  Future<void> _incScore(rtdb.DatabaseReference replyRef, int delta) async {
    await replyRef.runTransaction((Object? current) {
      final Map<String, dynamic> data =
      current is Map ? Map<String, dynamic>.from(current as Map) : <String, dynamic>{};

      final int cur = (data['score'] ?? 0) as int;
      data['score'] = cur + delta;

      return rtdb.Transaction.success(data);
    });
  }


  // ------------------------------------------------------------
  // Denormalized counters
  // - parent.reply_count++  (if replying to a comment)
  // - post.comment_count++  (always)
  // ------------------------------------------------------------
  Future<void> _bumpCountersOnCreate(
      {rtdb.DatabaseReference? parentReplyRef}) async {
    // bump parent.reply_count
    if (parentReplyRef != null) {
      await parentReplyRef.runTransaction((Object? current) {
        final Map<String, dynamic> data =
        current is Map ? Map<String, dynamic>.from(current as Map) : <String, dynamic>{};

        final int cur = (data['reply_count'] ?? 0) as int;
        data['reply_count'] = cur + 1;

        return rtdb.Transaction.success(data);
      });
    }


    // bump post.comment_count
    final postRef =
    _postsRef.child(widget.post['category']).child(widget.post['post_id']);
    await postRef.runTransaction((Object? current) {
      final Map<String, dynamic> data =
      current is Map ? Map<String, dynamic>.from(current as Map) : <String, dynamic>{};

      final int cur = (data['comment_count'] ?? 0) as int;
      data['comment_count'] = cur + 1;

      return rtdb.Transaction.success(data);
    });

  }

  // ------------------------------------------------------------
  // Widgets
  // ------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final rtdb.DatabaseReference rootRepliesRef = _postsRef
        .child(widget.post['category'])
        .child(widget.post['post_id'])
        .child('replies');

    return Scaffold(
      appBar: AppBar(title: Text(widget.post['title'] ?? 'Post Details')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Text("Posted by @${widget.post['username'] ?? 'Unknown'}",
                style:
                TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Text(widget.post['description'] ?? '',
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => _addOrEditReply(
                containerRef: rootRepliesRef,
                parentReplyRef: null,
                onFinish: () => setState(() {}),
              ),
              child: const Text('Add Reply'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text("Sort by: "),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _sortOption,
                  items: const [
                    DropdownMenuItem(value: 'Top', child: Text('Top')),
                    DropdownMenuItem(value: 'New', child: Text('New')),
                    DropdownMenuItem(value: 'Old', child: Text('Old')),
                  ],
                  onChanged: (val) async {
                    if (val == null) return;
                    setState(() => _sortOption = val);
                    await _loadReplies(reset: true);
                    _childSlices.clear();
                    _childLastTs.clear();
                    _collapsedStates.clear();
                  },
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => _loadReplies(reset: false),
                  child: const Text('Load more'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _topSlice.isEmpty
                  ? const Center(child: Text('No replies yet.'))
                  : ListView.builder(
                itemCount: _topSlice.length,
                itemBuilder: (ctx, i) {
                  final entry = _topSlice[i];
                  final replyId = entry.key;
                  final reply = entry.value;
                  final replyRef = rootRepliesRef.child(replyId);

                  return _buildReplyTile(
                    replyId: replyId,
                    reply: reply,
                    replyRef: replyRef,
                    depth: 0,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildReplyTile({
    required String replyId,
    required Map<String, dynamic> reply,
    required rtdb.DatabaseReference replyRef,
    required int depth,
  }) {
    final user = reply['user'] ?? 'Unknown';
    final ms = (reply['timestampMs'] ?? 0) as int;
    final dateString = ms > 0
        ? DateTime.fromMillisecondsSinceEpoch(ms).toIso8601String().split('T').first
        : (reply['timestamp']?.toString().split('T').first ?? 'Unknown');

    final commentText = (reply['comment'] ?? '') as String;
    final isCollapsed = _collapsedStates[replyId] ?? false;
    final cappedDepth = depth > maxIndent ? maxIndent : depth;
    final isOwner = _currentUser?.uid == (reply['uid'] as String?);

    final locked = reply['is_locked'] == true;
    final removed = reply['is_removed'] == true;

    // Children paging
    final childRef = replyRef.child('replies');
    final childList = _childSlices[replyId] ?? [];
    final replyScore = (reply['score'] ?? 0) as int;

    // ensure we know the current user's existing vote (non-blocking)
    _ensureMyVoteLoaded(replyId, replyRef);
    final my = _myVotes[replyId] ?? 0; // -1,0,+1

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: (maxIndent + 1) * indentWidth,
              child: CustomPaint(
                painter: ThreadLinesPainter(
                  depth: depth,
                  maxIndent: maxIndent,
                  indentWidth: indentWidth,
                ),
              ),
            ),
            SizedBox(width: indentWidth * cappedDepth),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // author/date + status chips
                  Row(
                    children: [
                      Text(
                        "$user • $dateString",
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                      if (locked) ...[
                        const SizedBox(width: 6),
                        const Chip(label: Text('locked'), visualDensity: VisualDensity.compact),
                      ],
                      if (removed) ...[
                        const SizedBox(width: 6),
                        const Chip(label: Text('deleted'), visualDensity: VisualDensity.compact),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),

                  // (optional) show “replying to …” context if present
                  if (reply['parent_user'] != null && reply['parent_excerpt'] != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        'Replying to @${reply['parent_user']}: “${reply['parent_excerpt']}”',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),

                  Text(
                    commentText +
                        (reply['edited'] == true && commentText != 'Deleted' ? ' (edited)' : ''),
                  ),
                  const SizedBox(height: 4),

                  // Actions row
                  Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // 👍 / 👎 with optimistic updates + active tint
                      _voteChip(
                        Icons.thumb_up,
                        '$replyScore',
                        my == 1,
                            () => _onVoteTap(
                          commentId: replyId,
                          replyRef: replyRef,
                          down: false,
                        ),
                      ),
                      _voteChip(
                        Icons.thumb_down,
                        '',
                        my == -1,
                            () => _onVoteTap(
                          commentId: replyId,
                          replyRef: replyRef,
                          down: true,
                        ),
                      ),

                      // ✅ unified replies control (expand / load more / collapse)
                      TextButton.icon(
                        icon: Icon(
                          isCollapsed ? Icons.chat_bubble_outline : Icons.expand_less,
                          size: 16,
                        ),
                        label: Text(_replyControlLabel(replyId, reply, isCollapsed)),
                        onPressed: () => _onReplyControlTap(
                          parentId: replyId,
                          childRef: childRef,
                          isCollapsed: isCollapsed,
                        ),
                      ),

                      // Author edit
                      if (isOwner)
                        _iconOnlyButton(Icons.edit, () {
                          final parentContainer = replyRef.parent;
                          if (parentContainer == null) return;
                          _addOrEditReply(
                            containerRef: parentContainer,
                            parentReplyRef: replyRef,
                            isEditing: true,
                            editingReplyKey: replyId,
                            existingComment: commentText,
                            onFinish: () => setState(() {}),
                          );
                        }),

                      // 🔐 Moderation controls (owner/mods or author via _canModerate)
                      if (_canModerate(reply['uid'] as String?))
                        TextButton(
                          onPressed: () => _modSetLock(
                            replyRef: replyRef,
                            commentId: replyId,
                            lock: !locked,
                          ),
                          child: Text(locked ? 'Unlock' : 'Lock'),
                        ),
                      if (_canModerate(reply['uid'] as String?))
                        TextButton(
                          onPressed: () => _modSetRemoved(
                            replyRef: replyRef,
                            commentId: replyId,
                            removed: !removed,
                          ),
                          child: Text(removed ? 'Restore' : 'Remove'),
                        ),

                      // Reply (hidden if locked/removed)
                      if (!locked && !removed)
                        InkWell(
                          onTap: () => _addOrEditReply(
                            containerRef: childRef,
                            parentReplyRef: replyRef,
                            onFinish: () => setState(() {}),
                          ),
                          child: const Text(
                            'Reply',
                            style: TextStyle(fontSize: 12, color: Colors.blue),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ]),

          // Children (only when expanded)
          if (!isCollapsed)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Column(
                children: [
                  if (childList.isNotEmpty)
                    Column(
                      children: List.generate(childList.length, (i) {
                        final child = childList[i];
                        final childId = child.key;
                        final childData = child.value;
                        final childNodeRef = childRef.child(childId);
                        return _buildReplyTile(
                          replyId: childId,
                          reply: childData,
                          replyRef: childNodeRef,
                          depth: depth + 1,
                        );
                      }),
                    ),
                  // (no standalone "Load more replies" button here; unified control handles it)
                ],
              ),
            ),
        ],
      ),
    );
  }



  Widget _actionButton(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey[700]),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 2),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ],
      ),
    );
  }

  Widget _iconOnlyButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Icon(icon, size: 14, color: Colors.grey[700]),
    );
  }
}

// ------------------------------------------------------------
// Painter (unchanged visual)
// ------------------------------------------------------------
class ThreadLinesPainter extends CustomPainter {
  final int depth;
  final int maxIndent;
  final double indentWidth;

  ThreadLinesPainter({
    required this.depth,
    required this.maxIndent,
    required this.indentWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.shade600
      ..strokeWidth = 1.0;

    final visibleDepth = depth > maxIndent ? maxIndent : depth;

    // vertical lines up to maxIndent
    for (int i = 0; i < visibleDepth; i++) {
      final x = indentWidth * i + indentWidth * 0.75;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // beyond maxIndent: dotted lines
    if (depth > maxIndent) {
      final baseX = indentWidth * (maxIndent - 1) + indentWidth * 0.75;
      final extraDepth = depth - maxIndent;
      for (int i = 0; i < extraDepth; i++) {
        final x = baseX + (i + 1) * 4;
        for (double y = 0; y < size.height; y += 4) {
          canvas.drawLine(Offset(x, y), Offset(x, y + 2), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

