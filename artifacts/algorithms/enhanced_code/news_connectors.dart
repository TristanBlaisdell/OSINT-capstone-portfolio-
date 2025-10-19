import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:webfeed/webfeed.dart';
import 'package:open_source/data/news_models.dart';

// ---------- Helpers ----------
DateTime _parseTime(dynamic v) {
  if (v == null) return DateTime.now();
  if (v is DateTime) return v;
  final s = v.toString();
  if (s.isEmpty) return DateTime.now();
  return DateTime.tryParse(s) ?? DateTime.now();
}

String _hostAsSource(String url) {
  try {
    final h = Uri.parse(url).host;
    if (h.startsWith('www.')) return h.substring(4);
    return h;
  } catch (_) {
    return 'Unknown';
  }
}

// Coerce Object? -> String
String _s(Object? v) => v is String ? v : (v?.toString() ?? '');

// ---------- 1) Generic RSS connector (FREE, no keys) ----------
class RssConnector implements FeedConnector {
  final List<Uri> feeds;
  final String? sourceLabelOverride; // optional: force a source label

  RssConnector({required this.feeds, this.sourceLabelOverride});

  @override
  Future<List<Article>> fetch() async {
    final out = <Article>[];
    for (final uri in feeds) {
      try {
        final res = await http.get(uri);
        if (res.statusCode != 200 || res.body.isEmpty) continue;

        // Try RSS first
        RssFeed? rss;
        try {
          rss = RssFeed.parse(res.body);
        } catch (_) {
          rss = null;
        }
        if (rss != null) {
          for (final item in rss.items ?? const <RssItem>[]) {
            // link/id
            String link = item.link ?? '';
            if (link.isEmpty) {
              final g = item.guid; // can be String or RssGuid depending on version
              if (g is String) {
                link = g;
              } else {
                try {
                  link = (g as dynamic)?.value as String? ?? '';
                } catch (_) {}
              }
            }
            if (link.isEmpty) continue;

            final summary = _s(item.description ?? item.content).trim();

            out.add(Article(
              id: link,
              title: item.title ?? '(no title)',
              summary: summary,
              url: link,
              source: sourceLabelOverride ?? (rss.title ?? _hostAsSource(link)),
              publishedAt: _parseTime(item.pubDate),
              entities: {},
            ));
          }
          continue; // parsed as RSS; skip Atom attempt
        }

        // Fallback to Atom
        AtomFeed? atom;
        try {
          atom = AtomFeed.parse(res.body);
        } catch (_) {
          atom = null;
        }
        if (atom != null) {
          for (final entry in atom.items ?? const <AtomItem>[]) {
            final link = (entry.links?.isNotEmpty ?? false)
                ? (entry.links!.first.href ?? '')
                : (entry.id ?? '');
            if (link.isEmpty) continue;

            final summary = _s(entry.summary ?? entry.content).trim();

            out.add(Article(
              id: link,
              title: entry.title ?? '(no title)',
              summary: summary,
              url: link,
              source: sourceLabelOverride ?? (atom.title ?? _hostAsSource(link)),
              publishedAt: _parseTime(entry.published ?? entry.updated),
              entities: {},
            ));
          }
        }
      } catch (_) {
        // swallow per-feed errors; add logging if you like
      }
    }
    return out;
  }
}

// ---------- 2) Guardian Content API (FREE key; generous) ----------
class GuardianConnector implements FeedConnector {
  final String apiKey;
  final List<String> sections; // e.g., ['world','us-news','business']

  GuardianConnector({required this.apiKey, this.sections = const ['world']});

  @override
  Future<List<Article>> fetch() async {
    final out = <Article>[];
    for (final section in sections) {
      final uri = Uri.https('content.guardianapis.com', '/search', {
        'api-key': apiKey,
        'section': section,
        'page-size': '50',
        'order-by': 'newest',
        'show-fields': 'trailText,bodyText,thumbnail',
      });
      try {
        final res = await http.get(uri);
        if (res.statusCode != 200) continue;
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final response = json['response'] as Map<String, dynamic>?;
        final results = (response?['results'] as List?) ?? const [];
        for (final r in results) {
          final m = r as Map<String, dynamic>;
          final fields = (m['fields'] as Map<String, dynamic>?) ?? {};

          final url = m['webUrl'] as String? ?? '';
          if (url.isEmpty) continue;

          final summary = _s(fields['trailText'] ?? fields['bodyText']).trim();

          out.add(Article(
            id: m['id'] as String? ?? url,
            title: (m['webTitle'] as String?) ?? '(no title)',
            summary: summary,
            url: url,
            source: 'The Guardian',
            publishedAt: _parseTime(m['webPublicationDate']),
            entities: {},
          ));
        }
      } catch (_) {/* ignore per-call errors */}
    }
    return out;
  }
}

// ---------- 3) NYT Top Stories API (FREE key; 5 req/min) ----------
class NytTopStoriesConnector implements FeedConnector {
  final String apiKey;
  final List<String> sections; // e.g., ['world','us','business','technology']

  NytTopStoriesConnector({required this.apiKey, this.sections = const ['world']});

  @override
  Future<List<Article>> fetch() async {
    final out = <Article>[];
    for (final section in sections) {
      final uri = Uri.https('api.nytimes.com', '/svc/topstories/v2/$section.json', {
        'api-key': apiKey,
      });
      try {
        final res = await http.get(uri);
        if (res.statusCode != 200) continue;
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final results = (json['results'] as List?) ?? const [];
        for (final r in results) {
          final m = r as Map<String, dynamic>;
          final url = (m['url'] as String?) ?? '';
          if (url.isEmpty) continue;

          final summary = _s(m['abstract']).trim();

          out.add(Article(
            id: url,
            title: (m['title'] as String?) ?? '(no title)',
            summary: summary,
            url: url,
            source: 'NYTimes',
            publishedAt: _parseTime(m['published_date']),
            entities: {
              if (m['section'] is String && (m['section'] as String).isNotEmpty)
                m['section'] as String
            },
          ));
        }
      } catch (_) {/* ignore per-call errors */}
    }
    return out;
  }
}

// ---------- Optional: simple “registry” that merges all ----------
class ConnectorRegistry {
  ConnectorRegistry(this.connectors);
  final List<FeedConnector> connectors;

  /// Fetch from all connectors and merge by article id (last write wins).
  Future<List<Article>> fetchAll() async {
    final map = <String, Article>{};
    for (final c in connectors) {
      final list = await c.fetch();
      for (final a in list) {
        map[a.id] = a;
      }
    }
    return map.values.toList();
  }
}

