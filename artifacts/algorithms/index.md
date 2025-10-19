Enhancement #2 — Algorithms & Data Structures

Artifact: News Clustering & Ranking Pipeline (Shingling → MinHash → LSH → Union-Find → Composite Scoring)
Files:

lib/news_screen.dart (controller + UI)

lib/data/news_connectors.dart (RSS/Guardian/NYT connectors)

lib/data/news_models.dart (Article model)

🎯 Goal

Transform a naive, chronological news feed into an algorithmically deduplicated & ranked stream by:

Clustering near-duplicate articles from multiple sources using LSH over MinHash signatures of k-shingles.

Consolidating each cluster under a representative article chosen by source reliability and recency.

Ranking clusters with a composite score (recency decay, Wilson credibility, source reliability, engagement, novelty).

Allowing users to filter by entities (e.g., “NATO”, “Ukraine”, “Elections”) via an inverted index.

This enhancement demonstrates applied data structures, algorithmic tradeoffs, and performance-aware design.

🧭 Pipeline Overview
1️⃣ Normalization & Shingling

Normalize text (lowercase, strip punctuation, stopword removal, light stemming) → tokenize.

Build k-shingles (default k=5 contiguous tokens) and hash each shingle with FNV-1a 32-bit for speed.

Set<int> shinglesFrom(String text, {int k = 5}) { ... }    // → Set<int> shingles

2️⃣ MinHash Signatures

Generate m=64 hash functions (affine family) to produce a MinHash signature per article.

final _minHasher = MinHasher(m: 64);
a.signature = _minHasher.signature(a.shingles);

3️⃣ Locality-Sensitive Hashing (LSH)

Banding scheme: bands=8, rowsPerBand=8 → 8 x 8 = 64 signature length.

Items whose band-slices collide fall into the same candidate buckets.

_lsh = LSH(bands: 8, rowsPerBand: 8);
_lsh.add(a.id, a.signature);
final cand = _lsh.query(a.signature);

4️⃣ Similarity Check & Clustering

For each candidate pair, estimate Jaccard from signatures; confirm with true Jaccard on shingles.

Use Union-Find (disjoint set) to merge items above thresholds (e.g., est ≥ 0.75 then true ≥ 0.80).

if (est >= 0.75 && jaccard(a.shingles, b.shingles) >= 0.80) uf.union(a.id, b.id);

5️⃣ Representative Selection

Pick one article per cluster by combined source reliability + recency.

// 0.7 * sourceReliability + 0.3 * recencyDecay

6️⃣ Composite Cluster Score

Rank clusters using:

Recency decay (exponential)

Wilson score on up/down votes

Source reliability prior (per-source weights)

Engagement (clicks + reads, log-scaled)

Novelty (lighter reward for smaller clusters)

score = 0.40*recency + 0.20*wilson + 0.20*source + 0.15*engagement + 0.05*novelty;

7️⃣ Entity Filter (Inverted Index)

Build entity -> {articleIds} index during refresh.

Filter clusters to those containing all selected entities (set intersection).

🧪 Key Structures & Algorithms

Shingles: Set<int> of hashed k-grams (space-efficient dedup).

MinHash: List<int> signature (m=64) for Jaccard estimation.

LSH (banding): buckets signatures to find probable near-duplicates in sublinear time.

Union-Find: near-O(α(N)) merges to form clusters.

Inverted Index: Map<String, Set<String>> for entity filters.

Scoring: Exponential decay + Wilson lower bound + priors + log engagement.

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

Composite weights:

Recency .40

Credibility .20

Source .20

Engagement .15

Novelty .05

Source reliability priors (sample):

AP .92

Reuters .93

BBC .90

NYTimes .87

CNN .80

Fox .78

Unknown .60

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
