// lib/news_screen.dart
import 'dart:math';
import 'package:flutter/material.dart';

// Shared models + connectors
import 'package:open_source/data/news_models.dart';
import 'package:open_source/data/news_connectors.dart';

/// ---------------------------------------------------------------------------
/// CLUSTER MODEL
/// ---------------------------------------------------------------------------

class Cluster {
  final String id;
  final Set<String> members; // articleIds
  final String representativeId;
  final double score; // composite ranking score
  final DateTime newestTime;

  Cluster({
    required this.id,
    required this.members,
    required this.representativeId,
    required this.score,
    required this.newestTime,
  });
}

/// Reliable prior per source (0..1). Tweak as you like / load from config.
const Map<String, double> kSourceReliability = {
  "AP": 0.92,
  "Reuters": 0.93,
  "BBC": 0.90,
  "WSJ": 0.88,
  "NYTimes": 0.87,
  "The Guardian": 0.86,
  "Guardian": 0.86,
  "Al Jazeera": 0.82,
  "AlJazeera": 0.82,
  "Fox": 0.78,
  "CNN": 0.80,
  "Unknown": 0.60,
};

double sourceReliability(String s) => kSourceReliability[s] ?? kSourceReliability["Unknown"]!;

/// ---------------------------------------------------------------------------
/// TEXT NORMALIZATION + SHINGLING
/// ---------------------------------------------------------------------------

final RegExp _punct = RegExp(r"[^\w\s]");
final Set<String> _stop = {
  "the","a","an","of","and","or","to","in","on","for","with","by","at","from",
  "as","that","this","is","are","be","was","were","it","its","into","over",
  "after","before","about","not","no","but","if","then","than","so","such",
};

String normalize(String s) {
  final lower = s.toLowerCase();
  final stripped = lower.replaceAll(_punct, " ");
  final words = stripped.split(RegExp(r"\s+")).where((w) => w.isNotEmpty);
  // ultra-light stemming: strip common plural 's'
  final stemmed = words.map((w) => w.endsWith('s') && w.length > 3 ? w.substring(0, w.length - 1) : w);
  final filtered = stemmed.where((w) => !_stop.contains(w));
  return filtered.join(' ');
}

List<String> kGrams(List<String> tokens, {int k = 5}) {
  if (tokens.length < k) return [tokens.join(' ')];
  final grams = <String>[];
  for (var i = 0; i <= tokens.length - k; i++) {
    grams.add(tokens.sublist(i, i + k).join(' '));
  }
  return grams;
}

Set<int> shinglesFrom(String text, {int k = 5}) {
  final norm = normalize(text);
  final tokens = norm.split(' ').where((w) => w.isNotEmpty).toList();
  final grams = kGrams(tokens, k: k);
  return grams.map((g) => _fnv1a32(g)).toSet();
}

/// 32-bit FNV-1a for speed + determinism
int _fnv1a32(String s) {
  const int fnvOffset = 0x811C9DC5;
  const int fnvPrime = 0x01000193;
  int hash = fnvOffset;
  for (int i = 0; i < s.length; i++) {
    hash ^= s.codeUnitAt(i);
    hash = (hash * fnvPrime) & 0xFFFFFFFF;
  }
  return hash;
}

/// ---------------------------------------------------------------------------
/// MINHASH + LSH
/// ---------------------------------------------------------------------------

class MinHasher {
  final int m; // number of hash functions
  final int prime = 4294967291; // largest 32-bit prime
  final List<int> a;
  final List<int> b;

  MinHasher({this.m = 64})
      : a = List<int>.generate(64, (i) => 2 * i + 1)..length = m,
        b = List<int>.generate(64, (i) => 3 * i + 7)..length = m;

  List<int> signature(Set<int> shingles) {
    final sig = List<int>.filled(m, 0x7FFFFFFF);
    for (final x in shingles) {
      for (int i = 0; i < m; i++) {
        final h = ((a[i] * x + b[i]) % prime) & 0x7FFFFFFF;
        if (h < sig[i]) sig[i] = h;
      }
    }
    return sig;
  }

  static double estJaccardFromSignatures(List<int> s1, List<int> s2) {
    int eq = 0;
    for (int i = 0; i < min(s1.length, s2.length); i++) {
      if (s1[i] == s2[i]) eq++;
    }
    return eq / s1.length;
  }
}

class LSH {
  final int bands;
  final int rowsPerBand;
  final Map<String, Set<String>> _buckets = {}; // bandKey -> articleIds

  LSH({required this.bands, required this.rowsPerBand});

  void add(String articleId, List<int> signature) {
    for (int b = 0; b < bands; b++) {
      final start = b * rowsPerBand;
      final end = start + rowsPerBand;
      final slice = signature.sublist(start, end).join(',');
      final key = _hashBand(slice);
      _buckets.putIfAbsent(key, () => <String>{}).add(articleId);
    }
  }

  Set<String> query(List<int> signature) {
    final results = <String>{};
    for (int b = 0; b < bands; b++) {
      final start = b * rowsPerBand;
      final end = start + rowsPerBand;
      final slice = signature.sublist(start, end).join(',');
      final key = _hashBand(slice);
      final bucket = _buckets[key];
      if (bucket != null) results.addAll(bucket);
    }
    return results;
  }

  String _hashBand(String s) => (_fnv1a32(s) & 0x7FFFFFFF).toString();
}

/// True Jaccard on shingles (for final confirmation)
double jaccard(Set<int> a, Set<int> b) {
  if (a.isEmpty && b.isEmpty) return 1.0;
  final inter = a.intersection(b).length;
  final uni = a.union(b).length;
  return inter / uni;
}

/// ---------------------------------------------------------------------------
/// UNION-FIND
/// ---------------------------------------------------------------------------

class UnionFind {
  final Map<String, String> parent = {};
  final Map<String, int> rank = {};

  UnionFind(Iterable<String> ids) {
    for (final id in ids) {
      parent[id] = id;
      rank[id] = 0;
    }
  }

  String find(String x) {
    if (parent[x] != x) {
      parent[x] = find(parent[x]!);
    }
    return parent[x]!;
  }

  void union(String x, String y) {
    final rx = find(x), ry = find(y);
    if (rx == ry) return;
    if (rank[rx]! < rank[ry]!) {
      parent[rx] = ry;
    } else if (rank[rx]! > rank[ry]!) {
      parent[ry] = rx;
    } else {
      parent[ry] = rx;
      rank[rx] = rank[rx]! + 1;
    }
  }
}

/// ---------------------------------------------------------------------------
/// SCORING: Recency, Wilson credibility, Engagement, Novelty
/// ---------------------------------------------------------------------------

double recencyDecay(DateTime t, {double lambdaPerHour = 0.05}) {
  final hours = DateTime.now().difference(t).inMinutes / 60.0;
  return exp(-lambdaPerHour * max(0.0, hours));
}

/// Wilson score lower bound (z=1.96 ~ 95%)
double wilson(int up, int down, {double z = 1.96}) {
  final n = up + down;
  if (n == 0) return 0.5; // neutral
  final p = up / n;
  final z2 = z * z;
  final denom = 1 + z2 / n;
  final centre = p + z2 / (2 * n);
  final margin = z * sqrt((p * (1 - p) + z2 / (4 * n)) / n);
  return (centre - margin) / denom;
}

/// Normalize engagement roughly (log scale)
double engagementScore(int clicks, int reads, {int cap = 1000}) {
  final v = min(cap, clicks + reads);
  return log(1 + v) / log(1 + cap);
}

/// Novelty: reward smaller clusters slightly
double novelty(int clusterSize) {
  return 1.0 / log(2 + clusterSize); // 1, ~0.63, ~0.5, ...
}

/// Composite weights (tweak to taste)
const double wRecency = 0.40;
const double wCred    = 0.20;
const double wSource  = 0.20;
const double wEng     = 0.15;
const double wNovel   = 0.05;

/// ---------------------------------------------------------------------------
/// MULTI-CONNECTOR ADAPTER
/// ---------------------------------------------------------------------------

class MultiConnector implements FeedConnector {
  final Future<List<Article>> Function() fetchAll;
  MultiConnector(this.fetchAll);
  @override
  Future<List<Article>> fetch() => fetchAll();
}

/// ---------------------------------------------------------------------------
/// NEWS CONTROLLER
/// ---------------------------------------------------------------------------

class NewsController extends ChangeNotifier {
  final FeedConnector feedConnector;
  final MinHasher _minHasher = MinHasher(m: 64);
  late LSH _lsh;
  final Map<String, Article> _articles = {};
  final Map<String, Set<String>> _entityIndex = {};
  final Map<String, List<int>> _sigs = {};
  final Map<String, Set<int>> _shingles = {};
  List<Cluster> _ranked = [];
  Set<String> _activeEntityFilter = {};

  NewsController({required this.feedConnector}) {
    _lsh = LSH(bands: 8, rowsPerBand: 8);
  }

  List<Cluster> get clusters => _ranked;
  Set<String> get activeFilter => _activeEntityFilter;

  List<String> get topEntities {
    final counts = <String, int>{};
    for (final e in _entityIndex.entries) {
      counts[e.key] = e.value.length;
    }
    final sorted = counts.keys.toList()
      ..sort((a, b) => (counts[b]!).compareTo(counts[a]!));
    return sorted.take(12).toList();
  }

  Future<void> refresh() async {
    _articles.clear();
    _entityIndex.clear();
    _sigs.clear();
    _shingles.clear();
    _lsh = LSH(bands: 8, rowsPerBand: 8);

    final fetched = await feedConnector.fetch();
    for (final a in fetched) {
      _articles[a.id] = a;
    }

    // normalize → shingles → signatures → LSH
    for (final a in _articles.values) {
      a.shingles = shinglesFrom("${a.title} ${a.summary}", k: 5);
      a.signature = _minHasher.signature(a.shingles);
      _shingles[a.id] = a.shingles;
      _sigs[a.id] = a.signature;
      _lsh.add(a.id, a.signature);
      // entities index
      for (final ent in a.entities) {
        _entityIndex.putIfAbsent(ent, () => <String>{}).add(a.id);
      }
    }

    // clustering
    final uf = UnionFind(_articles.keys);
    for (final a in _articles.values) {
      final cand = _lsh.query(a.signature)..remove(a.id);
      for (final id in cand) {
        final b = _articles[id]!;
        final est = MinHasher.estJaccardFromSignatures(a.signature, b.signature);
        if (est >= 0.75) {
          final jac = jaccard(a.shingles, b.shingles);
          if (jac >= 0.80) {
            uf.union(a.id, b.id);
          }
        }
      }
    }

    // groups
    final groups = <String, Set<String>>{};
    for (final id in _articles.keys) {
      final root = uf.find(id);
      groups.putIfAbsent(root, () => <String>{}).add(id);
    }

    // representative + score
    final clist = <Cluster>[];
    for (final g in groups.values) {
      final repId = _pickRepresentative(g);
      final score = _clusterScore(repId, g);
      final newest = g
          .map((id) => _articles[id]!.publishedAt)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      clist.add(Cluster(
        id: repId,
        members: g,
        representativeId: repId,
        score: score,
        newestTime: newest,
      ));
    }

    // entity filter if active
    List<Cluster> filtered = clist;
    if (_activeEntityFilter.isNotEmpty) {
      final allowedArticles = _intersectEntities(_activeEntityFilter);
      filtered = clist.where(
            (c) => c.members.any((m) => allowedArticles.contains(m)),
      ).toList();
    }

    filtered.sort((a, b) => b.score.compareTo(a.score));
    _ranked = filtered;
    notifyListeners();
  }

  void setEntityFilter(Set<String> entities) {
    _activeEntityFilter = entities;
    // quick re-filter + sort based on cached clusters
    final clist = List<Cluster>.from(_ranked);
    List<Cluster> all = clist;
    if (_activeEntityFilter.isNotEmpty) {
      final allowedArticles = _intersectEntities(_activeEntityFilter);
      all = clist.where((c) => c.members.any((m) => allowedArticles.contains(m))).toList();
    }
    all.sort((a, b) => b.score.compareTo(a.score));
    _ranked = all;
    notifyListeners();
  }

  Set<String> _intersectEntities(Set<String> ents) {
    Set<String>? acc;
    for (final e in ents) {
      final s = _entityIndex[e] ?? <String>{};
      acc = acc == null ? Set<String>.from(s) : acc!.intersection(s);
    }
    return acc ?? <String>{};
  }

  String _pickRepresentative(Set<String> g) {
    // highest (source reliability, then freshest)
    String best = g.first;
    double bestScore = -1;
    for (final id in g) {
      final a = _articles[id]!;
      final sRel = sourceReliability(a.source);
      final fresh = recencyDecay(a.publishedAt);
      final cand = 0.7 * sRel + 0.3 * fresh;
      if (cand > bestScore) {
        bestScore = cand;
        best = id;
      }
    }
    return best;
  }

  double _clusterScore(String repId, Set<String> members) {
    final rep = _articles[repId]!;
    final d = recencyDecay(rep.publishedAt);
    final w = wilson(rep.upvotes, rep.downvotes);
    final r = sourceReliability(rep.source);
    final e = engagementScore(rep.clicks, rep.reads);
    final n = novelty(members.length);
    return wRecency * d + wCred * w + wSource * r + wEng * e + wNovel * n;
  }
}

/// ---------------------------------------------------------------------------
/// UI
/// ---------------------------------------------------------------------------

class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  late final NewsController controller;
  final Set<String> selectedEntities = {};

  @override
  void initState() {
    super.initState();

    // Optional keys via --dart-define
    const guardianKey = String.fromEnvironment('GUARDIAN_API_KEY', defaultValue: '');
    const nytKey = String.fromEnvironment('NYT_API_KEY', defaultValue: '');

    // Free, live RSS (no keys required)
    final rss = RssConnector(feeds: [
      Uri.parse('https://apnews.com/index.rss'),
      Uri.parse('https://feeds.bbci.co.uk/news/world/rss.xml'),
      Uri.parse('https://rss.cnn.com/rss/edition_world.rss'),
      Uri.parse('https://www.aljazeera.com/xml/rss/all.xml'),
    ]);

    final connectors = <FeedConnector>[
      rss,
      if (guardianKey.isNotEmpty)
        GuardianConnector(apiKey: guardianKey, sections: const ['world','us-news','business','technology']),
      if (nytKey.isNotEmpty)
        NytTopStoriesConnector(apiKey: nytKey, sections: const ['world','us','business','technology']),
    ];

    final registry = ConnectorRegistry(connectors);

    controller = NewsController(
      feedConnector: MultiConnector(registry.fetchAll),
    );

    controller.addListener(_onUpdate);
    controller.refresh();
  }

  @override
  void dispose() {
    controller.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final isEmpty = controller.clusters.isEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('News'),
        actions: [
          IconButton(
            tooltip: "Refresh",
            onPressed: () => controller.refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          _EntityFilterBar(
            allEntities: controller.topEntities,
            selected: selectedEntities,
            onToggle: (e) {
              setState(() {
                if (selectedEntities.contains(e)) {
                  selectedEntities.remove(e);
                } else {
                  selectedEntities.add(e);
                }
              });
              controller.setEntityFilter(selectedEntities);
            },
            onClear: () {
              setState(() => selectedEntities.clear());
              controller.setEntityFilter(selectedEntities);
            },
          ),
          Expanded(
            child: isEmpty
                ? const _EmptyState()
                : ListView.builder(
              itemCount: controller.clusters.length,
              itemBuilder: (ctx, i) {
                final c = controller.clusters[i];
                // access representative + members from controller internals
                final rep = controller._articles[c.representativeId]!;
                return _ClusterCard(
                  cluster: c,
                  rep: rep,
                  all: c.members.map((id) => controller._articles[id]!).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          "No stories yet. Tap refresh.",
          style: TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}

class _EntityFilterBar extends StatelessWidget {
  final List<String> allEntities;
  final Set<String> selected;
  final void Function(String) onToggle;
  final VoidCallback onClear;

  const _EntityFilterBar({
    required this.allEntities,
    required this.selected,
    required this.onToggle,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ...allEntities.map((e) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(e),
              selected: selected.contains(e),
              onSelected: (_) => onToggle(e),
            ),
          )),
          if (selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: TextButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.clear),
                label: const Text("Clear"),
                style: TextButton.styleFrom(
                  foregroundColor: scheme.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ClusterCard extends StatefulWidget {
  final Cluster cluster;
  final Article rep;
  final List<Article> all;

  const _ClusterCard({
    required this.cluster,
    required this.rep,
    required this.all,
  });

  @override
  State<_ClusterCard> createState() => _ClusterCardState();
}

class _ClusterCardState extends State<_ClusterCard> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final rep = widget.rep;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => expanded = !expanded),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RowSpace(
                left: Text(
                  rep.title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                right: _ScorePill(score: widget.cluster.score),
              ),
              const SizedBox(height: 6),
              Text(
                rep.summary.isNotEmpty ? rep.summary : rep.url,
                maxLines: expanded ? 8 : 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: -6,
                children: [
                  _Tag(rep.source),
                  _Tag(_timeAgo(rep.publishedAt)),
                  _Tag("${widget.cluster.members.length} source${widget.cluster.members.length > 1 ? 's' : ''}"),
                ],
              ),
              if (expanded) ...[
                const Divider(height: 18),
                ...widget.all
                    .where((a) => a.id != rep.id)
                    .map((a) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.link, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "${a.source}: ${a.title}",
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                )),
              ],
              if (expanded) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () async {
                      // open the representative URL in a browser
                      final url = rep.url;
                      // You can integrate url_launcher; omitted to keep deps minimal.
                      // ScaffoldMessenger.of(context).showSnackBar(
                      //   const SnackBar(content: Text('Open link not implemented')),
                      // );
                    },
                    icon: const Icon(Icons.open_in_new),
                    label: const Text("Open"),
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.primary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RowSpace extends StatelessWidget {
  final Widget left;
  final Widget right;
  const _RowSpace({required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: left),
      const SizedBox(width: 12),
      right,
    ]);
  }
}

class _ScorePill extends StatelessWidget {
  final double score;
  const _ScorePill({required this.score});

  @override
  Widget build(BuildContext context) {
    final s = (score * 100).clamp(0, 100).toStringAsFixed(0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.3)),
      ),
      child: Text("Score $s"),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  const _Tag(this.text);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Fallback color to avoid depending on Material 3's surfaceContainerHighest
    final bg = scheme.surfaceVariant.withOpacity(0.5);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }
}

String _timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return "just now";
  if (d.inMinutes < 60) return "${d.inMinutes}m ago";
  if (d.inHours < 24) return "${d.inHours}h ago";
  return "${d.inDays}d ago";
}

