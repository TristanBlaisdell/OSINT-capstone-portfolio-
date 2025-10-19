[← Back to Home](../../index.md)

# Enhancement 2 — Algorithms & Data Structures

**Artifact:** News Clustering & Ranking Pipeline  
**Focus:** Shingling → MinHash → LSH → Union-Find → Composite Scoring  
**Key Files:**  
- `lib/news_screen.dart` (controller + UI)  
- `lib/data/news_connectors.dart` (RSS/Guardian/NYT connectors)  
- `lib/data/news_models.dart` (Article model)

---

## 🎯 Overview and Purpose

The goal of this enhancement was to transform the app’s naive chronological news feed into an **intelligent, deduplicated, and ranked feed** using applied algorithms and data structures. The enhancement demonstrates the ability to design and evaluate efficient computing solutions that manage trade-offs between accuracy, speed, and scalability.

Specifically, this enhancement added:
- **Clustering** of near-duplicate articles using Locality Sensitive Hashing (LSH) on MinHash signatures of k-shingles.  
- **Ranking** based on a composite score (recency, credibility, engagement, novelty).  
- **Entity filtering** using an inverted index structure for topic-based exploration.  

These algorithmic improvements enable meaningful organization of open-source news data while preserving performance and accuracy.

---

## ⚙️ Pre-Enhancement Context

Before enhancement, the feed simply displayed all news items sorted by publish date.  
There was **no deduplication**, **no similarity detection**, and **no ranking beyond recency**.  
To document this stage, see the reconstructed notes in [Original State](original_state.md).

---

## 🧩 Algorithmic Pipeline

### 1️⃣ Text Normalization & Shingling
Input text is cleaned (lowercased, punctuation removed, stop words filtered) and split into **5-word shingles**.  
Each shingle is hashed using **FNV-1a (32-bit)** for compact set representation.

```dart
Set<int> shinglesFrom(String text, {int k = 5}) { ... } // → Set<int> shingles

2️⃣ MinHash Signature Generation

Each article’s shingle set is transformed into a 64-element MinHash signature using an affine hash family.
final _minHasher = MinHasher(m: 64);
a.signature = _minHasher.signature(a.shingles);

3️⃣ Locality-Sensitive Hashing (LSH)

The 64-element signature is divided into 8 bands of 8 rows each.
Items that share identical band hashes are treated as potential duplicates.
_lsh = LSH(bands: 8, rowsPerBand: 8);
_lsh.add(a.id, a.signature);
final cand = _lsh.query(a.signature);

4️⃣ Similarity Validation & Clustering

Candidate pairs are compared by estimated and true Jaccard similarity.
If both thresholds pass (est ≥ 0.75, true ≥ 0.80), articles are merged using a Union-Find structure.
if (est >= 0.75 && jaccard(a.shingles, b.shingles) >= 0.80) uf.union(a.id, b.id);
5️⃣ Representative Selection

Each cluster chooses one “canonical” article based on:

Source reliability weight

Recency decay factor
// 0.7 * sourceReliability + 0.3 * recencyDecay

6️⃣ Composite Cluster Score

Clusters are ranked by a composite score that combines:

Recency decay (exponential)

Wilson credibility (statistical lower bound)

Source reliability prior

Engagement level (clicks + reads)

Novelty factor (smaller clusters get slight preference)
score = 0.40*recency + 0.20*wilson + 0.20*source + 0.15*engagement + 0.05*novelty;

7️⃣ Entity Filtering

An inverted index maps entities (like “NATO”, “Ukraine”, “Elections”) to the article IDs where they appear.
Users can filter by one or more entities to view only clusters that match all selected topics.

🧠 Data Structures Used
Structure	Purpose
Set<int>	Stores hashed k-shingles for text similarity
List<int>	MinHash signature (length 64) for Jaccard estimation
Map<String, Set<String>>	Entity-to-article inverted index
UnionFind	Efficient clustering of similar articles
LSH	Locality Sensitive Hashing for approximate nearest-neighbor lookup
⏱️ Complexity & Performance
Stage	Structure	Typical Cost
Shingling	Set of hashes	O(T) per article, T = tokens
MinHash	64 affine hashes	O(64 ×
LSH add/query	bands=8, rows=8	O(8) per add/query
Pair confirm	Jaccard	O(
Clustering	Union-Find	near O(α(N))
Ranking	Composite arithmetic	O(#clusters)

Trade-offs:

Increasing m or tightening thresholds raises precision but increases runtime.

Banding (8×8) balances recall vs. precision for short-form news text.

⚙️ Parameters and Thresholds
Parameter	Value	Description
k	5	Shingle size
m	64	MinHash signature length
bands	8	LSH bands
rowsPerBand	8	LSH rows per band
est-Jaccard	≥ 0.75	MinHash similarity threshold
true-Jaccard	≥ 0.80	Confirmed similarity threshold

Composite Weighting:

Factor	Weight
Recency	0.40
Credibility	0.20
Source Reliability	0.20
Engagement	0.15
Novelty	0.05

Source Reliability Priors:

Source	Reliability
AP	0.92
Reuters	0.93
BBC	0.90
NYTimes	0.87
CNN	0.80
Fox	0.78
Unknown	0.60
🧪 Edge Cases & Safeguards

Empty or short articles default to a single shingle (still clusterable).

Invalid or missing timestamps default to DateTime.now() for safe scoring.

Entity filters automatically refresh when toggled on/off.

Feed gracefully handles failed connectors (skips rather than crashes).

🎓 Course Outcomes Alignment
Outcome	Application
Algorithmic Design	Implemented multi-stage clustering using MinHash + LSH + Union-Find
Data Structures	Efficient sets, maps, and disjoint sets to store and manage relationships
Performance Evaluation	Tuned parameters for optimal balance of recall and speed
Security Mindset	Weighted sources by credibility; neutral defaults prevent bias
Communication	Clear code modularization, consistent comments, structured scoring formula
📎 Artifacts

Enhanced Code:

lib/news_screen.dart

lib/data/news_connectors.dart

lib/data/news_models.dart

Reconstructed Original Notes: original_state.md

Narrative Report (PDF): artifact2_narrative.pdf (to be added)

🔗 Navigation

← Back to Home

Software Design & Engineering

Databases****


