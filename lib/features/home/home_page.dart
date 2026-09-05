import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../../core/ui.dart';
import '../../data/live_price_service.dart';
import '../../data/position_repository.dart';
import '../../domain/market_snapshot.dart';
import '../../domain/position_record.dart';
import '../records/records_page.dart';

class _ThousandsSeparatorInputFormatter extends TextInputFormatter {
  const _ThousandsSeparatorInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text.replaceAll(',', '');
    if (raw.isEmpty) return newValue;
    if (!RegExp(r'^\d*\.?\d*$').hasMatch(raw)) return oldValue;

    final parts = raw.split('.');
    final integer = parts.first.isEmpty ? '0' : parts.first;
    final grouped = integer.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    final formatted = parts.length == 2 ? '$grouped.${parts.last}' : grouped;
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.snapshots,
    required this.positionRepository,
    required this.livePriceService,
  });

  final List<MarketSnapshot> snapshots;
  final PositionRepository positionRepository;
  final LivePriceService livePriceService;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _priceController = TextEditingController();
  final _amountController = TextEditingController(text: '100');
  final List<PositionRecord> _records = [];

  StreamSubscription<double>? _livePriceSubscription;
  int _priceStreamGeneration = 0;
  int _selectedAsset = 0;
  PositionSide _side = PositionSide.long;
  double _stopLossPercent = 2;
  double _takeProfitPercent = 10;
  int _leverage = 5;
  bool _loadingRecords = true;
  bool _hasLivePrice = false;
  bool _followMarketPrice = true;
  double? _livePrice;

  int get _openCount =>
      _records.where((record) => record.result == PositionResult.open).length;

  MarketSnapshot get _snapshot => widget.snapshots[_selectedAsset];
  double? get _entryPrice =>
      double.tryParse(_priceController.text.replaceAll(',', '').trim());
  double? get _amount =>
      double.tryParse(_amountController.text.replaceAll(',', '').trim());
  bool get _canSubmit => (_entryPrice ?? 0) > 0 && (_amount ?? 0) > 0;
  double get _positionValue => _amount ?? 0;
  double get _estimatedLoss => _positionValue * _stopLossPercent / 100;
  double get _estimatedProfit => _positionValue * _takeProfitPercent / 100;

  double? get _stopLossPrice {
    final price = _entryPrice;
    if (price == null) return null;
    return _side == PositionSide.long
        ? price * (1 - _stopLossPercent / 100)
        : price * (1 + _stopLossPercent / 100);
  }

  double? get _takeProfitPrice {
    final price = _entryPrice;
    if (price == null) return null;
    return _side == PositionSide.long
        ? price * (1 + _takeProfitPercent / 100)
        : price * (1 - _takeProfitPercent / 100);
  }

  @override
  void initState() {
    super.initState();
    _watchSelectedPrice();
    _loadRecords();
  }

  @override
  void dispose() {
    _livePriceSubscription?.cancel();
    _priceController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _fillMarketPrice() {
    _followMarketPrice = true;
    final price = _livePrice;
    if (price == null) {
      _priceController.clear();
    } else {
      _setPriceText(price);
    }
  }

  void _setPriceText(double price) {
    final text = formatPrice(price);
    if (_priceController.text == text) return;
    _priceController.text = text;
  }

  void _selectAsset(int index) {
    if (index == _selectedAsset) return;
    setState(() {
      _selectedAsset = index;
      _livePrice = null;
      _hasLivePrice = false;
      _followMarketPrice = true;
      _priceController.clear();
    });
    _watchSelectedPrice();
  }

  void _watchSelectedPrice() {
    final generation = ++_priceStreamGeneration;
    _livePriceSubscription?.cancel();
    _livePriceSubscription = widget.livePriceService
        .watchPrice(_snapshot.symbol)
        .listen(
          (price) {
            if (!mounted || generation != _priceStreamGeneration) return;
            setState(() {
              _livePrice = price;
              _hasLivePrice = true;
              if (_followMarketPrice) _setPriceText(price);
            });
          },
          onError: (Object _) {
            if (!mounted || generation != _priceStreamGeneration) return;
            setState(() => _hasLivePrice = false);
          },
        );
  }

  Future<void> _loadRecords() async {
    var records = <PositionRecord>[];
    try {
      records = await widget.positionRepository.load();
    } on Exception {
      records = [];
    }
    if (!mounted) return;
    setState(() {
      _records
        ..clear()
        ..addAll(records);
      _loadingRecords = false;
    });
  }

  Future<void> _addRecord() async {
    final price = _entryPrice;
    final amount = _amount;
    if (price == null || price <= 0 || amount == null || amount <= 0) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _records.insert(
        0,
        PositionRecord(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          symbol: _snapshot.symbol,
          side: _side,
          entryPrice: price,
          stopLossPercent: _stopLossPercent,
          takeProfitPercent: _takeProfitPercent,
          createdAt: DateTime.now(),
          positionAmount: amount,
          leverage: _leverage,
        ),
      );
    });
    try {
      await widget.positionRepository.save(_records);
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('记录已加入，但本机保存失败，请稍后重试')));
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${_snapshot.symbol} 开仓计划已加入记录')));
  }

  Future<void> _openRecords() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecordsPage(
          positionRepository: widget.positionRepository,
          livePriceService: widget.livePriceService,
        ),
      ),
    );
    if (!mounted) return;
    _loadRecords();
  }

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 100),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '开仓',
                    style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 30,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '先算风险，再进场',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.tealSoft,
                borderRadius: BorderRadius.circular(100),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.calculate_outlined,
                    color: AppColors.teal,
                    size: 15,
                  ),
                  SizedBox(width: 6),
                  Text(
                    '仓位计算器',
                    style: TextStyle(
                      color: AppColors.teal,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _HomePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DirectionSelector(
                side: _side,
                onChanged: (side) => setState(() => _side = side),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _HomePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _CoinSelector(
                    snapshots: widget.snapshots,
                    selectedIndex: _selectedAsset,
                    onSelected: _selectAsset,
                  ),
                  const Spacer(),
                  TextButton.icon(
                    key: const ValueKey('use-market-price'),
                    onPressed: () => setState(_fillMarketPrice),
                    icon: Icon(
                      Icons.bolt_rounded,
                      size: 17,
                      color: _hasLivePrice ? AppColors.teal : AppColors.muted,
                    ),
                    label: Text(
                      _livePrice == null
                          ? '市价 --'
                          : '${_hasLivePrice ? '实时' : '市价'} ${formatPrice(_livePrice!)}',
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.teal,
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('entry-price-input'),
                controller: _priceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: const [_ThousandsSeparatorInputFormatter()],
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.6,
                ),
                decoration: InputDecoration(
                  prefixText: r'$ ',
                  hintText: '--',
                  hintStyle: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 18,
                    fontWeight: FontWeight.w400,
                  ),
                  prefixStyle: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                  suffix: const Text(
                    'USDT',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  fillColor: Color(0xFFFAFBFC),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
                onChanged: (_) => setState(() => _followMarketPrice = false),
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const FieldLabel('开仓数量'),
                        const SizedBox(height: 8),
                        TextField(
                          key: const ValueKey('position-amount-input'),
                          controller: _amountController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: const [
                            _ThousandsSeparatorInputFormatter(),
                          ],
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: const InputDecoration(
                            suffixText: 'USDT',
                            suffixStyle: TextStyle(
                              color: AppColors.muted,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            fillColor: Color(0xFFFAFBFC),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 15,
                              vertical: 13,
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _LeverageSelector(
                      value: _leverage,
                      onChanged: (value) => setState(() => _leverage = value),
                    ),
                  ),
                ],
              ),
              
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _TargetCard(
                  key: const ValueKey('stop-loss-card'),
                  title: '止损',
                  percent: _stopLossPercent,
                  distancePercent: _side == PositionSide.long
                      ? -_stopLossPercent
                      : _stopLossPercent,
                  price: _stopLossPrice,
                  amount: -_estimatedLoss,
                  color: AppColors.red,
                  softColor: AppColors.redSoft,
                  onDecrease: () => setState(() {
                    _stopLossPercent = (_stopLossPercent - .5).clamp(.5, 50);
                  }),
                  onIncrease: () => setState(() {
                    _stopLossPercent = (_stopLossPercent + .5).clamp(.5, 50);
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TargetCard(
                  key: const ValueKey('take-profit-card'),
                  title: '止盈',
                  percent: _takeProfitPercent,
                  distancePercent: _side == PositionSide.long
                      ? _takeProfitPercent
                      : -_takeProfitPercent,
                  price: _takeProfitPrice,
                  amount: _estimatedProfit,
                  color: AppColors.teal,
                  softColor: AppColors.tealSoft,
                  onDecrease: () => setState(() {
                    _takeProfitPercent = (_takeProfitPercent - 1).clamp(1, 90);
                  }),
                  onIncrease: () => setState(() {
                    _takeProfitPercent = (_takeProfitPercent + 1).clamp(1, 90);
                  }),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _AddRecordButton(
          key: const ValueKey('add-position-record'),
          enabled: _canSubmit,
          onTap: _addRecord,
        ),
        const SizedBox(height: 14),
        _RecordsEntry(
          total: _loadingRecords ? null : _records.length,
          openCount: _openCount,
          onTap: _openRecords,
        ),
      ],
    );
  }
}

class _HomePanel extends StatelessWidget {
  const _HomePanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A23314A),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _CoinSelector extends StatelessWidget {
  const _CoinSelector({
    required this.snapshots,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<MarketSnapshot> snapshots;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      key: const ValueKey('coin-selector'),
      initialValue: selectedIndex,
      onSelected: onSelected,
      color: AppColors.surface,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      itemBuilder: (context) => List.generate(
        snapshots.length,
        (index) => PopupMenuItem<int>(
          value: index,
          child: Text('${snapshots[index].symbol}/USDT'),
        ),
      ),
      child: Container(
        height: 30,
        padding: const EdgeInsets.only(left: 9, right: 5),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              snapshots[selectedIndex].symbol,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 1),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppColors.muted,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

class _DirectionSelector extends StatelessWidget {
  const _DirectionSelector({required this.side, required this.onChanged});

  final PositionSide side;
  final ValueChanged<PositionSide> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: PositionSide.values.map((value) {
        final selected = value == side;
        final isLong = value == PositionSide.long;
        final activeColor = isLong ? AppColors.teal : AppColors.red;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: value == PositionSide.long ? 10 : 0,
            ),
            child: GestureDetector(
              key: ValueKey('direction-${value.name}'),
              onTap: () => onChanged(value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? activeColor.withValues(alpha: .08)
                      : const Color(0xFFF8F9FB),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected
                        ? activeColor.withValues(alpha: .28)
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isLong ? Icons.north_rounded : Icons.south_rounded,
                      size: 19,
                      color: selected ? activeColor : AppColors.muted,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      isLong ? '做多' : '做空',
                      style: TextStyle(
                        color: selected ? activeColor : AppColors.muted,
                        fontSize: 15,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 160),
                      opacity: selected ? 1 : 0,
                      child: Icon(
                        Icons.check_circle_rounded,
                        size: 16,
                        color: activeColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _LeverageSelector extends StatelessWidget {
  const _LeverageSelector({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = [1, 2, 3, 5, 10, 20, 50, 100, 125];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel('杠杆'),
        const SizedBox(height: 8),
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: const Color(0xFFFAFBFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              key: const ValueKey('leverage-selector'),
              value: value,
              isExpanded: true,
              borderRadius: BorderRadius.circular(16),
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              items: options
                  .map(
                    (option) => DropdownMenuItem<int>(
                      value: option,
                      child: Text('${option}X'),
                    ),
                  )
                  .toList(),
              onChanged: (selected) {
                if (selected != null) onChanged(selected);
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _TargetCard extends StatelessWidget {
  const _TargetCard({
    super.key,
    required this.title,
    required this.percent,
    required this.distancePercent,
    required this.price,
    required this.amount,
    required this.color,
    required this.softColor,
    required this.onDecrease,
    required this.onIncrease,
  });

  final String title;
  final double percent;
  final double distancePercent;
  final double? price;
  final double amount;
  final Color color;
  final Color softColor;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    final percentText = percent % 1 == 0
        ? percent.toStringAsFixed(0)
        : percent.toStringAsFixed(1);
    final icon = title == '止损' ? Icons.shield_outlined : Icons.flag_outlined;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A23314A),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [

              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              _StepButton(
                key: ValueKey('$title-decrease'),
                icon: Icons.remove_rounded,
                onTap: onDecrease,
              ),
              const SizedBox(width: 2),
              SizedBox(
                width: 30,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$percentText%',
                    style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              _StepButton(
                key: ValueKey('$title-increase'),
                icon: Icons.add_rounded,
                onTap: onIncrease,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            formatUsdt(amount),
            key: ValueKey('$title-amount'),
            style: TextStyle(
              color: color,
              fontSize: 19,
              fontWeight: FontWeight.w700,
              letterSpacing: -.3,
            ),
          ),
          const SizedBox(height: 4),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Text(
              price == null ? '价格 --' : '价格 ${formatPrice(price!)} USDT',
              key: ValueKey(price),
              maxLines: 1,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            decoration: BoxDecoration(
              color: softColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.gps_fixed_rounded, color: color, size: 13),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    '距离当前 ${distancePercent > 0 ? '+' : ''}${distancePercent.toStringAsFixed(2)}%',
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({super.key, required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 22,
          height: 22,
          child: Icon(icon, size: 13, color: AppColors.ink),
        ),
      ),
    );
  }
}

class _AddRecordButton extends StatelessWidget {
  const _AddRecordButton({
    super.key,
    required this.enabled,
    required this.onTap,
  });

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : .45,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0B8F80), Color(0xFF0A8277)],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33147D73),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(20),
            child: const SizedBox(
              height: 48,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_circle_outline_rounded, color: Colors.white),
                  SizedBox(width: 9),
                  Text(
                    '记录',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordsEntry extends StatelessWidget {
  const _RecordsEntry({
    required this.total,
    required this.openCount,
    required this.onTap,
  });

  final int? total;
  final int openCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _HomePanel(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('open-records-entry'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.tealSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.assignment_outlined,
                  color: AppColors.teal,
                  size: 20,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '开仓记录',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      total == null ? '加载中…' : '共 $total 笔 · 持仓中 $openCount 笔',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_right_rounded,
                color: AppColors.muted,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
