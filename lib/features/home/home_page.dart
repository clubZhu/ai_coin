import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../../core/ui.dart';
import '../../data/live_price_service.dart';
import '../../data/position_repository.dart';
import '../../domain/market_snapshot.dart';
import '../../domain/position_record.dart';

String _formatUsdt(double value) {
  final parts = value.abs().toStringAsFixed(2).split('.');
  final whole = formatPrice(double.parse(parts.first));
  final sign = value > 0
      ? '+'
      : value < 0
      ? '-'
      : '';
  return '$sign\$$whole.${parts.last}';
}

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

enum _RecordFilterValue { all, open, profit, loss }

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
  final _scrollController = ScrollController();
  final List<PositionRecord> _records = [];

  StreamSubscription<double>? _livePriceSubscription;
  int _priceStreamGeneration = 0;
  int _selectedAsset = 0;
  PositionSide _side = PositionSide.long;
  double _stopLossPercent = 2;
  double _takeProfitPercent = 10;
  int _leverage = 5;
  _RecordFilterValue _recordFilter = _RecordFilterValue.all;
  bool _loadingRecords = true;
  bool _hasLivePrice = false;
  bool _followMarketPrice = true;
  double? _livePrice;

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
    _scrollController.dispose();
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
    _priceController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _editRecord(int index) async {
    final updated = await showModalBottomSheet<PositionRecord>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _EditRecordSheet(record: _records[index]),
    );
    if (updated == null || !mounted) return;
    setState(() => _records[index] = updated);
    try {
      await widget.positionRepository.save(_records);
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('结果已更新，但本机保存失败，请稍后重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleRecords = switch (_recordFilter) {
      _RecordFilterValue.all => _records,
      _RecordFilterValue.open =>
        _records
            .where((record) => record.result == PositionResult.open)
            .toList(),
      _RecordFilterValue.profit =>
        _records
            .where((record) => record.result == PositionResult.profit)
            .toList(),
      _RecordFilterValue.loss =>
        _records
            .where((record) => record.result == PositionResult.loss)
            .toList(),
    };
    return PageFrame(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 34),
      children: [
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
                  fontWeight: FontWeight.w600,
                  letterSpacing: -.4,
                ),
                decoration: InputDecoration(
                  prefixText: r'$ ',
                  hintText: '--',
                  hintStyle: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 28,
                    fontWeight: FontWeight.w400,
                  ),
                  prefixStyle: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                  suffix: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'USDT',
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(width: 6),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppColors.muted,
                        size: 20,
                      ),
                    ],
                  ),
                  fillColor: Color(0xFFFAFBFC),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 13,
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
                        const _FieldLabel('开仓数量'),
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
        const SizedBox(height: 26),
        Row(
          children: [
            Expanded(
              child: Text(
                '开仓记录',
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 16,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -.3,
                ),
              ),
            ),
            _RecordFilter(
              value: _recordFilter,
              onChanged: (value) => setState(() => _recordFilter = value),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_loadingRecords)
          const _HomePanel(
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (visibleRecords.isEmpty)
          _EmptyRecords(filtered: _recordFilter != _RecordFilterValue.all)
        else
          ...List.generate(
            visibleRecords.length,
            (index) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _RecordCard(
                record: visibleRecords[index],
                onEdit: () => _editRecord(
                  _records.indexWhere(
                    (record) => record.id == visibleRecords[index].id,
                  ),
                ),
              ),
            ),
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

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        height: 1.3,
        fontWeight: FontWeight.w600,
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
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? activeColor.withValues(alpha: .08)
                      : const Color(0xFFF8F9FB),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected
                        ? activeColor.withValues(alpha: .22)
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isLong ? Icons.north_rounded : Icons.south_rounded,
                      size: 21,
                      color: selected ? activeColor : AppColors.muted,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isLong ? '做多' : '做空',
                      style: TextStyle(
                        color: selected ? activeColor : AppColors.muted,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
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
        const _FieldLabel('杠杆'),
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
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
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
                width: 36,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$percentText%',
                    style: TextStyle(
                      color: color,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
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
            _formatUsdt(amount),
            key: ValueKey('$title-amount'),
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: -.25,
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
          width: 25,
          height: 25,
          child: Icon(icon, size: 15, color: AppColors.ink),
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
    return Opacity(
      opacity: enabled ? 1 : .45,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0B8F80), Color(0xFF0A8277)],
          ),
          borderRadius: BorderRadius.circular(19),
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
          borderRadius: BorderRadius.circular(19),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(19),
            child: const SizedBox(
              height: 46,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_circle_outline_rounded, color: Colors.white),
                  SizedBox(width: 9),
                  Text(
                    '加入开仓记录',
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

class _RecordFilter extends StatelessWidget {
  const _RecordFilter({required this.value, required this.onChanged});

  final _RecordFilterValue value;
  final ValueChanged<_RecordFilterValue> onChanged;

  @override
  Widget build(BuildContext context) {
    final label = switch (value) {
      _RecordFilterValue.all => '全部',
      _RecordFilterValue.open => '持仓',
      _RecordFilterValue.profit => '盈利',
      _RecordFilterValue.loss => '亏损',
    };
    return PopupMenuButton<_RecordFilterValue>(
      key: const ValueKey('record-filter'),
      initialValue: value,
      onSelected: onChanged,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (context) => const [
        PopupMenuItem(value: _RecordFilterValue.all, child: Text('全部')),
        PopupMenuItem(value: _RecordFilterValue.open, child: Text('持仓')),
        PopupMenuItem(value: _RecordFilterValue.profit, child: Text('盈利')),
        PopupMenuItem(value: _RecordFilterValue.loss, child: Text('亏损')),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A23314A),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 7),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppColors.muted,
              size: 19,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyRecords extends StatelessWidget {
  const _EmptyRecords({required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context) {
    return _HomePanel(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(
                  Icons.assignment_outlined,
                  color: Color(0xFFC8D0E2),
                  size: 46,
                ),
                Positioned(
                  left: -8,
                  top: 2,
                  child: Icon(
                    Icons.add_rounded,
                    color: AppColors.teal.withValues(alpha: .28),
                    size: 17,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              filtered ? '没有符合条件的记录' : '暂无开仓记录',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 7),
            Text(
              filtered ? '切换筛选条件查看其他记录' : '添加第一笔开仓记录，开始追踪你的交易。',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record, required this.onEdit});

  final PositionRecord record;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final isLong = record.side == PositionSide.long;
    final resultColor = switch (record.result) {
      PositionResult.open => AppColors.blue,
      PositionResult.profit => AppColors.teal,
      PositionResult.loss => AppColors.red,
    };
    final resultLabel = switch (record.result) {
      PositionResult.open => '持仓中',
      PositionResult.profit => '盈利',
      PositionResult.loss => '亏损',
    };
    final time =
        '${record.createdAt.hour.toString().padLeft(2, '0')}:${record.createdAt.minute.toString().padLeft(2, '0')}';

    return _HomePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.tealSoft,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  record.symbol == 'BTC' ? '₿' : 'Ξ',
                  style: const TextStyle(
                    color: AppColors.teal,
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        record.symbol,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 7),
                      StatusPill(
                        label: isLong ? '做多 ↑' : '做空 ↓',
                        foreground: isLong ? AppColors.teal : AppColors.red,
                        background: isLong
                            ? AppColors.tealSoft
                            : AppColors.redSoft,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '今天 $time',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: resultColor.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  resultLabel,
                  style: TextStyle(
                    color: resultColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '开仓 \$${formatPrice(record.entryPrice)}  ·  ${formatPrice(record.positionAmount)} USDT  ·  ${record.leverage}X',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _RecordTarget(
                  label: '止损 ${_percent(record.stopLossPercent)}',
                  amount: -record.estimatedLoss,
                  price: record.stopLossPrice,
                  color: AppColors.red,
                ),
              ),
              Container(width: 1, height: 46, color: AppColors.line),
              const SizedBox(width: 16),
              Expanded(
                child: _RecordTarget(
                  label: '止盈 ${_percent(record.takeProfitPercent)}',
                  amount: record.estimatedProfit,
                  price: record.takeProfitPrice,
                  color: AppColors.teal,
                ),
              ),
            ],
          ),
          if (record.result != PositionResult.open) ...[
            const SizedBox(height: 17),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: resultColor.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        '实际结果',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const Spacer(),
                      Text(
                        _formatUsdt(record.realizedAmount ?? 0),
                        style: TextStyle(
                          color: resultColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Text(
                        '平仓价格',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const Spacer(),
                      if (record.closePrice != null)
                        Text(
                          r'$' + formatPrice(record.closePrice!),
                          style: const TextStyle(fontSize: 12),
                        ),
                      const SizedBox(width: 10),
                      Text(
                        '${(record.realizedPercent ?? 0) > 0 ? '+' : ''}${(record.realizedPercent ?? 0).toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: resultColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          OutlinedButton.icon(
            key: ValueKey('edit-record-${record.id}'),
            onPressed: onEdit,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              foregroundColor: AppColors.ink,
              side: const BorderSide(color: AppColors.line),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.edit_outlined, size: 17),
            label: Text(
              record.result == PositionResult.open ? '记录盈亏结果' : '编辑结果',
            ),
          ),
        ],
      ),
    );
  }

  static String _percent(double value) {
    final text = value % 1 == 0
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '$text%';
  }
}

class _RecordTarget extends StatelessWidget {
  const _RecordTarget({
    required this.label,
    required this.amount,
    required this.price,
    required this.color,
  });

  final String label;
  final double amount;
  final double price;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 3),
        Text(
          _formatUsdt(amount),
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '\$${formatPrice(price)}',
          style: const TextStyle(color: AppColors.muted, fontSize: 11),
        ),
      ],
    );
  }
}

class _EditRecordSheet extends StatefulWidget {
  const _EditRecordSheet({required this.record});

  final PositionRecord record;

  @override
  State<_EditRecordSheet> createState() => _EditRecordSheetState();
}

class _EditRecordSheetState extends State<_EditRecordSheet> {
  late PositionResult _result;
  late final TextEditingController _percentController;
  late final TextEditingController _closePriceController;

  @override
  void initState() {
    super.initState();
    _result = widget.record.result;
    _percentController = TextEditingController(
      text: widget.record.realizedPercent?.abs().toStringAsFixed(1) ?? '',
    );
    _closePriceController = TextEditingController(
      text: widget.record.closePrice == null
          ? ''
          : widget.record.closePrice!.toStringAsFixed(1),
    );
  }

  @override
  void dispose() {
    _percentController.dispose();
    _closePriceController.dispose();
    super.dispose();
  }

  void _selectResult(PositionResult result) {
    setState(() {
      _result = result;
      if (result == PositionResult.profit && _percentController.text.isEmpty) {
        _percentController.text = widget.record.takeProfitPercent
            .toStringAsFixed(1);
      } else if (result == PositionResult.loss &&
          _percentController.text.isEmpty) {
        _percentController.text = widget.record.stopLossPercent.toStringAsFixed(
          1,
        );
      }
    });
  }

  void _save() {
    if (_result == PositionResult.open) {
      Navigator.of(context).pop(
        widget.record.copyWith(
          result: PositionResult.open,
          clearClosePrice: true,
          clearRealizedPercent: true,
        ),
      );
      return;
    }
    final rawPercent = double.tryParse(_percentController.text) ?? 0;
    final signedPercent = _result == PositionResult.loss
        ? -rawPercent.abs()
        : rawPercent.abs();
    Navigator.of(context).pop(
      widget.record.copyWith(
        result: _result,
        realizedPercent: signedPercent,
        closePrice: double.tryParse(_closePriceController.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + bottomInset),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.line,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text('编辑交易结果', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 5),
              Text(
                '${widget.record.symbol} · ${widget.record.side == PositionSide.long ? '做多' : '做空'} · 开仓 ${formatPrice(widget.record.entryPrice)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              const _FieldLabel('当前结果'),
              const SizedBox(height: 9),
              Row(
                children: [
                  _ResultOption(
                    key: const ValueKey('result-open'),
                    label: '持仓中',
                    selected: _result == PositionResult.open,
                    color: AppColors.blue,
                    onTap: () => _selectResult(PositionResult.open),
                  ),
                  const SizedBox(width: 8),
                  _ResultOption(
                    key: const ValueKey('result-profit'),
                    label: '盈利',
                    selected: _result == PositionResult.profit,
                    color: AppColors.teal,
                    onTap: () => _selectResult(PositionResult.profit),
                  ),
                  const SizedBox(width: 8),
                  _ResultOption(
                    key: const ValueKey('result-loss'),
                    label: '亏损',
                    selected: _result == PositionResult.loss,
                    color: AppColors.red,
                    onTap: () => _selectResult(PositionResult.loss),
                  ),
                ],
              ),
              if (_result != PositionResult.open) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _SheetNumberField(
                        fieldKey: const ValueKey('close-price-input'),
                        label: '平仓价格',
                        controller: _closePriceController,
                        prefix: r'$',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SheetNumberField(
                        fieldKey: const ValueKey('result-percent-input'),
                        label: '实际盈亏',
                        controller: _percentController,
                        suffix: '%',
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                key: const ValueKey('save-record-result'),
                onPressed: _save,
                child: const Text('保存结果'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultOption extends StatelessWidget {
  const _ResultOption({
    super.key,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: .11)
                : AppColors.background,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected ? color.withValues(alpha: .35) : AppColors.line,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? color : AppColors.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetNumberField extends StatelessWidget {
  const _SheetNumberField({
    required this.fieldKey,
    required this.label,
    required this.controller,
    this.prefix,
    this.suffix,
  });

  final Key fieldKey;
  final String label;
  final TextEditingController controller;
  final String? prefix;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label),
        const SizedBox(height: 8),
        TextField(
          key: fieldKey,
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: InputDecoration(prefixText: prefix, suffixText: suffix),
        ),
      ],
    );
  }
}
