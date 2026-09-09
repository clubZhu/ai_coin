import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/ui.dart';
import '../../data/binance_asset_catalog.dart';
import '../../data/coin_recommendation_repository.dart';
import '../../domain/coin_recommendation.dart';

class AssetManagerPage extends StatefulWidget {
  const AssetManagerPage({
    super.key,
    required this.symbols,
    required this.catalog,
    required this.recommendationRepository,
  });

  final List<String> symbols;
  final TradingAssetCatalog catalog;
  final CoinRecommendationRepository recommendationRepository;

  @override
  State<AssetManagerPage> createState() => _AssetManagerPageState();
}

class _AssetManagerPageState extends State<AssetManagerPage> {
  final _searchController = TextEditingController();
  late final List<String> _symbols = List<String>.of(widget.symbols);

  List<String> _catalogSymbols = const [];
  bool _loadingCatalog = true;
  Object? _catalogError;
  List<CoinRecommendation> _recommendations = const [];
  bool _loadingRecommendations = true;
  Object? _recommendationError;
  String _query = '';

  List<String> get _searchResults {
    final query = _query.trim().toUpperCase();
    if (query.isEmpty) return const [];
    return _catalogSymbols
        .where((symbol) => symbol.contains(query))
        .take(60)
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _loadCatalog();
    _loadRecommendations();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _loadingCatalog = true;
      _catalogError = null;
    });
    try {
      final symbols = await widget.catalog.fetchSymbols();
      if (!mounted) return;
      setState(() {
        _catalogSymbols = symbols;
        _loadingCatalog = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _catalogError = error;
        _loadingCatalog = false;
      });
    }
  }

  Future<void> _loadRecommendations() async {
    setState(() {
      _loadingRecommendations = true;
      _recommendationError = null;
    });
    try {
      final recommendations = await widget.recommendationRepository
          .fetchRecommendations();
      if (!mounted) return;
      setState(() {
        _recommendations = recommendations;
        _loadingRecommendations = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _recommendationError = error;
        _loadingRecommendations = false;
      });
    }
  }

  void _finish() => Navigator.of(context).pop(List<String>.of(_symbols));

  void _add(String symbol) {
    if (_symbols.contains(symbol)) return;
    setState(() {
      _symbols.add(symbol);
      _query = '';
      _searchController.clear();
    });
  }

  void _remove(String symbol) {
    if (_symbols.length == 1) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('至少保留一个币种')));
      return;
    }
    setState(() => _symbols.remove(symbol));
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final symbol = _symbols.removeAt(oldIndex);
      _symbols.insert(newIndex, symbol);
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _finish();
        return false;
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          toolbarHeight: 56,
          leading: IconButton(
            onPressed: _finish,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
          ),
          titleSpacing: 0,
          title: const Text(
            '币种管理',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          actions: [
            TextButton(
              onPressed: _finish,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.teal,
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('完成'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              20 + MediaQuery.paddingOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 48,
                  child: TextField(
                    key: const ValueKey('asset-search'),
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      hintText: '搜索 Binance 币种',
                      hintStyle: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: AppColors.muted,
                      ),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                              icon: const Icon(Icons.close_rounded, size: 18),
                            ),
                      filled: true,
                      fillColor: AppColors.surface,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(13),
                        borderSide: const BorderSide(color: AppColors.line),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(13),
                        borderSide: const BorderSide(color: AppColors.teal),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_query.isEmpty) ...[
                  Row(
                    children: [
                      const Text(
                        '优选币种',
                        style: TextStyle(
                          color: AppColors.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '实时筛选 · 非买入指令',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 10,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '刷新优选币种',
                        visualDensity: VisualDensity.compact,
                        onPressed: _loadingRecommendations
                            ? null
                            : _loadRecommendations,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildRecommendationStrip(),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text(
                        '已添加',
                        style: TextStyle(
                          color: AppColors.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_symbols.length} 个 · 长按拖动排序',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ] else
                  const Text(
                    '搜索结果',
                    style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: _query.isEmpty
                      ? _buildSelectedList()
                      : _buildSearchResults(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecommendationStrip() {
    if (_loadingRecommendations) {
      return const _RecommendationState(loading: true, message: '正在筛选高流动性币种');
    }
    if (_recommendationError != null) {
      return _RecommendationState(
        message: '优选行情加载失败',
        actionLabel: '重试',
        onAction: _loadRecommendations,
      );
    }
    if (_recommendations.isEmpty) {
      return const _RecommendationState(message: '当前没有达到优选标准的币种');
    }
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _recommendations.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final recommendation = _recommendations[index];
          return _RecommendationCard(
            recommendation: recommendation,
            selected: _symbols.contains(recommendation.symbol),
            onAdd: () => _add(recommendation.symbol),
          );
        },
      ),
    );
  }

  Widget _buildSelectedList() {
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      padding: EdgeInsets.zero,
      itemCount: _symbols.length,
      onReorder: _reorder,
      proxyDecorator: (child, index, animation) => Material(
        color: Colors.transparent,
        elevation: 3,
        borderRadius: BorderRadius.circular(16),
        child: child,
      ),
      itemBuilder: (context, index) {
        final symbol = _symbols[index];
        return _AssetRow(
          key: ValueKey('selected-$symbol'),
          symbol: symbol,
          leading: ReorderableDelayedDragStartListener(
            index: index,
            child: const Icon(
              Icons.drag_indicator_rounded,
              size: 20,
              color: AppColors.muted,
            ),
          ),
          trailing: IconButton(
            tooltip: '删除 $symbol',
            onPressed: () => _remove(symbol),
            icon: const Icon(
              Icons.remove_circle_outline_rounded,
              size: 20,
              color: AppColors.muted,
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchResults() {
    if (_loadingCatalog) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_catalogError != null) {
      return _CatalogMessage(
        icon: Icons.cloud_off_rounded,
        title: '币种列表加载失败',
        actionLabel: '重试',
        onAction: _loadCatalog,
      );
    }
    final results = _searchResults;
    if (results.isEmpty) {
      return const _CatalogMessage(
        icon: Icons.search_off_rounded,
        title: '没有找到对应的 USDT 现货币种',
      );
    }
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: results.length,
      itemBuilder: (context, index) {
        final symbol = results[index];
        final selected = _symbols.contains(symbol);
        return _AssetRow(
          key: ValueKey('result-$symbol'),
          symbol: symbol,
          leading: _AssetGlyph(symbol: symbol),
          trailing: IconButton(
            tooltip: selected ? '已添加' : '添加 $symbol',
            onPressed: selected ? null : () => _add(symbol),
            icon: Icon(
              selected ? Icons.check_rounded : Icons.add_circle_outline_rounded,
              size: 21,
              color: selected ? AppColors.teal : AppColors.muted,
            ),
          ),
        );
      },
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({
    required this.recommendation,
    required this.selected,
    required this.onAdd,
  });

  final CoinRecommendation recommendation;
  final bool selected;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final positive = recommendation.changePercent >= 0;
    return Container(
      width: 218,
      padding: const EdgeInsets.fromLTRB(13, 12, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF0F1F4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0523314A),
            blurRadius: 18,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                recommendation.symbol,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Text(
                ' / USDT',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.tealSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${recommendation.levelLabel} ${recommendation.score}',
                  style: const TextStyle(
                    color: AppColors.teal,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: Text(
                  '\$${formatPrice(recommendation.price, decimals: recommendation.pricePrecision)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -.2,
                  ),
                ),
              ),
              Text(
                '${positive ? '+' : ''}${recommendation.changePercent.toStringAsFixed(2)}%',
                style: TextStyle(
                  color: positive ? AppColors.teal : AppColors.red,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            recommendation.reasons.join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 10,
              fontWeight: FontWeight.w400,
            ),
          ),
          const Spacer(),
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              height: 30,
              child: TextButton.icon(
                onPressed: selected ? null : onAdd,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.teal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                icon: Icon(
                  selected ? Icons.check_rounded : Icons.add_rounded,
                  size: 15,
                ),
                label: Text(selected ? '已添加' : '加入自选'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendationState extends StatelessWidget {
  const _RecommendationState({
    required this.message,
    this.loading = false,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final bool loading;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 86,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF0F1F4)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (loading) ...[
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          if (onAction != null) ...[
            const SizedBox(width: 6),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class _AssetRow extends StatelessWidget {
  const _AssetRow({
    super.key,
    required this.symbol,
    required this.leading,
    required this.trailing,
  });

  final String symbol;
  final Widget leading;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.only(left: 14, right: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF0F1F4)),
      ),
      child: Row(
        children: [
          SizedBox(width: 28, child: Center(child: leading)),
          const SizedBox(width: 10),
          Text(
            symbol,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Text(
            ' / USDT',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w400,
            ),
          ),
          const Spacer(),
          trailing,
        ],
      ),
    );
  }
}

class _AssetGlyph extends StatelessWidget {
  const _AssetGlyph({required this.symbol});

  final String symbol;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.tealSoft,
        shape: BoxShape.circle,
      ),
      child: Text(
        symbol.substring(0, 1),
        style: const TextStyle(
          color: AppColors.teal,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CatalogMessage extends StatelessWidget {
  const _CatalogMessage({
    required this.icon,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34, color: AppColors.muted),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
          if (onAction != null) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
