
# 🧪 Code Review — OSINT Mobile App
### Informal walkthrough of existing functionality, analysis, and planned enhancements

🎥 **Watch the code review:**  
[https://screenrec.com/share/vRqr0QChBp](https://screenrec.com/share/vRqr0QChBp)

> Tip: If you later upload the video to YouTube (Unlisted), add that link here too for redundancy.

---

## 🎛️ Existing Functionality (Pre-Enhancements)
This review starts by demonstrating the OSINT app’s core features **before** enhancements:

- **Authentication & Onboarding:** Firebase Auth sign-in, session persistence.
- **Home / Feeds:** Bias-labeled news tiles and regional filtering.
- **Forum:** Public discussions with nested replies (initial implementation).
- **Messaging:** Private E2EE messaging (MVP), contact lookup by username/phone.
- **Live Intel:** Embedded live sources (e.g., livestreams, incident map).
- **Navigation:** Tabbed/bottom navigation across Home, Globe, News, Messages, Account.

---

## 🔍 Code Analysis (Targets for Improvement)
The review highlights areas to improve across design, algorithms, databases, testing, and security:

- **Software Design & Engineering**
  - Refactor to **modular widgets** and clearer screen/view separation.
  - Introduce a **state management** pattern (e.g., Provider/ChangeNotifier).
  - Strengthen **UI/UX** consistency and input validation.

- **Algorithms & Data Structures**
  - Optimize **nested thread rendering** (depth limits, collapse/expand).
  - Add **sorting** for replies: *Top*, *New*, *Old*.
  - Improve **query efficiency** and pagination for large threads.

- **Databases**
  - Finalize **Firestore schema** for users, threads, replies, messages.
  - Enforce **RBAC** (roles/claims), validation, and least-privilege reads/writes.
  - Add indexes and query patterns to reduce reads and costs.

- **Security & Testing**
  - Confirm **HTTPS everywhere**, sanitize inputs, validate payloads.
  - Add **unit/widget tests** for forum sort & recursion edge cases.
  - Document **threat model** and mitigations (abuse, spam, exfiltration).

---

## 🧩 Planned Enhancements (What I Implemented)
These are the enhancements described in the review and completed in the capstone:

### 1) Software Design & Engineering
- Extracted reusable **UI components** (cards, list tiles, reply blocks).
- Centralized navigation and **state management** (Provider).
- Hardened form flows and **error handling**; improved accessibility and UX.

### 2) Algorithms & Data Structures
- Implemented **recursive threaded replies** with visual depth cues and a **max indentation** rule.
- Added reply **sorting** (*Top*, *New*, *Old*), plus load-more for long threads.
- Reduced query overhead via **structured paths** and targeted listeners.

### 3) Databases
- Designed a **secure Firestore schema** for posts, replies, users, messages.
- Applied **rules** for role-based access, ownership checks, and input constraints.
- Added **compound indexes** and paginated reads.

---

## 🎯 Course Outcome Alignment
- **Collaboration & Decision Support:** Clear in-code comments, review narration, and design trade-offs documented for stakeholders.
- **Professional Communication:** Structured walkthrough, visuals, and rationale tailored to mixed technical audiences.
- **Algorithmic Design:** Recursive structures, sort strategies, pagination, and performance trade-offs.
- **Techniques & Tools:** Flutter, Firebase, Provider, iterative testing, CI-ready structure.
- **Security Mindset:** RBAC, validation, encryption principles, least-privilege rules, and misuse case considerations.

---

## 📂 Related Links
- [Code Review Video](code_review/)
- [Software Design & Engineering Enhancement](artifacts/software_design/)
- [Algorithms & Data Structures Enhancement](artifacts/algorithms/)
- [Database Enhancement](artifacts/databases/)

---

## ✅ Reviewer Notes (What to Look For)
- How modularization improved readability and testability.
- How recursion, sorting, and pagination reduce UI lag and reads.
- How Firestore rules and schema changes enforce data integrity and privacy.

