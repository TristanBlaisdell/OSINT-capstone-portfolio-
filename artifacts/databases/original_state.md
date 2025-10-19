[← Back to Databases](index.md)

# Reconstructed Original State — Databases

> Earlier “original” files weren’t preserved verbatim. This document summarizes the app’s **pre‑enhancement data layer** based on milestone notes and the code‑review video. It exists to contrast the current secure, hybrid database approach.

---

## 🧱 Before Enhancement (Summary)

- **Single‑store bias:** Logic tended to treat the backend as a flat feed store. Replies, votes, and moderation state were coupled to UI without dedicated auditability.  
- **No client‑side media encryption:** Files (when present) were uploaded in the clear; large uploads/downloads risked memory spikes.  
- **Limited messaging schema:** Text messages lacked a group‑ready wrapped‑key strategy; media handling was minimal or absent.  
- **No streaming:** Large files were handled in memory, risking OOM on mobile devices.

---

## 🧩 Original Data Handling (Simplified)

- **Forum:** Chronological lists and nested maps without transactional counters or lock/soft‑delete flags.  
- **Messaging:** Basic Firestore chat docs, text only, no per‑recipient key wrapping, no media.  
- **Storage:** Either unused or used without encryption.

```text
[UI] → fetch list → render → (optional) write item
(no background mirrors, minimal pagination, no audit logs)
```

---

## 🧮 Gaps Addressed by the Enhancement

| Area | Original | Enhanced |
|------|----------|----------|
| Forum storage | Single store, flat usage | **RTDB** for live tree, **Firestore** mirror + audits |
| Counters | Ad‑hoc updates | **Transactions** for `reply_count` / `comment_count` |
| Moderation | Minimal | **Lock/soft‑delete** flags + **moderation_actions** log |
| Messaging | Text only, no E2E | **AES‑GCM + RSA‑OAEP**, wrappedKeys map (group‑ready) |
| Media | Not encrypted | **Client‑side encryption**; **streaming** upload/download |
| Performance | Full list reloads | **Keyset pagination**, optimistic updates |
| Reliability | Best‑effort writes | Dual‑writes w/ reconciliation (UI stays responsive) |

---

## 🧾 Evidence Sources

- Capstone code‑review video and milestone notes.  
- Commits and diffs in this repository reflecting the addition of `encrypted_storage_manager.dart`, key wrapping, and moderation logging.

---

## 🧭 Summary

The original database usage was functional but minimal.  
The enhanced design introduces a **hybrid Firebase architecture** with **transactional integrity**, **client‑side encryption**, and **scalable media handling**, aligning the project with professional expectations for security, performance, and auditability.

