# Stocks — AI 巴菲特炒股助手

macOS 原生 SwiftUI 应用，苹果「股市」App 风格，中文界面。量化引擎（确定性、可解释）+ Claude 语义分析，同时支持 **美股 + A股**。

> ⚠️ **仅分析与跟踪，不接入真实下单 / 券商。** 本应用产出的任何评分、结论、内在价值均为辅助决策参考，不构成投资建议。

---

## 功能

| 模块 | 说明 |
|---|---|
| 📊 个股分析报告 | 行情 + 历史 K 线（交互式十字线）+ 财务数据 + 巴菲特量化评分（5 维度分项）+ Claude 中文定性分析 |
| 🔍 全市场筛选器 | A股 全市场 5500+ 只 clist 粗筛（PE / PB / 市值）+ 引擎深筛排序；美股 curated 池 |
| ⭐ 自选股 | SwiftData 本地保存，实时行情刷新，点按进入报告 |
| 💰 持仓跟踪 | 数量 × 成本，实时盈亏、组合总市值 / 总盈亏 |
| 🌏 双市场 | 美股（绿涨红跌）与 A股（红涨绿跌）涨跌颜色自适应 |

### 巴菲特量化引擎（确定性，Claude 不覆盖只解释）

| 维度 | 权重 |
|---|---|
| 财务质量（ROE、净利率） | 25% |
| 资产负债表（负债率，金融股豁免） | 20% |
| 盈利稳定与增长（无亏损年、EPS 增长） | 20% |
| 现金流（FCF 为正、FCF/净利润） | 15% |
| 估值与安全边际（PE/PB + DCF） | 20% |

结论判定：**买入区间 / 观望 / 回避 / 数据不足**。DCF 为两阶段模型（g = min(FCF 复合增速, 8%)、折现 10%、永续 2.5%、含净现金）。

策略细节见 [docs/STRATEGY.md](docs/STRATEGY.md)，架构与数据源实测记录见 [docs/DESIGN.md](docs/DESIGN.md)。

---

## 环境要求

- Xcode 26.4+，macOS 26.4+（SwiftUI + Swift Charts + SwiftData）
- App Sandbox 已启用，含 `com.apple.security.network.client` 网络权限（`Stocks/Stocks.entitlements`）

## 构建

```bash
xcodebuild -project Stocks.xcodeproj -scheme Stocks build
```

或直接用 Xcode 打开 `Stocks.xcodeproj` 运行。

## 配置（可选）

API Key 仅存本机 **Keychain**（设置页填写），不落盘明文：

| 项目 | 必填? | 用途 |
|---|---|---|
| Anthropic API Key | 选填 | Claude 语义分析。不填则量化评分照常可用，AI 报告跳过 |
| Alpha Vantage Key | 选填（美股） | 美股财务数据（免费档 25 次/天）。A股 财务走东方财富免 Key |

## 数据源（中国大陆网络实测可用）

- **东方财富**（免 Key）：A股 + 美股行情 / 历史 K 线 / 年报财务（F10）/ 全市场股票池
- **Alpha Vantage**：美股财务（INCOME / BALANCE / CASH_FLOW）
- **Claude API**：`api.anthropic.com` 定性分析

## 测试

引擎与 DCF 单元测试为 standalone Swift 脚本（不依赖 Xcode target），`Tests/` 在仓库根：

```bash
cd Tests && swiftc BuffettEngineTests.swift ../Stocks/Engine/DCF.swift ../Stocks/Engine/BuffettEngine.swift ../Stocks/Domain/*.swift -o /tmp/engine_tests && /tmp/engine_tests
```

## 免责声明

本应用仅用于个人学习与研究。投资有风险，决策需谨慎，据此操作盈亏自负。

---

MIT License
