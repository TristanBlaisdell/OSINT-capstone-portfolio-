// lib/data/news_models.dart

class Article {
  final String id;
  final String title;
  final String summary;
  final String url;
  final String source; // e.g., "AP", "Reuters"
  final DateTime publishedAt;
  final int upvotes;
  final int downvotes;
  final int clicks;
  final int reads;
  final Set<String> entities; // e.g., {"France","EU","NATO"}

  // computed (filled in later by the controller/pipeline)
  late final Set<int> shingles;
  late final List<int> signature;

  Article({
    required this.id,
    required this.title,
    required this.summary,
    required this.url,
    required this.source,
    required this.publishedAt,
    this.upvotes = 0,
    this.downvotes = 0,
    this.clicks = 0,
    this.reads = 0,
    Set<String>? entities,
  }) : entities = entities ?? {};
}

abstract class FeedConnector {
  Future<List<Article>> fetch();
}

