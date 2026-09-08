import '../domain/coin_recommendation.dart';

abstract interface class CoinRecommendationRepository {
  Future<List<CoinRecommendation>> fetchRecommendations({int limit = 6});
}
