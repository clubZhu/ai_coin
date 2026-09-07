# CryptoPilot

CryptoPilot 是一款面向加密货币交易者的 AI 辅助分析应用。它不提供买卖喊单，而是帮助用户理解多周期行情、识别仓位风险并复盘交易行为。

> Trade with Data, Not Emotion.

## 当前版本

这个仓库包含可运行的 Flutter V1 体验，当前覆盖：

- BTC / ETH / ZEC / BNB 行情快照与资产切换
- 首页按照开仓计算器布局展示价格、实际开仓数量、杠杆和动态止损止盈金额
- 可本机保存并编辑盈亏结果的开仓记录，支持输入实际 USDT 盈亏金额、同步换算比例，并导出 CSV 分享
- AI 多周期趋势分析
- 关键支撑与压力地图
- 可交互的仓位风险评分
- 结构化 AI 问答
- 每日交易复盘、行为模式与交易规则

首页价格使用币安公共 WebSocket；行情页通过币安 REST 获取快照和 K 线，并订阅实时价格。开仓记录由用户手动创建并保存在本机，可通过 Android 系统分享面板导出 CSV，不代表交易所真实下单；AI 分析等演示模块仍使用本地示例数据。

## 运行

```bash
flutter pub get
flutter run
```

## 检查

常规界面修改按用户约定，以 Android 编译通过为默认验证方式：

```bash
flutter build apk --debug
```

## UI 规范

后续界面开发必须遵循 [统一 UI 规范](docs/ui-style-guide.md)。颜色、文字层级、间距、卡片、导航、弹窗和数据状态以该文档为准；协作执行要求见 [AGENTS.md](AGENTS.md)。

## 代码结构

```text
lib/
  core/       主题、设计令牌和共享组件
  data/       行情数据实现
  domain/     市场快照领域模型
  features/   首页、行情、AI、风险、复盘与个人中心
```

产品中的分析只用于辅助决策，不构成投资建议。

Android 版本采用 edge-to-edge 系统栏：顶部时间正常显示，底部导航区域保持透明并与页面背景融合。
