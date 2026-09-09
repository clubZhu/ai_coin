import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../domain/market_context.dart';
import 'policy_impact_repository.dart';

typedef PolicyTextFetcher = Future<String> Function(Uri url);

class PublicPolicyImpactRepository implements PolicyImpactRepository {
  PublicPolicyImpactRepository({PolicyTextFetcher? fetcher})
    : _fetcher = fetcher ?? _httpFetcher;

  static final Uri _fedMonetaryFeed = Uri.parse(
    'https://www.federalreserve.gov/feeds/press_monetary.xml',
  );
  static final Uri _secPressFeed = Uri.parse(
    'https://www.sec.gov/news/pressreleases.rss',
  );

  static const _cryptoTerms = [
    'crypto',
    'digital asset',
    'bitcoin',
    'ether',
    'blockchain',
    'stablecoin',
    'token',
    'exchange-traded fund',
    'spot etf',
  ];
  static const _supportiveTerms = [
    'approve',
    'approval',
    'clarif',
    'innovation',
    'rescind',
    'dismiss',
    'easing',
    'lower',
    'rate cut',
    'liquidity support',
  ];
  static const _restrictiveTerms = [
    'charge',
    'enforcement',
    'fraud',
    'violation',
    'ban',
    'restrict',
    'tighten',
    'rate increase',
    'raise',
    'sanction',
    'warning',
    'suspend',
  ];

  final PolicyTextFetcher _fetcher;

  static Future<String> _httpFetcher(Uri url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client
          .getUrl(url)
          .timeout(const Duration(seconds: 8));
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'CryptoPilot/1.0 public-policy-feed-reader',
      );
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/rss+xml,text/xml',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('政策源返回 ${response.statusCode}', uri: url);
      }
      return response.transform(utf8.decoder).join();
    } finally {
      client.close();
    }
  }

  @override
  Future<PolicyImpact> fetchImpact() async {
    final results = await Future.wait([
      _safeFeed(_fedMonetaryFeed, source: '美联储', macroRelevant: true),
      _safeFeed(_secPressFeed, source: 'SEC', macroRelevant: false),
    ]);
    final available = results.where((result) => result.available).length;
    if (available == 0) {
      return const PolicyImpact(
        directionScore: 0,
        eventRiskScore: 0,
        confidence: 0,
        relevantItemCount: 0,
        availableSourceCount: 0,
        expectedSourceCount: 2,
        headline: null,
        updatedAt: null,
        unavailableReason: '权威政策源暂时不可用',
      );
    }

    final now = DateTime.now().toUtc();
    final entries = results.expand((result) => result.entries).where((entry) {
      final age = now.difference(entry.publishedAt);
      return !age.isNegative && age <= const Duration(days: 7);
    }).toList();
    var weightedDirection = 0.0;
    var totalWeight = 0.0;
    var eventRisk = 0.0;
    _PolicyEntry? lead;
    var leadImpact = -1.0;

    for (final entry in entries) {
      final text = '${entry.title} ${entry.description}'.toLowerCase();
      final cryptoRelevant = _containsAny(text, _cryptoTerms);
      if (!entry.macroRelevant && !cryptoRelevant) continue;
      final age = now.difference(entry.publishedAt);
      final recency = age <= const Duration(hours: 24)
          ? 1.0
          : age <= const Duration(days: 3)
          ? .7
          : .35;
      final relevance = cryptoRelevant ? 1.0 : .65;
      final supportive = _matchCount(text, _supportiveTerms);
      final restrictive = _matchCount(text, _restrictiveTerms);
      final rawDirection = (supportive - restrictive).clamp(-3, 3);
      final weight = recency * relevance;
      weightedDirection += rawDirection * weight;
      totalWeight += math.max(weight, .1);
      final impact =
          weight *
          (rawDirection == 0
              ? (entry.macroRelevant ? 34 : 22)
              : 55 + 12 * rawDirection.abs());
      eventRisk = math.max(eventRisk, impact);
      if (impact > leadImpact) {
        leadImpact = impact;
        lead = entry;
      }
    }

    final relevantCount = entries.where((entry) {
      final text = '${entry.title} ${entry.description}'.toLowerCase();
      return entry.macroRelevant || _containsAny(text, _cryptoTerms);
    }).length;
    final directionScore = totalWeight == 0
        ? 0
        : (weightedDirection / totalWeight * 42)
              .round()
              .clamp(-100, 100)
              .toInt();
    final confidence = (available * 32 + math.min(relevantCount, 3) * 10)
        .clamp(0, 94)
        .toInt();

    return PolicyImpact(
      directionScore: directionScore,
      eventRiskScore: eventRisk.round().clamp(0, 100).toInt(),
      confidence: confidence,
      relevantItemCount: relevantCount,
      availableSourceCount: available,
      expectedSourceCount: 2,
      headline: lead == null ? null : '${lead.source} · ${lead.title}',
      updatedAt: lead?.publishedAt,
      unavailableReason: available < 2 ? '部分政策源暂时不可用' : null,
    );
  }

  Future<_FeedResult> _safeFeed(
    Uri uri, {
    required String source,
    required bool macroRelevant,
  }) async {
    try {
      final xml = await _fetcher(uri);
      return _FeedResult(
        available: true,
        entries: _parseFeed(xml, source: source, macroRelevant: macroRelevant),
      );
    } on Object {
      return const _FeedResult(available: false, entries: []);
    }
  }

  List<_PolicyEntry> _parseFeed(
    String xml, {
    required String source,
    required bool macroRelevant,
  }) {
    final items = RegExp(
      r'<item\b[\s\S]*?</item>',
      caseSensitive: false,
    ).allMatches(xml);
    final entries = <_PolicyEntry>[];
    for (final itemMatch in items) {
      final item = itemMatch.group(0)!;
      final title = _tagValue(item, 'title');
      final description = _tagValue(item, 'description');
      final dateText = _tagValue(item, 'pubDate').isNotEmpty
          ? _tagValue(item, 'pubDate')
          : _tagValue(item, 'dc:date');
      final publishedAt = _parseDate(dateText);
      if (title.isEmpty || publishedAt == null) continue;
      entries.add(
        _PolicyEntry(
          source: source,
          title: title,
          description: description,
          publishedAt: publishedAt,
          macroRelevant: macroRelevant,
        ),
      );
    }
    return entries;
  }

  String _tagValue(String xml, String tag) {
    final match = RegExp(
      '<${RegExp.escape(tag)}\\b[^>]*>([\\s\\S]*?)</${RegExp.escape(tag)}>',
      caseSensitive: false,
    ).firstMatch(xml);
    if (match == null) return '';
    return _decodeXml(
      match
          .group(1)!
          .replaceAll(RegExp(r'<!\[CDATA\['), '')
          .replaceAll(']]>', '')
          .replaceAll(RegExp(r'<[^>]+>'), ' '),
    ).replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _decodeXml(String value) {
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
  }

  DateTime? _parseDate(String value) {
    if (value.isEmpty) return null;
    try {
      return HttpDate.parse(value).toUtc();
    } on FormatException {
      final direct = DateTime.tryParse(value)?.toUtc();
      if (direct != null) return direct;
      final match = RegExp(
        r'^(?:[A-Za-z]{3},\s*)?(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})\s+([A-Za-z]{2,4}|[+-]\d{4})$',
      ).firstMatch(value.trim());
      if (match == null) return null;
      const months = {
        'Jan': 1,
        'Feb': 2,
        'Mar': 3,
        'Apr': 4,
        'May': 5,
        'Jun': 6,
        'Jul': 7,
        'Aug': 8,
        'Sep': 9,
        'Oct': 10,
        'Nov': 11,
        'Dec': 12,
      };
      final month = months[match.group(2)];
      if (month == null) return null;
      final timezone = match.group(7)!;
      final offsetMinutes = switch (timezone) {
        'GMT' || 'UTC' => 0,
        'EST' => -5 * 60,
        'EDT' => -4 * 60,
        'CST' => -6 * 60,
        'CDT' => -5 * 60,
        'MST' => -7 * 60,
        'MDT' => -6 * 60,
        'PST' => -8 * 60,
        'PDT' => -7 * 60,
        _ => _numericOffsetMinutes(timezone),
      };
      if (offsetMinutes == null) return null;
      final localAsUtc = DateTime.utc(
        int.parse(match.group(3)!),
        month,
        int.parse(match.group(1)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
        int.parse(match.group(6)!),
      );
      return localAsUtc.subtract(Duration(minutes: offsetMinutes));
    }
  }

  int? _numericOffsetMinutes(String value) {
    final match = RegExp(r'^([+-])(\d{2})(\d{2})$').firstMatch(value);
    if (match == null) return null;
    final minutes =
        int.parse(match.group(2)!) * 60 + int.parse(match.group(3)!);
    return match.group(1) == '-' ? -minutes : minutes;
  }

  static bool _containsAny(String text, List<String> terms) =>
      terms.any(text.contains);

  static int _matchCount(String text, List<String> terms) =>
      terms.where(text.contains).length;
}

class _FeedResult {
  const _FeedResult({required this.available, required this.entries});

  final bool available;
  final List<_PolicyEntry> entries;
}

class _PolicyEntry {
  const _PolicyEntry({
    required this.source,
    required this.title,
    required this.description,
    required this.publishedAt,
    required this.macroRelevant,
  });

  final String source;
  final String title;
  final String description;
  final DateTime publishedAt;
  final bool macroRelevant;
}
