import '../domain/cross_exchange_analysis.dart';
import '../domain/market_snapshot.dart';

abstract interface class CrossExchangeRepository {
  Future<List<CrossExchangeAnalysis>> fetchAnalyses(
    List<MarketSnapshot> snapshots,
  );
}

class EmptyCrossExchangeRepository implements CrossExchangeRepository {
  const EmptyCrossExchangeRepository();

  @override
  Future<List<CrossExchangeAnalysis>> fetchAnalyses(
    List<MarketSnapshot> snapshots,
  ) async => const [];
}
