# Enhancement #1 — Software Design & Engineering
**Artifact:** OSINT Mobile App (Flutter + Firebase)  
**Focus:** Modular architecture, state management boundaries, secure UX flows, and robust forum UI

---

## 🎯 Purpose of This Enhancement
I refactored the forum detail and messaging areas to improve **separation of concerns**, **testability**, and **user experience**, while maintaining a secure, auditable design:
- Clear divide between **UI rendering** and **business logic**
- **Optimistic UI** patterns with **dual-write** to Firestore for analytics/audit data
- **Role-based controls** (Owner/Moderator/User) surfaced safely in UI
- **Stable pagination/sorting** that works uniformly for top-level and child replies

---

## 🧩 Reconstructed Original State
*Because earlier “original” source files were not saved verbatim, this section documents the pre-enhancement state using milestone notes and my code review video.*  
See **[Original State Notes](original_state.md)**.

**Key pain points (before):**
- UI widgets mixed with network and mutation logic
- Limited reuse of components (reply tiles, action rows)
- No unified pattern for **Top/New/Old** sorting across depths
- Moderation affordances not centralized; no auditable action log

---

## ✅ Enhanced Implementation (Current)
This version implements a consistent design that’s easier to extend and reason about.

### Representative files (enhanced)
- `post_detail_screen.dart` — thread screen UI + unified pagination/sorting, optimistic votes  
- `messaging_screen.dart` — forum index + category selector + navigation to post detail  
- `models/comment.dart` — comment data model (Firestore mirror)  
- `data/comments_repository_firestore.dart` — repository for Firestore upserts, votes, audits

> In this design, **Realtime Database (RTDB)** remains the source of truth for live forum UX, while **Firestore** mirrors key data for analytics/audits/moderation reports.

**Placeholders in the repo**

