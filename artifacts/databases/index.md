[← Back to Home](../../index.md)

# Enhancement 3 — Databases

**Artifact Focus:** Secure, scalable data layer spanning **Firebase Realtime Database**, **Cloud Firestore**, and **Firebase Storage**, with end‑to‑end encryption (AES‑GCM) and per‑recipient RSA key wrapping.  
**Key Files (already in repo):**
- `lib/data/comments_repository_firestore.dart` *(Firestore repository & moderation log)*
- `lib/models/comment.dart` *(comment document model)*
- `lib/screens/post_detail_screen.dart` *(hybrid RTDB+Firestore comment tree, voting, moderation)*
- `lib/screens/messaging_screen.dart` *(chat list & navigation, Firestore queries)*
- `lib/screens/Chat_screen.dart` *(E2E messaging: hybrid text/media, group‑ready key wrap)*
- `lib/security/encrypted_storage_manager.dart` *(AES‑GCM encryption, Storage upload/download, streaming for video)*

> Full source files should live in this section’s [`code/`](code/) folder for easy browsing from your ePortfolio.

---

## 🎯 Goals

- **Reliability & scale:** Split responsibilities across the right backends:
  - **Realtime Database (RTDB):** live, paginated threaded replies and vote counts.
  - **Cloud Firestore:** durable mirrors, audits, search‑able metadata, chat threads/messages.
  - **Firebase Storage:** binary media at scale (images/video) with **client‑side encryption**.
- **Security by design:** End‑to‑end encryption for private messages (AES‑GCM per message/file, RSA‑OAEP wrapping per participant), soft‑delete & lock controls for forum moderation, and least‑privilege access patterns.
- **Performance:** Keyset pagination, denormalized counters, streaming encryption/decryption for large video files, and optimistic UI on votes.

---

## 🗃️ Data Model Overview

### Realtime Database (forum threads)
```
forum_posts/{category}/{post_id} : {
  title, description, username, uid, comment_count,
  replies: {
    {reply_id}: {
      user, uid, comment, timestamp, timestampMs, score, upvotes, downvotes,
      reply_count, is_removed, is_locked,
      parent_user?, parent_excerpt?,
      replies: { ...nested... }
    }
  }
}
```
- **Why RTDB here?** Low‑latency tree reads + keyset pagination for nested replies.

### Firestore (mirrors, moderation, chat)
```
comments/{comment_id} : {
  thread_id, parent_id?, depth, sort_key, body,
  author_id, created_at, updated_at,
  score, reply_count, is_removed, is_locked,
  ancestors: [ ... ]
}

moderation_actions/{auto_id} : {
  actor_id, action, target_comment_id, thread_id, reason?, at
}

chats/{chat_id} : {
  type: "private"|"group",
  members: [uid...],
  groupName?,
  createdAt,
  lastMessage: { type, timestamp, ... }
}

chats/{chat_id}/messages/{message_id} : {
  type: "text"|"media",
  senderId,
  // TEXT:
  encryptedMessage?, aesKeyForRecipient?, aesKeyForSender?,  // legacy 1:1
  wrappedKeys?: { uid: base64_rsa_oaep(aes_key) },          // new group-ready
  // MEDIA:
  storagePath?, fileSize?, mimeType?,
  timestamp
}
```

### Firebase Storage (encrypted blobs)
```
/chats/{chat_id}/messages/{message_id}.bin  // nonce || ciphertext blocks || tag
```

---

## 🔐 Security & Privacy

- **Text messages:** Hybrid E2E. A fresh AES key encrypts plaintext; key is RSA‑OAEP wrapped for each participant. Decrypt on device using the user’s **unlocked** private key.
- **Media (images/videos):** AES‑GCM **client‑side** encryption before upload.  
  - Small media: encrypt in memory → `putData`.
  - Large video: **streaming** AES‑GCM to temp file → `putFile` (no huge buffers).
- **Moderation controls:** Authors/mods can **lock** or **soft‑delete** replies (flags mirrored to Firestore). **Audit trail** in `moderation_actions`.
- **Least‑privilege reads:** UI fetches only minimal metadata first (e.g., message list), then conditionally downloads & decrypts media bytes on demand.

---

## ⚙️ Key Repository & Service Logic

### `comments_repository_firestore.dart`
- **Upsert** comment docs (merge), compute **ancestors/depth** from parent.  
- **voteComment()** uses Firestore **transaction** to atomically update `score` and user vote.  
- **logModeration()** appends immutable audit entries.

### `post_detail_screen.dart`
- **Hybrid store:** RTDB → source of truth for threaded tree & counters; Firestore → mirror + audit.  
- **Pagination:** keyset via `orderByChild('timestampMs')` + `startAt` for both top‑level and children.  
- **Optimistic votes** + reconciliation with transactional RTDB updates; mirror to Firestore asynchronously.

### `Chat_screen.dart` + `encrypted_storage_manager.dart`
- **Text:** hybrid schema supports legacy 1:1 (`aesKeyForRecipient/aesKeyForSender`) and **new** `wrappedKeys{uid→wrappedKey}` for groups.  
- **Images:** download‑decrypt in memory for fast rendering.  
- **Video:** **downloadDecryptToFile()** streams to a temp clear file and hands off to the video player to avoid OOM.

---

## 🚀 Performance Techniques

- **Keyset pagination** on RTDB (`startAt(lastTs)` + `limitToFirst(n+1)`).
- **Denormalized counters** (`reply_count`, `comment_count`), updated via **transactions**.
- **Lazy hydration** of media: thumbnails/text first, fetch bytes only when visible or tapped.
- **Background Firestore mirrors** so UI remains responsive even during network churn.

---

## 🧪 Failure Handling & Edge Cases

- **Locked threads:** Reply button hidden; server flags prevent writes even if UI is stale.  
- **Missing keys:** If a `wrappedKeys[uid]` is absent, show a friendly error and block decryption.  
- **Key not unlocked:** Guard actions with a “Unlock your key” prompt.  
- **Oversized downloads:** Cap bytes for inline image decrypt (e.g., 25MB), require tap‑to‑open for video.

---

## 🧾 Example Flows

### Post a reply (top‑level or nested)
1. Author submits text → RTDB `push()` under appropriate `replies` node.  
2. **Transactions** increment `reply_count` (parent) and `comment_count` (post).  
3. **Mirror** to Firestore (ancestors/depth, sort_key) and **bumpCounters()`.  
4. UI refreshes current slice; optimistic state reconciles with server.

### Send a text message
1. Fetch recipient public keys (sender + recipient).  
2. Create **fresh AES key** → encrypt message.  
3. Wrap AES key for each participant → write message doc.  
4. Update `lastMessage` on chat root; receivers decrypt with their private key.

### Send a video
1. Stream‑encrypt file with AES‑GCM to temp file → upload to Storage.  
2. Store `storagePath`, `mimeType`, `fileSize`, and **wrappedKeys** in Firestore.  
3. Receiver taps bubble → stream‑download & decrypt to temp clear file → play.

---

## 🧮 Why These Trade‑offs?

- **RTDB vs Firestore:** RTDB excels at **deep, rapidly changing trees** (forum replies). Firestore excels at **auditable, queryable** documents (votes, moderation, chats).  
- **Client‑side crypto:** Ensures Storage holds **only ciphertext**; access to buckets alone does not reveal content.  
- **Streaming:** Prevents memory spikes on large media, keeping the app stable on mobile devices.

---

## 📎 Artifacts & Code

- Browse the full files in [`code/`](code/):  
  - [`comments_repository_firestore.dart`](code/comments_repository_firestore.dart)  
  - [`comment.dart`](code/comment.dart)  
  - [`post_detail_screen.dart`](code/post_detail_screen.dart)  
  - [`messaging_screen.dart`](code/messaging_screen.dart)  
  - [`Chat_screen.dart`](code/Chat_screen.dart)  
  - [`encrypted_storage_manager.dart`](code/encrypted_storage_manager.dart)

> Tip: keep classroom‑submitted PDFs (narrative) alongside this page, e.g. `artifact3_narrative.pdf`.

---

## 🎓 Course Outcomes Alignment

- **Collaborative environments:** Moderation audit trails; code comments and structure suitable for reviews.  
- **Professional communication:** Clear README, ePortfolio navigation, and on‑page data diagrams.  
- **Design & evaluation:** Hybrid RTDB/Firestore architecture with transactional updates and mirrors.  
- **Techniques & tools:** AES‑GCM, RSA‑OAEP, Firebase SDKs, streaming I/O, keyset pagination.  
- **Security mindset:** E2E encryption, locked threads, input validation, and least‑privilege access.

---

## 🔗 Navigation

- [← Back to Home](../../index.md)  
- [Software Design & Engineering](../software_design/index.md)  
- [Algorithms & Data Structures](../algorithms/index.md)

