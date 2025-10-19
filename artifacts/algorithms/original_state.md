[← Back to Algorithms & Data Structures](index.md)

# Reconstructed Original State — Algorithms & Data Structures

Because earlier “original” source files were not saved verbatim, this document reconstructs the project’s pre-enhancement state using milestone notes and the code review video as reference material.  
The video evidence and notes reflect the state of the application **before** implementing advanced algorithmic clustering and ranking logic.

---

## 🧱 Pre-Enhancement Architecture Overview

Before enhancement, the **News Screen** feature of the OSINT application was a **flat chronological feed**.  
It simply pulled articles from multiple sources (AP, Reuters, BBC, etc.) and displayed them sorted by publish date.  

### Characteristics of the original design:
- **No clustering:** Duplicate or near-duplicate stories appeared multiple times in the feed.  
- **No similarity detection:** The system had no concept of article overlap or text similarity.  
- **No algorithmic ranking:** Articles were ordered only by timestamp, without considering credibility or engagement.  
- **No entity filtering:** Users could not filter by topics, locations, or people mentioned in articles.  
- **Basic connectors only:** The connectors (RSS, Guardian, NYT) pulled and parsed feeds but did not perform post-processing.

---

## 🧩 Original Data Flow (Simplified)

```text
FeedConnector.fetch()  →  returns List<Article>
      ↓
NewsController.refresh()  
      ↓
display ListView of articles (sorted by date)
```

Each article object included only:
```dart
class Article {
  final String id;
  final String title;
  final String summary;
  final String url;
  final String source;
  final DateTime publishedAt;
}
```

There were no algorithmic structures (e.g., sets, maps, or clustering).  
The logic primarily involved iterating over the article list, assigning UI widgets, and refreshing content from RSS feeds.

---

## ⚙️ Example Pre-Enhancement Behavior

| Function | Description | Pre-Enhancement Implementation |
|-----------|--------------|--------------------------------|
| **Sorting** | Chronological sort | `articles.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));` |
| **Duplicate Handling** | None | Duplicates displayed freely |
| **Scoring** | None | Articles displayed by timestamp only |
| **Filtering** | None | No entity or topic filters |
| **Connectors** | Static fetch | RSS/JSON parsing without analytics |

---

## 🧮 Limitations of Original Logic

1. **No Deduplication**  
   - Stories from multiple outlets about the same event appeared several times.  
   - This cluttered the feed and diluted user attention.

2. **No Semantic Grouping**  
   - The app treated text as plain strings, not meaning-bearing data.  
   - There was no notion of “similar content” or topic overlap.

3. **No Ranking Algorithm**  
   - The feed lacked logic for scoring credibility, engagement, or novelty.  
   - Highly reputable or trending content did not surface first.

4. **Performance Issues**  
   - While simple, the approach scaled poorly as the number of feeds grew.  
   - The app re-rendered entire lists without efficient re-indexing or caching.

5. **User Experience Constraints**  
   - Without filters or relevance logic, the app behaved like a plain RSS reader rather than an analytical OSINT tool.

---

## 🧠 Missing Algorithmic Components (Added Later)

| Component | Status (Pre-Enhancement) | Description |
|------------|--------------------------|--------------|
| **Shingling** | ❌ Absent | No tokenization or text hashing |
| **MinHash** | ❌ Absent | No compact similarity representation |
| **Locality Sensitive Hashing (LSH)** | ❌ Absent | No near-duplicate grouping |
| **Union-Find** | ❌ Absent | No cluster merging logic |
| **Composite Scoring** | ❌ Absent | No weighted metrics for ranking |
| **Entity Indexing** | ❌ Absent | No inverted index for topic filtering |

---

## 🧾 Supporting Evidence

- **Code Review Video:** [https://screenrec.com/share/vRqr0QChBp](https://screenrec.com/share/vRqr0QChBp)  
- **Milestone Notes:** References from early capstone drafts confirming that article sorting and retrieval were purely chronological.  
- **Design Reflections:** Initial architecture lacked algorithmic differentiation or clustering features.

---

## 🧩 Summary

In its pre-enhancement state, the OSINT application’s news system functioned as a basic feed aggregator.  
There were no advanced data structures or algorithmic pipelines beyond list sorting.  
The later enhancements introduced measurable algorithmic sophistication, transforming the project from a linear data display into an intelligent, ranked, and clustered information engine.

