import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app_system_ui.dart';
import 'core/app_theme.dart';
import 'data/cross_exchange_repository.dart';
import 'data/binance_asset_catalog.dart';
import 'data/coin_recommendation_repository.dart';
import 'data/live_price_service.dart';
import 'data/market_repository.dart';
import 'data/position_repository.dart';
import 'data/trading_asset_repository.dart';
import 'features/app_shell.dart';

class CryptoPilotApp extends StatelessWidget {
  const CryptoPilotApp({
    super.key,
    this.positionRepository,
    this.livePriceService,
    this.marketRepository,
    this.crossExchangeRepository,
    this.tradingAssetRepository,
    this.tradingAssetCatalog,
    this.coinRecommendationRepository,
  });

  final PositionRepository? positionRepository;
  final LivePriceService? livePriceService;
  final MarketRepository? marketRepository;
  final CrossExchangeRepository? crossExchangeRepository;
  final TradingAssetRepository? tradingAssetRepository;
  final TradingAssetCatalog? tradingAssetCatalog;
  final CoinRecommendationRepository? coinRecommendationRepository;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppSystemUi.overlayStyle,
      child: MaterialApp(
        title: 'CryptoPilot',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: AppShell(
          positionRepository: positionRepository,
          livePriceService: livePriceService,
          marketRepository: marketRepository,
          crossExchangeRepository: crossExchangeRepository,
          tradingAssetRepository: tradingAssetRepository,
          tradingAssetCatalog: tradingAssetCatalog,
          coinRecommendationRepository: coinRecommendationRepository,
        ),
      ),
    );
  }
}
