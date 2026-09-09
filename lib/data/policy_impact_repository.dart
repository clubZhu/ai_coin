import '../domain/market_context.dart';

abstract interface class PolicyImpactRepository {
  Future<PolicyImpact> fetchImpact();
}

class EmptyPolicyImpactRepository implements PolicyImpactRepository {
  const EmptyPolicyImpactRepository();

  @override
  Future<PolicyImpact> fetchImpact() async => const PolicyImpact(
    directionScore: 0,
    eventRiskScore: 0,
    confidence: 0,
    relevantItemCount: 0,
    availableSourceCount: 0,
    expectedSourceCount: 2,
    headline: null,
    updatedAt: null,
    unavailableReason: '政策数据未启用',
  );
}
