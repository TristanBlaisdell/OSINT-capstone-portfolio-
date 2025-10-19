# Enhancement #2 — Algorithms & Data Structures
**Artifact:** News Clustering & Ranking Pipeline (Shingling → MinHash → LSH → Union-Find → Composite Scoring)  
**Files:**  
- `lib/news_screen.dart` *(controller + UI)*  
- `lib/data/news_connectors.dart` *(RSS/Guardian/NYT connectors)*  
- `lib/data/news_models.dart` *(Article model)*

---

## 🎯 Goal
Transform a naive, chronological news feed into an **algorithmically deduplicated & ranked** stream by:
- Clustering near-duplicate articles from multiple sources using **LSH** over **MinHash signatures** of **k-shingles**.
- Consolidating each cluster under a **representative article** chosen by source reliability and recency.
- Ranking clusters with a **composite score** (recency decay, Wilson credibility, source reliability, engagement, novelty).
- Allowing users to **filter by entities** (e.g., “NATO”, “Ukraine”, “Elections”) via an inverted index.

This enhancement demonstrates applied data-structures, algorithmic tradeoffs, and performance-aware design.

---

## 🧭 Pipeline Overview

**1) Normalization & Shingling**  
- Normalize text (lowercase, strip punctuation, stopword removal, light stemming) → tokenize.  
- Build **k-shingles** (default `k=5` contiguous tokens) and hash each shingle with **FNV-1a 32-bit** for speed.  
```dart
Set<int> shinglesFrom(String text, {int k = 5}) { ... }    // → Set<int> shingles
2) MinHash Signatures

Generate m=64 hash functions (affine family) to produce a MinHash signature per article.

dart
Copy code
final _minHasher = MinHasher(m: 64);
a.signature = _minHasher.signature(a.shingles);
3) Locality-Sensitive Hashing (LSH)

Banding scheme: bands=8, rowsPerBand=8 → 8 x 8 = 64 signature length.

Items whose band-slices collide fall into the same candidate buckets.

dart
Copy code
_lsh = LSH(bands: 8, rowsPerBand: 8);
_lsh.add(a.id, a.signature);
final cand = _lsh.query(a.signature);
4) Similarity Check & Clustering

For each candidate pair, estimate Jaccard from signatures; confirm with true Jaccard on shingles.

Use Union-Find (disjoint set) to merge items above thresholds (e.g., est ≥ 0.75 then true ≥ 0.80).

dart
Copy code
if (est >= 0.75 && jaccard(a.shingles, b.shingles) >= 0.80) uf.union(a.id, b.id);
5) Representative Selection

Pick one article per cluster by combined source reliability + recency.

dart
Copy code
// 0.7 * sourceReliability + 0.3 * recencyDecay
6) Composite Cluster Score

Rank clusters using:

Recency decay (exponential)

Wilson score on up/down votes

Source reliability prior (per-source weights)

Engagement (clicks + reads, log-scaled)

Novelty (lighter reward for smaller clusters)

dart
Copy code
score = 0.40*recency + 0.20*wilson + 0.20*source + 0.15*engagement + 0.05*novelty;
7) Entity Filter (Inverted Index)

Build entity -> {articleIds} index during refresh.

Filter clusters to those containing all selected entities (set intersection).

🧪 Key Structures & Algorithms
Shingles: Set<int> of hashed k-grams (space-efficient dedup).

MinHash: List<int> signature (m=64) for Jaccard estimation.

LSH (banding): buckets signatures to find probable near-duplicates in sublinear time.

Union-Find: near-O(α(N)) merges to form clusters.

Inverted Index: Map<String, Set<String>> for entity filters.

Scoring: Exponential decay + Wilson lower bound + priors + log engagement.

🧰 Representative Code (Already in repo)
dart
Copy code
// Add to LSH buckets
void add(String articleId, List<int> signature) {
  for (int b = 0; b < bands; b++) {
    final start = b * rowsPerBand;
    final end = start + rowsPerBand;
    final slice = signature.sublist(start, end).join(',');
    final key = _hashBand(slice);
    _buckets.putIfAbsent(key, () => <String>{}).add(articleId);
  }
}
dart
Copy code
// Wilson lower bound
double wilson(int up, int down, {double z = 1.96}) { ... }
dart
Copy code
// Recency decay (hours)
double recencyDecay(DateTime t, {double lambdaPerHour = 0.05}) {
  final hours = DateTime.now().difference(t).inMinutes / 60.0;
  return exp(-lambdaPerHour * max(0.0, hours));
}
⏱️ Complexity & Performance
Stage	Structure	Typical Cost
Shingling	Set of hashes	O(T) per article, T = tokens
MinHash	64 affine hashes	O(64 ·
LSH add/query	bands=8, rows=8	O(8) per add; O(8 + collisions) per query
Pair confirm	Jaccard on sets	O(
Clustering	Union-Find	near O(α(N)) merges
Ranking	Simple arithmetic	O(#clusters)

Trade-offs:

Increasing m or tightening thresholds raises precision but costs more CPU.

Banding (8x8) balances recall/precision for short news text; tweakable.

🧷 Parameters & Thresholds (tunable)
k (shingles) = 5

m (signature length) = 64

bands = 8, rowsPerBand = 8

LSH candidate confirmation: est-Jaccard ≥ 0.75, true Jaccard ≥ 0.80

Composite weights: wRecency=.40, wCred=.20, wSource=.20, wEng=.15, wNovel=.05

Source reliability priors (sample): AP .92, Reuters .93, BBC .90, NYTimes .87, CNN .80, Fox .78 (fallback Unknown .60)

🧪 Edge Cases & Safeguards
Empty/short texts fall back to a single shingle → still clusterable.

Invalid timestamps default to DateTime.now() (safe recency).

Entity filter uses set intersection; clearing filters restores full ranked list.

If connectors fail, pipeline degrades gracefully (skips errors).

🎓 Course Outcomes Mapping
Algorithmic principles: MinHash/LSH pipeline, set ops, Union-Find, Wilson score.

Design trade-offs: Precision/recall via banding; k-shingles vs. char-grams; performance vs. quality.

Techniques & tools: Multi-source ingestion (RSS/Guardian/NYT), robust parsing, normalized ranking.

Security mindset: Trusted-source priors, neutral defaults (Wilson 0.5), resilience to malformed inputs.

Communication: Clear code structure and comments, parameterized design, UI that explains cluster size/score.

📎 Artifacts
Enhanced Code:

lib/news_screen.dart

lib/data/news_connectors.dart

lib/data/news_models.dart

Reconstructed Original Notes: original_state.md

Narrative (PDF): artifact2_narrative.pdf (to be added)

🔗 Navigation
Back to Home / Self-Assessment

Software Design & Engineering

Databases

yaml
Copy code

---

## 2) `artifacts/algorithms/original_state.md`

```markdown
[← Back to Algorithms & Data Structures Enhancement](index.md)

# Reconstructed Original State — Algorithms & Data Structures

> **Note:** Earlier “original” files were not preserved.  
> This document reconstructs the pre-enhancement algorithmic behavior based on milestone notes and the code review video. It exists to contrast with the current clustering/ranking pipeline.

---

## 🧩 Context (Before Enhancement)
The news feed initially aggregated items from one or more sources and displayed them **chronologically** without de-duplication or clustering:

- No text normalization, shingling, or similarity search.  
- No candidate generation (LSH) or MinHash signatures.  
- No cluster representative or composite scoring.  
- No entity-based inverted index for filtering.  
- Articles from different outlets covering the same story appeared as **duplicates**.

---

## 💻 Representative “Before” Pseudocode

### 1️⃣ Naive fetch + chronological render
```dart
Future<List<Article>> fetchFeed() async {
  final list = <Article>[];
  for (final connector in connectors) {
    list.addAll(await connector.fetch());
  }
  // simple last-write-wins merge by id (optional)
  return list..sort((a,b) => b.publishedAt.compareTo(a.publishedAt));
}

Widget build(context) {
  return ListView(
    children: feed.map((a) => ListTile(
      title: Text(a.title),
      subtitle: Text(a.source),
    )).toList(),
  );
}
2️⃣ No similarity / clustering
dart
Copy code
// BEFORE: each article stands alone; duplicates from AP/Reuters/CNN are not grouped.
3️⃣ No ranking beyond time
dart
Copy code
// BEFORE: purely by publishedAt; no recency decay, no Wilson, no source prior.
🧱 Observed Limitations
Area	Original (Reconstructed)	Impact
Deduplication	None	Duplicate headlines clutter feed
Similarity	None	No grouping of near-duplicates
Ranking	Chronological only	Fresh but not necessarily credible/engaging
Entities	None	Users cannot focus on topics easily
Scalability	O(N) render	Acceptable at small N, poor UX for large N

🧠 Why Enhance
User value: consolidated story clusters instead of repetitive headlines.

Quality: factor in credibility, engagement, and novelty—not just time.

Performance: use LSH/MinHash to keep near-duplicate detection efficient.

Exploration: entity-based filtering to quickly focus on topics.

🧾 Evidence Sources
Code Review Video: (see ePortfolio Code Review page)

Milestone notes from the Algorithms enhancement planning phase.
