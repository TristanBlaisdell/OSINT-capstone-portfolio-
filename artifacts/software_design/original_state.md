[← Back to Software Design & Engineering Enhancement](index.md)

# Reconstructed Original State — Software Design & Engineering

> **Note:** Earlier source files were not saved verbatim.  
> This reconstruction describes the pre-enhancement state based on milestone notes and the code review video.  
> It is included to provide context for the architectural and structural improvements made in the current version of the OSINT app.

---

## 🧩 Context (Pre-Enhancement)

Before enhancement, the OSINT app’s forum and messaging screens were fully functional but lacked modular structure and maintainable separation between UI, logic, and data layers. Key issues included:

- **UI and business logic were tightly coupled** within large widget trees.  
- **Limited code reuse:** repetitive layouts for posts, replies, and action buttons.  
- **State was managed locally**, causing inconsistent behavior between screens.  
- **Error handling and validation** were minimal or inconsistent.  
- **Moderation and security controls** were embedded directly in UI logic.  
- **No standardized architectural pattern** (e.g., Provider or MVC separation).

These patterns made future feature additions (e.g., role-based moderation, recursive replies, encrypted messaging) difficult to scale or test.

---

## 💻 Representative “Before” Pseudocode

### 1️⃣ Mixed presentation and logic
```dart
// BEFORE (representative)
Widget build(BuildContext context) {
  return ListView.builder(
    itemCount: posts.length,
    itemBuilder: (context, i) {
      final post = posts[i];
      return ListTile(
        title: Text(post['title']),
        subtitle: Text(post['description']),
        trailing: IconButton(
          icon: Icon(Icons.thumb_up),
          onPressed: () async {
            // business logic inline
            final ref = FirebaseDatabase.instance.ref('posts/${post['id']}');
            await ref.update({'upvotes': post['upvotes'] + 1});
          },
        ),
      );
    },
  );
}
Problem: Business logic (database writes, validation, and UI updates) was nested directly inside the UI tree.

Impact: Harder to test or modify; poor separation of concerns.

2️⃣ Duplicate UI components
dart
Copy code
// BEFORE: identical button logic repeated in multiple places
TextButton(
  onPressed: () => _deletePost(postId),
  child: const Text('Delete'),
);

TextButton(
  onPressed: () => _deleteComment(commentId),
  child: const Text('Delete'),
);
Each screen implemented its own deletion logic separately.

No shared components or utility methods.

3️⃣ Inconsistent state management
dart
Copy code
// BEFORE: used setState everywhere, no centralized provider
setState(() {
  posts.add(newPost);
});
Updates relied solely on setState() calls scattered across widgets.

This caused UI flickers and redundant rebuilds in larger views.

4️⃣ No defined moderation or role-based logic
dart
Copy code
// BEFORE: any user could trigger delete or lock
TextButton(
  onPressed: () => replyRef.update({'is_removed': true}),
  child: const Text('Remove'),
);
No role check for moderators or post owners.

No audit trail or Firestore logging of moderation events.

🧱 Observed Issues
Category	Before Enhancement	Consequence
Structure	UI + logic intermixed	Hard to extend or refactor
State Management	Localized via setState()	Redundant rebuilds, inconsistent updates
Security / Roles	Missing enforcement	Non-owners could edit/remove
Code Reuse	None (duplicate widgets)	Increased maintenance cost
UI Consistency	Inline styling everywhere	Inconsistent look and feel

🧠 Motivation for Enhancement
The goal of the enhancement was to modernize the app’s front-end architecture and improve maintainability by introducing:

Modular components (e.g., VoteChip, ReplyTile, ThreadLinesPainter)

Centralized data repositories for comment handling (CommentsRepositoryFirestore)

Cleaner separation between presentation and logic

Role-based moderation UI

Improved error handling and validation

Provider / state-driven updates for responsiveness

These improvements reduced redundancy, increased security, and aligned the app with Flutter’s best practices for scalability and maintainability.

🧾 Supporting Evidence
Code Review Video: https://screenrec.com/share/vRqr0QChBp

Milestone Notes: Module 3 – Enhancement 1 reflection (Software Design & Engineering)

Commit History: Demonstrates refactoring from UI-mixed logic to modular structure.

🧮 Summary of Change
Area	Original (Reconstructed)	Enhanced (Current)
Architecture	Monolithic widgets	Modular components & repository pattern
Logic Placement	Inside UI trees	Extracted into service / data layers
UI Components	Duplicated	Reusable and parameterized
Moderation Controls	None	Role-based access & audit logging
Error Handling	Minimal	Centralized and user-friendly
State Management	Local setState() only	Reactive updates via Provider & Firestore


