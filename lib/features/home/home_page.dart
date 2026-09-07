import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
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
  final Map<String, double> _recordPrices = {};
  final Map<String, StreamSubscription<double>> _recordPriceSubscriptions = {};

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

  int get _openRecordCount =>
      _records.where((record) => record.result == PositionResult.open).length;

  double? get _openUnrealizedAmount {
    var total = 0.0;
    var counted = 0;
    for (final record in _records) {
      if (record.result != PositionResult.open) continue;
      final price = _recordPrices[record.symbol];
      if (price == null) continue;
      final amount = record.unrealizedAmount(price);
      if (amount == null) continue;
      total += amount;
      counted++;
    }
    return counted == 0 ? null : total;
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
    for (final subscription in _recordPriceSubscriptions.values) {
      subscription.cancel();
    }
    _priceController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _watchRecordPrices() {
    final symbols = _records
        .where((record) => record.result == PositionResult.open)
        .map((record) => record.symbol)
        .toSet();
    for (final symbol in _recordPriceSubscriptions.keys.toList()) {
      if (!symbols.contains(symbol)) {
        _recordPriceSubscriptions.remove(symbol)!.cancel();
        _recordPrices.remove(symbol);
      }
    }
    for (final symbol in symbols) {
      if (_recordPriceSubscriptions.containsKey(symbol)) continue;
      _recordPriceSubscriptions[symbol] = widget.livePriceService
          .watchPrice(symbol)
          .listen((price) {
            if (!mounted) return;
            setState(() => _recordPrices[symbol] = price);
          }, onError: (Object _) {});
    }
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
    _watchRecordPrices();
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
    _watchRecordPrices();
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
                'Save',
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
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('记录'),
                  if (_openRecordCount > 0) ...[
                    const SizedBox(width: 6),
                    if (_openUnrealizedAmount == null)
                      const Text(
                        '--',
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      )
                    else
                      _RollingValue(
                        value: _openUnrealizedAmount!,
                        style: TextStyle(
                          color: _openUnrealizedAmount! < 0
                              ? AppColors.red
                              : AppColors.teal,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -.2,
                        ),
                      ),
                  ],
                ],
              ),
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
              const _HomeFieldLabel('价格'),
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
                        const _HomeFieldLabel('数量'),
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
        const SizedBox(height: 12),
        _ProfitJarCard(
          amount: _openUnrealizedAmount,
          openCount: _openRecordCount,
        ),
      ],
    );
  }
}

class _RollingValue extends StatefulWidget {
  const _RollingValue({required this.value, required this.style});

  final double value;
  final TextStyle style;

  @override
  State<_RollingValue> createState() => _RollingValueState();
}

class _RollingValueState extends State<_RollingValue>
    with SingleTickerProviderStateMixin {
  static const _decimalPlaces = [-1, -2];

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..addListener(() => setState(() {}));

  late double _from = widget.value;
  late double _to = widget.value;
  final Map<String, double> _glyphWidths = {};

  double get _t => Curves.easeInOutCubic.transform(_controller.value);

  TextStyle get _style => widget.style.copyWith(height: 1.25);

  double get _lineHeight => (widget.style.fontSize ?? 12) * 1.25;

  TextScaler get _textScaler => MediaQuery.textScalerOf(context);

  @override
  void didUpdateWidget(_RollingValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _from = _displayedValue;
      _to = widget.value;
      _controller.forward(from: 0);
    }
  }

  double get _displayedValue => lerpDouble(_from, _to, _t)!;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _glyphWidth(String glyph) {
    final key = '${_textScaler.scale(10)}:$glyph';
    return _glyphWidths.putIfAbsent(key, () {
      final painter = TextPainter(
        text: TextSpan(text: glyph, style: _style),
        textDirection: TextDirection.ltr,
        textScaler: _textScaler,
      )..layout();
      return painter.width;
    });
  }

  static int _integerDigits(double value) {
    final whole = value.abs().floor();
    return whole <= 0 ? 1 : whole.toString().length;
  }

  static double _digitAt(double value, int place) {
    final shifted = value.abs() * math.pow(10.0, -place);
    return (shifted.floor() % 10).toDouble();
  }

  double _animatedDigit(int place) {
    final fromDigit = _digitAt(_from, place);
    final toDigit = _digitAt(_to, place);
    if (fromDigit == toDigit) return fromDigit;
    // Always roll upward; past 9 the strip wraps seamlessly back to 0.
    final distance = (toDigit - fromDigit) % 10;
    return fromDigit + distance * _t;
  }

  @override
  Widget build(BuildContext context) {
    final height = _lineHeight;
    final digitWidth = _glyphWidth('0');
    final sign = _displayedValue < 0 ? '-' : '+';
    final intDigits = math.max(_integerDigits(_from), _integerDigits(_to));

    final children = <Widget>[
      _ValueGlyph(sign, height, _glyphWidth(sign), _style),
      _ValueGlyph(r'$', height, _glyphWidth(r'$'), _style),
    ];
    for (var place = intDigits - 1; place >= 0; place--) {
      if (place > 0 && place % 3 == 2 && place != intDigits - 1) {
        children.add(_ValueGlyph(',', height, _glyphWidth(','), _style));
      }
      children.add(
        _DigitColumn(
          position: _animatedDigit(place),
          height: height,
          width: digitWidth,
          style: _style,
        ),
      );
    }
    children.add(_ValueGlyph('.', height, _glyphWidth('.'), _style));
    for (final place in _decimalPlaces) {
      children.add(
        _DigitColumn(
          position: _animatedDigit(place),
          height: height,
          width: digitWidth,
          style: _style,
        ),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

class _ValueGlyph extends StatelessWidget {
  const _ValueGlyph(this.text, this.height, this.width, this.style);

  final String text;
  final double height;
  final double width;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Center(child: Text(text, style: style)),
    );
  }
}

class _DigitColumn extends StatelessWidget {
  const _DigitColumn({
    required this.position,
    required this.height,
    required this.width,
    required this.style,
  });

  final double position;
  final double height;
  final double width;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final base = position.floor();
    final fraction = position - base;
    String glyph(int value) => '${((value % 10) + 10) % 10}';

    if (fraction <= 0) {
      return _ValueGlyph(glyph(base), height, width, style);
    }
    return SizedBox(
      width: width,
      height: height,
      child: ClipRect(
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: -fraction * height,
              height: height * 2,
              child: Column(
                children: [
                  _ValueGlyph(glyph(base), height, width, style),
                  _ValueGlyph(glyph(base + 1), height, width, style),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _kJarRippleDuration = Duration(milliseconds: 460);

const _jarCaptionStyle = TextStyle(
  color: AppColors.muted,
  fontSize: 11,
  height: 1.4,
  fontWeight: FontWeight.w400,
);

class _ProfitJarCard extends StatefulWidget {
  const _ProfitJarCard({required this.amount, required this.openCount});

  final double? amount;
  final int openCount;

  @override
  State<_ProfitJarCard> createState() => _ProfitJarCardState();
}

class _ProfitJarCardState extends State<_ProfitJarCard>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  Duration _elapsed = Duration.zero;
  int _placed = 0; // coins fully stacked in the jar
  int _fromCoins = 0;
  int _targetCoins = 0;
  int _lastPlaced = 0;
  Duration _countStart = Duration.zero;
  Duration _countDuration = const Duration(milliseconds: 600);
  bool _countAnimating = false;
  int _flightIndex = -1; // coin currently entering or leaving the stack
  double _flightT = 0;
  bool _flightIn = true;
  final List<_JarRipple> _ripples = [];
  final List<_JarFlowCoin> _flows = [];
  math.Random? _random;

  double _nextSeed() => (_random ??= math.Random()).nextDouble();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    final initial = _countFor(widget.amount);
    _placed = _fromCoins = _targetCoins = _lastPlaced = initial;
  }

  @override
  void didUpdateWidget(_ProfitJarCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final amount = widget.amount;
    final count = _countFor(amount);
    var active = false;
    if (count != _countFor(oldWidget.amount)) {
      // Whole-dollar change: coins join or leave the stack one by one.
      _fromCoins = _placed;
      _targetCoins = count;
      _countDuration = Duration(
        milliseconds: (420 + 52 * (count - _placed).abs()).clamp(420, 1600),
      );
      _countStart = _elapsed;
      _countAnimating = true;
      _flightIn = count >= _placed;
      _lastPlaced = _placed;
      active = true;
    } else {
      // Sub-dollar change: a single coin still flies in or out.
      final delta = (amount ?? 0) - (oldWidget.amount ?? 0);
      final inward = delta > 0;
      if (delta.abs() >= 0.005 &&
          _flows.length < 4 &&
          (inward || _placed > 0)) {
        _flows.add(
          _JarFlowCoin(start: _elapsed, inward: inward, seed: _nextSeed()),
        );
        active = true;
      }
    }
    if (active && !_ticker.isActive) _ticker.start();
  }

  @override
  void dispose() {
    _ticker.stop();
    super.dispose();
  }

  static int _countFor(double? amount) {
    if (amount == null || amount <= 0) return 0;
    return amount.floor();
  }

  void _onTick(Duration elapsed) {
    _elapsed = elapsed;
    if (_countAnimating) {
      final t =
          ((elapsed - _countStart).inMicroseconds /
                  _countDuration.inMicroseconds)
              .clamp(0.0, 1.0);
      final v = lerpDouble(
        _fromCoins.toDouble(),
        _targetCoins.toDouble(),
        Curves.easeInOutCubic.transform(t),
      )!;
      _placed = v.floor();
      _flightIndex = _placed;
      _flightT = v - _placed;
      if (_flightT <= 0.001 || _flightIndex >= _targetCoins) {
        _flightIndex = -1;
      }
      if (v > _lastPlaced && _ripples.length < 3) {
        _ripples.add(_JarRipple(start: elapsed, index: _lastPlaced));
      }
      _lastPlaced = _placed;
      if (t >= 1) {
        _countAnimating = false;
        _placed = _targetCoins;
        _flightIndex = -1;
      }
    }
    for (final flow in _flows) {
      if (!flow.landed && flow.inward && flow.progress(elapsed) >= .92) {
        flow.landed = true;
        if (_ripples.length < 3) {
          _ripples.add(_JarRipple(start: elapsed, seedX: flow.seed));
        }
      }
    }
    _flows.removeWhere((flow) => flow.isFinished(elapsed));
    _ripples.removeWhere((ripple) => ripple.isFinished(elapsed));
    if (!_countAnimating && _ripples.isEmpty && _flows.isEmpty) {
      _ticker.stop();
      _elapsed = Duration.zero;
      _countStart = Duration.zero;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final amount = widget.amount;
    return _HomePanel(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            height: 124,
            child: CustomPaint(
              painter: _JarPainter(
                placed: _placed,
                flightIndex: _flightIndex,
                flightT: _flightT,
                flightIn: _flightIn,
                ripples: _ripples,
                flows: _flows,
                elapsed: _elapsed,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('开仓中浮动盈亏', style: _jarCaptionStyle),
                const SizedBox(height: 5),
                if (amount == null)
                  const Text(
                    '--',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 22,
                      height: 1.25,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -.4,
                    ),
                  )
                else
                  _RollingValue(
                    value: amount,
                    style: TextStyle(
                      color: amount < 0 ? AppColors.red : AppColors.teal,
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -.4,
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  widget.openCount > 0
                      ? '持仓 ${widget.openCount} 笔 · 金币随盈亏增减'
                      : '暂无持仓记录',
                  style: _jarCaptionStyle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JarRipple {
  _JarRipple({required this.start, this.index, this.seedX});

  final Duration start;
  final int? index;
  final double? seedX;

  bool isFinished(Duration elapsed) => elapsed >= start + _kJarRippleDuration;

  double progress(Duration elapsed) =>
      ((elapsed - start).inMicroseconds / _kJarRippleDuration.inMicroseconds)
          .clamp(0.0, 1.0);
}

class _JarFlowCoin {
  _JarFlowCoin({required this.start, required this.inward, required this.seed});

  final Duration start;
  final bool inward;
  final double seed;
  bool landed = false;

  Duration get lifetime => Duration(milliseconds: inward ? 640 : 780);

  bool isFinished(Duration elapsed) => elapsed >= start + lifetime;

  double progress(Duration elapsed) =>
      ((elapsed - start).inMicroseconds / lifetime.inMicroseconds).clamp(
        0.0,
        1.0,
      );
}

/// One coin in the jar: a 1, 10 or 100 coin with its laid-out geometry.
class _JarCoinSlot {
  const _JarCoinSlot(this.denom, this.center, this.radius, this.height);

  final int denom;
  final Offset center;
  final double radius;
  final double height;
}

/// Geometry of a whole coin stack laid out inside the jar interior.
class _JarStackLayout {
  const _JarStackLayout(this.coins, this.unit, this.height);

  final List<_JarCoinSlot> coins;
  final double unit; // diameter of a 1 coin
  final double height; // vertical space the stack occupies
}

class _JarPainter extends CustomPainter {
  _JarPainter({
    required this.placed,
    required this.flightIndex,
    required this.flightT,
    required this.flightIn,
    required this.ripples,
    required this.flows,
    required this.elapsed,
  });

  // Slot units across one row of the jar.
  static const _perRow = 4;
  // Slot units a coin of each denomination occupies across a row.
  static const _denomUnits = <int, int>{1: 1, 10: 2, 100: 4};
  // Coin diameter relative to the unit (a 1 coin).
  static const _denomDiameter = <int, double>{1: .88, 10: 1.68, 100: 3.3};

  final int placed;
  final int flightIndex;
  final double flightT;
  final bool flightIn;
  final List<_JarRipple> ripples;
  final List<_JarFlowCoin> flows;
  final Duration elapsed;

  @override
  void paint(Canvas canvas, Size size) {
    final lidWidth = size.width * .56;
    final lidHeight = size.height * .115;
    final lidRect = Rect.fromLTWH(
      (size.width - lidWidth) / 2,
      0,
      lidWidth,
      lidHeight,
    );
    final lid = RRect.fromRectAndRadius(lidRect, const Radius.circular(6));
    final bodyTop = lidHeight + size.height * .035;
    final bodyInset = size.width * .09;
    final body = RRect.fromRectAndCorners(
      Rect.fromLTRB(bodyInset, bodyTop, size.width - bodyInset, size.height),
      topLeft: const Radius.circular(10),
      topRight: const Radius.circular(10),
      bottomLeft: const Radius.circular(20),
      bottomRight: const Radius.circular(20),
    );
    final inner = body.deflate(3.5);
    final centerX = size.width / 2;
    final stack = _layoutStack(inner, placed);
    final unit = stack.unit;

    // Interior: the coin stack, ripples and the entering coin are clipped so a
    // coin only appears once it is inside the jar.
    canvas.save();
    canvas.clipRRect(inner);
    for (final coin in stack.coins) {
      _drawCoin(
        canvas,
        coin.center,
        coin.radius,
        flatten: coin.height * .5,
        opacity: .96,
      );
    }
    for (final ripple in ripples) {
      final p = Curves.easeOutCubic.transform(ripple.progress(elapsed));
      final Offset center;
      if (ripple.index != null) {
        final slot = _slotFor(inner, ripple.index!);
        center = slot == null
            ? _pileTop(inner, stack, ripple.seedX ?? .5)
            : Offset(slot.center.dx, slot.center.dy - slot.height * .5);
      } else {
        center = _pileTop(inner, stack, ripple.seedX ?? .5);
      }
      final width = unit * .8 + 16 * p;
      canvas.drawOval(
        Rect.fromCenter(center: center, width: width, height: width * .26),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = AppColors.amber.withValues(alpha: .38 * (1 - p)),
      );
    }
    if (flightIndex >= 0 && flightIn && flightT > 0) {
      final slot = _slotFor(inner, flightIndex);
      if (slot != null) {
        final easeFall = Curves.easeInQuad.transform(flightT);
        final easeDrift = Curves.easeOutCubic.transform(flightT);
        final startX =
            centerX + (flightIndex % 2 == 0 ? -1.0 : 1.0) * lidWidth * .08;
        final x = lerpDouble(startX, slot.center.dx, easeDrift)!;
        final y = lerpDouble(bodyTop + 2, slot.center.dy - 1, easeFall)!;
        _drawCoin(
          canvas,
          Offset(x, y),
          slot.radius,
          flatten: lerpDouble(slot.radius, slot.height * .5, easeFall),
          spin: (1 - easeFall) * (flightIndex * 1.7 + flightT * math.pi * 2),
          opacity: flightT < .12 ? flightT / .12 : 1,
        );
      }
    }
    for (final flow in flows) {
      if (!flow.inward || flow.progress(elapsed) <= 0) continue;
      final p = flow.progress(elapsed);
      final easeFall = Curves.easeInQuad.transform(p);
      final easeDrift = Curves.easeOutCubic.transform(p);
      final from = Offset(
        inner.left + inner.width / 2 + (flow.seed - .5) * lidWidth * .2,
        bodyTop + 2,
      );
      final to = _pileTop(inner, stack, flow.seed);
      final x = lerpDouble(from.dx, to.dx, easeDrift)!;
      final y = lerpDouble(from.dy, to.dy, easeFall)!;
      _drawCoin(
        canvas,
        Offset(x, y),
        unit * .44,
        flatten: lerpDouble(unit * .44, unit * .18, easeFall),
        spin: (1 - easeFall) * (flow.seed * 6 + p * math.pi * 2),
        opacity: p < .12 ? p / .12 : 1,
      );
    }
    if (flightIndex >= 0 && !flightIn) {
      final slot = _slotFor(inner, flightIndex);
      _drawExit(
        canvas: canvas,
        t: flightT,
        clippedPhase: true,
        from: slot?.center ?? _pileTop(inner, stack, .5),
        centerX: centerX,
        bodyTop: bodyTop,
        coinRadius: slot?.radius ?? unit * .44,
        coinHeight: slot?.height ?? unit * .36,
        side: flightIndex % 2 == 0 ? -1.0 : 1.0,
        drift: 10 + (flightIndex % 3) * 5,
      );
    }
    for (final flow in flows) {
      if (flow.inward) continue;
      _drawExit(
        canvas: canvas,
        t: flow.progress(elapsed),
        clippedPhase: true,
        from: _pileTop(inner, stack, flow.seed),
        centerX: centerX,
        bodyTop: bodyTop,
        coinRadius: unit * .44,
        coinHeight: unit * .36,
        side: flow.seed < .5 ? -1.0 : 1.0,
        drift: 10 + flow.seed * 14,
      );
    }
    canvas.restore();

    // Glass body.
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = AppColors.muted.withValues(alpha: .38),
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(inner.left + 5, bodyTop + 9, 5, inner.height * .42),
        topLeft: const Radius.circular(2.5),
        topRight: const Radius.circular(2.5),
        bottomLeft: const Radius.circular(2.5),
        bottomRight: const Radius.circular(2.5),
      ),
      Paint()..color = Colors.white.withValues(alpha: .6),
    );

    // Lid and coin slot.
    canvas.drawRRect(lid, Paint()..color = AppColors.background);
    canvas.drawRRect(
      lid,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = AppColors.muted.withValues(alpha: .38),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(centerX, lidRect.center.dy),
          width: lidWidth * .34,
          height: 3.5,
        ),
        const Radius.circular(2),
      ),
      Paint()..color = AppColors.ink.withValues(alpha: .32),
    );

    // Above the glass: coins that slipped out of the slot drift away and fade.
    if (flightIndex >= 0 && !flightIn) {
      final slot = _slotFor(inner, flightIndex);
      _drawExit(
        canvas: canvas,
        t: flightT,
        clippedPhase: false,
        from: slot?.center ?? _pileTop(inner, stack, .5),
        centerX: centerX,
        bodyTop: bodyTop,
        coinRadius: slot?.radius ?? unit * .44,
        coinHeight: slot?.height ?? unit * .36,
        side: flightIndex % 2 == 0 ? -1.0 : 1.0,
        drift: 10 + (flightIndex % 3) * 5,
      );
    }
    for (final flow in flows) {
      if (flow.inward) continue;
      _drawExit(
        canvas: canvas,
        t: flow.progress(elapsed),
        clippedPhase: false,
        from: _pileTop(inner, stack, flow.seed),
        centerX: centerX,
        bodyTop: bodyTop,
        coinRadius: unit * .44,
        coinHeight: unit * .36,
        side: flow.seed < .5 ? -1.0 : 1.0,
        drift: 10 + flow.seed * 14,
      );
    }
  }

  Offset _pileTop(RRect inner, _JarStackLayout stack, double seed) {
    if (stack.coins.isEmpty) {
      return Offset(
        inner.left + inner.width * (.35 + .3 * seed),
        inner.bottom - stack.unit * .2,
      );
    }
    final top = stack.coins.last;
    return Offset(top.center.dx, top.center.dy - top.height * .55);
  }

  /// Where the coin added as placement number [index] would sit in a stack of
  /// exactly [index] + 1 coins — e.g. the 10th dollar becomes a big 10 coin.
  _JarCoinSlot? _slotFor(RRect inner, int index) {
    final layout = _layoutStack(inner, index + 1);
    if (layout.coins.isEmpty) return null;
    return layout.coins.last;
  }

  /// Breaks [count] dollars into 1 / 10 / 100 coins, packed into rows of
  /// [_perRow] slot units with the biggest denominations at the bottom, e.g.
  /// 234 -> [100], [10, 10], [1, 1, 1, 1] rows.
  static List<List<int>> _rowsFor(int count) {
    var hundreds = count ~/ 100;
    var tens = (count % 100) ~/ 10;
    var ones = count % 10;
    final rows = <List<int>>[];
    while (hundreds > 0 || tens > 0 || ones > 0) {
      final row = <int>[];
      var space = _perRow;
      while (true) {
        if (hundreds > 0 && space >= 4) {
          row.add(100);
          hundreds--;
          space -= 4;
        } else if (tens > 0 && space >= 2) {
          row.add(10);
          tens--;
          space -= 2;
        } else if (ones > 0 && space >= 1) {
          row.add(1);
          ones--;
          space -= 1;
        } else {
          break;
        }
      }
      if (row.isEmpty) break; // Safety: never loop without progress.
      rows.add(row);
    }
    return rows;
  }

  /// Lays out a stack of [count] coins inside [inner], shrinking the coin size
  /// when the pile would overflow the jar so any amount fits without a cap.
  _JarStackLayout _layoutStack(RRect inner, int count) {
    var unit = inner.width / (_perRow + .55);
    var layout = _layoutWithUnit(inner, count, unit);
    if (layout.height > inner.height * .96) {
      unit *= inner.height * .96 / layout.height;
      layout = _layoutWithUnit(inner, count, unit);
    }
    return layout;
  }

  _JarStackLayout _layoutWithUnit(RRect inner, int count, double unit) {
    final coins = <_JarCoinSlot>[];
    var y = inner.bottom;
    var index = 0;
    for (final row in _rowsFor(count)) {
      var rowUnits = 0;
      var rowHeight = 0.0;
      for (final denom in row) {
        rowUnits += _denomUnits[denom]!;
        final h = unit * _denomDiameter[denom]! * .36;
        if (h > rowHeight) rowHeight = h;
      }
      var x = inner.left + (inner.width - rowUnits * unit * 1.02) / 2;
      for (final denom in row) {
        final diameter = unit * _denomDiameter[denom]!;
        final span = _denomUnits[denom]! * unit * 1.02;
        final jitter = ((index * 37) % 5 - 2) * unit * .07;
        coins.add(
          _JarCoinSlot(
            denom,
            Offset(x + span / 2 + jitter, y - rowHeight * .55),
            diameter / 2,
            diameter * .36,
          ),
        );
        x += span;
        index++;
      }
      y -= rowHeight * .88;
    }
    final height = coins.isEmpty
        ? 0.0
        : inner.bottom - (coins.last.center.dy - coins.last.height * .5);
    return _JarStackLayout(coins, unit, height);
  }

  /// A leaving coin travels in two phases: first it slides across the pile to
  /// the jar's centre line and rises (drawn inside the interior clip), then it
  /// slips out of the slot on the lid, drifts aside and fades (drawn above the
  /// glass). It never falls back into the jar.
  void _drawExit({
    required Canvas canvas,
    required double t,
    required bool clippedPhase,
    required Offset from,
    required double centerX,
    required double bodyTop,
    required double coinRadius,
    required double coinHeight,
    required double side,
    required double drift,
  }) {
    if (t <= 0 || t >= 1) return;
    if (clippedPhase && t >= .5) return;
    if (!clippedPhase && t < .5) return;
    if (t < .5) {
      final u = t / .5;
      final x = lerpDouble(from.dx, centerX, Curves.easeOutCubic.transform(u))!;
      final y = lerpDouble(
        from.dy,
        bodyTop + 1,
        Curves.easeInQuad.transform(u),
      )!;
      _drawCoin(
        canvas,
        Offset(x, y),
        coinRadius,
        flatten: lerpDouble(coinHeight * .5, coinRadius, u),
        spin: (1 - u) * side * 1.2,
        opacity: 1,
      );
    } else {
      final u = (t - .5) / .5;
      final ease = Curves.easeOutCubic.transform(u);
      final x = centerX + side * drift * ease;
      final y = lerpDouble(bodyTop, -8, ease)!;
      _drawCoin(
        canvas,
        Offset(x, y),
        coinRadius,
        spin: side * ease * math.pi * .8,
        opacity: u < .45 ? 1 : 1 - (u - .45) / .55,
      );
    }
  }

  static const _goldHi = Color(0xFFFFF0C4);
  static const _goldLight = Color(0xFFF8CE6B);
  static const _goldMid = Color(0xFFE8A93C);
  static const _goldRim = Color(0xFF9C650F);

  void _drawCoin(
    Canvas canvas,
    Offset center,
    double radius, {
    double spin = 0,
    double opacity = 1,
    double? flatten,
  }) {
    final ry = (flatten ?? radius).clamp(radius * .2, radius);
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: radius * 2,
      height: ry * 2,
    );
    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (spin != 0) canvas.rotate(spin);

    if (ry < radius * .62) {
      // Coin edge (side view): a minted gold band with a lit upper rim.
      canvas.drawOval(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _goldHi.withValues(alpha: opacity),
              _goldLight.withValues(alpha: opacity),
              AppColors.amber.withValues(alpha: opacity),
            ],
            stops: const [0, .42, 1],
          ).createShader(rect),
      );
      canvas.drawArc(
        rect.deflate(.7),
        math.pi * 1.1,
        math.pi * .8,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .8
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: .65 * opacity),
      );
    } else {
      // Coin face: metallic radial sheen with an embossed mint ring.
      canvas.drawOval(
        rect,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-.38, -.42),
            radius: 1.25,
            colors: [
              _goldHi.withValues(alpha: opacity),
              _goldLight.withValues(alpha: opacity),
              _goldMid.withValues(alpha: opacity),
              AppColors.amber.withValues(alpha: opacity),
            ],
            stops: const [0, .38, .72, 1],
          ).createShader(rect),
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: radius * 1.46,
          height: ry * 1.46,
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .8
          ..color = AppColors.amber.withValues(alpha: .5 * opacity),
      );
      // Specular crescent hugging the upper-left rim.
      canvas.drawArc(
        rect.deflate(radius * .14),
        math.pi * 1.02,
        math.pi * .5,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = radius * .17
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: .78 * opacity),
      );
      // Soft reflected light on the lower-right rim.
      canvas.drawArc(
        rect.deflate(radius * .12),
        math.pi * .04,
        math.pi * .3,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = radius * .1
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: .28 * opacity),
      );
      // Sharp glint where the light source hits.
      canvas.drawCircle(
        Offset(-radius * .36, -ry * .38),
        radius * .13,
        Paint()..color = Colors.white.withValues(alpha: .92 * opacity),
      );
    }
    // Dark minted outer rim for definition against the pile.
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _goldRim.withValues(alpha: .8 * opacity),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _JarPainter oldDelegate) => true;
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
                          isLong ? '多' : '空',
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
                    '记录',
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
