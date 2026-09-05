import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../../core/ui.dart';
import '../../data/live_price_service.dart';
import '../../data/position_repository.dart';
import '../../domain/trading_assets.dart';
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
    this.symbols = TradingAssets.symbols,
    required this.positionRepository,
    required this.livePriceService,
  });

  final List<String> symbols;
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
  bool _hasLivePrice = false;
  bool _followMarketPrice = true;
  double? _livePrice;

  String get _symbol => widget.symbols[_selectedAsset];
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
        .watchPrice(_symbol)
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
          symbol: _symbol,
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
    ).showSnackBar(SnackBar(content: Text('$_symbol 开仓计划已加入记录')));
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
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Expanded(
              child: Text(
                '开仓',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 26,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -.5,
                ),
              ),
            ),
            const SizedBox(width: 10),
            TextButton.icon(
              key: const ValueKey('open-records-entry'),
              onPressed: _openRecords,
              icon: const Icon(Icons.assignment_outlined, size: 16),
              label: const Text('开仓记录'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.muted,
                backgroundColor: AppColors.surface,
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 13),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                side: const BorderSide(color: AppColors.line),
                shape: const StadiumBorder(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _HomePanel(
          padding: const EdgeInsets.all(10),
          child: _DirectionSelector(
            side: _side,
            onChanged: (side) => setState(() => _side = side),
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
                    symbols: widget.symbols,
                    selectedIndex: _selectedAsset,
                    onSelected: _selectAsset,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        key: const ValueKey('use-market-price'),
                        onPressed: () => setState(_fillMarketPrice),
                        icon: Icon(
                          Icons.bolt_rounded,
                          size: 15,
                          color: _hasLivePrice
                              ? AppColors.teal
                              : AppColors.muted,
                        ),
                        label: Text(
                          _livePrice == null
                              ? '市价 --'
                              : '${_hasLivePrice ? '实时' : '市价'} ${formatPrice(_livePrice!)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: _hasLivePrice
                              ? AppColors.teal
                              : AppColors.muted,
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const _HomeFieldLabel('开仓价格'),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('entry-price-input'),
                controller: _priceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: const [_ThousandsSeparatorInputFormatter()],
                textInputAction: TextInputAction.next,
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                style: const TextStyle(
                  fontSize: 22,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -.3,
                ),
                decoration: _homeInputDecoration.copyWith(
                  prefixText: r'$ ',
                  hintText: '--',
                  hintStyle: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 22,
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
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
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
                        const _HomeFieldLabel('开仓数量'),
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
                          textInputAction: TextInputAction.done,
                          onTapOutside: (_) =>
                              FocusManager.instance.primaryFocus?.unfocus(),
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.25,
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: _homeInputDecoration.copyWith(
                            suffixText: 'USDT',
                            suffixStyle: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
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
      ],
    );
  }
}

class _HomePanel extends StatelessWidget {
  const _HomePanel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF0F1F4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0523314A),
            blurRadius: 18,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

const _homeInputDecoration = InputDecoration(
  filled: true,
  isDense: true,
  fillColor: Color(0xFFFAFBFC),
  contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(13)),
    borderSide: BorderSide(color: AppColors.line),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(13)),
    borderSide: BorderSide(color: AppColors.teal),
  ),
);

class _HomeFieldLabel extends StatelessWidget {
  const _HomeFieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.muted,
        fontSize: 12,
        height: 1.3,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _CoinSelector extends StatelessWidget {
  const _CoinSelector({
    required this.symbols,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> symbols;
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
        symbols.length,
        (index) => PopupMenuItem<int>(
          value: index,
          child: Text('${symbols[index]}/USDT'),
        ),
      ),
      child: Container(
        height: 36,
        padding: const EdgeInsets.only(left: 10, right: 6),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              symbols[selectedIndex],
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
            const SizedBox(width: 4),
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
            child: Semantics(
              button: true,
              selected: selected,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 46,
                decoration: BoxDecoration(
                  color: selected
                      ? activeColor.withValues(alpha: .07)
                      : const Color(0xFFF8F9FB),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: selected
                        ? activeColor.withValues(alpha: .18)
                        : Colors.transparent,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: ValueKey('direction-${value.name}'),
                    onTap: () => onChanged(value),
                    borderRadius: BorderRadius.circular(13),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isLong ? Icons.north_rounded : Icons.south_rounded,
                          size: 18,
                          color: selected ? activeColor : AppColors.muted,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          isLong ? '做多' : '做空',
                          style: TextStyle(
                            color: selected ? activeColor : AppColors.muted,
                            fontSize: 15,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
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
        const _HomeFieldLabel('杠杆'),
        const SizedBox(height: 8),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: const Color(0xFFFAFBFC),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: AppColors.line),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              key: const ValueKey('leverage-selector'),
              value: value,
              isExpanded: true,
              dropdownColor: AppColors.surface,
              borderRadius: BorderRadius.circular(13),
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AppColors.muted,
                size: 18,
              ),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
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
                title,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 13,
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
              Flexible(
                flex: 3,
                child: SizedBox(
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
              ),
              const SizedBox(width: 2),
              _StepButton(
                key: ValueKey('$title-increase'),
                icon: Icons.add_rounded,
                onTap: onIncrease,
              ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatUsdt(amount),
              key: ValueKey('$title-amount'),
              style: TextStyle(
                color: color,
                fontSize: 22,
                height: 1.25,
                fontWeight: FontWeight.w500,
                letterSpacing: -.4,
              ),
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              price == null ? '价格 --' : '价格 ${formatPrice(price!)} USDT',
              key: ValueKey(price),
              maxLines: 1,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                height: 1.4,
                fontWeight: FontWeight.w400,
              ),
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
                Flexible(
                  child: Text(
                    '开仓价 ${distancePercent > 0 ? '+' : ''}${distancePercent.toStringAsFixed(2)}%',
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w400,
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
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          width: 26,
          height: 32,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(7),
              ),
              child: SizedBox(
                width: 24,
                height: 24,
                child: Icon(icon, size: 15, color: AppColors.ink),
              ),
            ),
          ),
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
            colors: [Color(0xFF11897D), Color(0xFF147D73)],
          ),
          borderRadius: BorderRadius.circular(15),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A147D73),
              blurRadius: 12,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(15),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(15),
            child: const SizedBox(
              height: 48,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 7),
                  Text(
                    '加入开仓记录',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
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
