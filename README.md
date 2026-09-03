# CryptoPilot

CryptoPilot 是一款面向加密货币交易者的 AI 辅助分析应用。它不提供买卖喊单，而是帮助用户理解多周期行情、识别仓位风险并复盘交易行为。

> Trade with Data, Not Emotion.

## 当前版本

这个仓库包含可运行的 Flutter V1 体验，当前覆盖：

- BTC / ETH 行情快照与资产切换
- 首页开仓价格、动态止损止盈与盈亏比计算
- 可本机保存并编辑盈亏结果的开仓记录
- AI 多周期趋势分析
- 关键支撑与压力地图
- 可交互的仓位风险评分
- 结构化 AI 问答
- 每日交易复盘、行为模式与交易规则

当前行情和交易记录由本地演示数据提供，数据访问被隔离在 `MarketRepository` 后，便于后续接入 REST、WebSocket、交易所账户与 AI 服务。

## 运行

```bash
flutter pub get
flutter run
```

## 检查

```bash
flutter analyze
flutter test
flutter build web --release
```

## 代码结构

```text
lib/
  core/       主题、设计令牌和共享组件
  data/       行情数据实现
  domain/     市场快照领域模型
  features/   首页、行情、AI、风险、复盘与个人中心
```

产品中的分析只用于辅助决策，不构成投资建议。
