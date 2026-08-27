# AI 巴菲特炒股助手 — 软件设计方案

> 技术栈：**macOS 原生 SwiftUI**（部署目标 macOS 26.4，Xcode 26.4，Swift 5）。UI 风格参考苹果「股市」App。覆盖**美股 + A股**，量化引擎 + Claude 语义分析，v1 不做真实下单。

---

## 1. 需求范围（v1）

| 功能 | 说明 |
|---|---|
| 个股巴菲特分析报告 | 输入任意代码（美股 ticker / A股 6位代码），输出中文「巴菲特健康报告」：量化分项评分、DCF 内在价值与安全边际、买入/观望/回避结论、Claude 护城河与管理层分析 |
| 全市场筛选器 | 按巴菲特过滤条件在配置的股票池上筛选，按评分排序；A股用东方财富全市场粗筛→财务精筛，美股用精选池 |
| 自选股 + 持仓跟踪 | SwiftData 持久化自选列表与持仓（数量/成本），价格与评分刷新，组合级巴菲特健康度 |
| 设置 | Anthropic API Key（Keychain）、FMP Key（Keychain）、Claude 模型选择、涨跌颜色习惯、刷新 |

**非目标**：真实下单、盘中高频交易、技术指标买卖信号。

---

## 2. 总体架构

```
┌─ Views ──────────────────────────────────────────────┐
│ SwiftUI（中文，Apple Stocks 风格）                    │
│  NavigationSplitView：看板/自选/持仓/筛选/设置        │
└──────────────┬──────────────────────────────────────┘
               │ @Observable ViewModel
┌─ Services ── ▼ ──────────────────────────────────────┐
│ MarketDataService（外观：路由/缓存/限速/日配额）       │
│ ClaudeClient（Anthropic Messages API）                │
│ KeychainStore（API Key）                              │
└──────────────┬──────────────────────────────────────┘
┌─ Domain ──── ▼ ──────────────────────────────────────┐
│ BuffettEngine（量化评分，nonisolated 纯函数）          │
│ DCF（内在价值 + 安全边际）                             │
└──────────────┬──────────────────────────────────────┘
┌─ Data ────── ▼ ──────────────────────────────────────┐
│ MarketDataProvider 协议                               │
│  ├ YahooPriceProvider         (美股 价格/历史，免Key) │
│  ├ FMPFundamentalsProvider    (美股 财务，FMP免费档)  │
│  ├ EastmoneyQuote/KlineProvider(A股 行情/K线，免鉴权) │
│  ├ EastmoneyFundamentalsProvider(A股 F10年报财务)     │
│  ├ EastmoneyUniverseProvider  (A股 全市场粗筛)        │
│  └ CuratedUSUniverse          (美股 精选池 ~50只)     │
│ RateLimiter（令牌桶）/ DataCache（TTL）               │
└──────────────┬──────────────────────────────────────┘
┌─ Persistence ─ ▼ ────────────────────────────────────┐
│ SwiftData @Model（nonisolated）：WatchItem/Holding/   │
│   AnalysisReport/CachedQuote 等；单 ModelContainer    │
└──────────────────────────────────────────────────────┘
```

**分层原则**：
- Views 只依赖 `MarketDataService` 与 SwiftData 模型，不直接碰网络协议；
- Provider 通过协议解耦，每个市场一套适配器，由 `Symbol.market` 路由；
- 引擎/估值是纯函数，天然可单元测试。

---

## 3. 数据层

### 3.1 协议

```swift
protocol PriceProvider: Sendable {
    func quote(for symbol: Symbol) async throws -> Quote
    func priceHistory(for symbol: Symbol, range: PriceRange) async throws -> [PriceBar]
}
protocol FundamentalsProvider: Sendable {
    func fundamentals(for symbol: Symbol) async throws -> FundamentalsBundle
}
protocol UniverseProvider: Sendable {
    func universe() async throws -> [ScreenerRow]
}
```

### 3.2 美股

| 数据 | 来源 | 说明 |
|---|---|---|
| 价格/历史/52周高低 | Yahoo v8 chart `query1.finance.yahoo.com/v8/finance/chart/{ticker}?interval=1d&range=10y` | **免 Key、免 crumb**；必须带 `User-Agent: Mozilla/5.0` 否则 403；备用主机 query2 |
| 基本面（ROE/负债/利润率/FCF/EPS） | FMP 免费档 `/api/v3/income-statement|balance-sheet-statement|cash-flow-statement|financial-ratios/{sym}?period=annual&limit=10` | **250 次/天、5 年历史**、需注册免费 Key、`/stock-screener` 为付费 |
| 10 年财务（探针） | Yahoo crumb 握手：`fc.yahoo.com` 取 cookie → `/v1/test/getcrumb` → `v10/quoteSummary` + `fundamentals-timeseries` | 家用 IP 可行则启用；数据中心 IP 401。**v1 基于 FMP 5 年 + coverageYears 缩放** |

### 3.3 A股（东方财富，免鉴权、无 SLA）

| 数据 | 来源 | 关键点 |
|---|---|---|
| 实时行情 | `push2.eastmoney.com/api/qt/stock/get?secid=..&fltt=2&invt=2&fields=f43,f58,f60,f162,f167,f116,f169` | secid：`1.`+沪/科创、`0.`+深/创业板（如 `1.600519`、`0.000001`） |
| K线历史 | `push2his.eastmoney.com/api/qt/stock/kline/get?secid=..&klt=101&fqt=1&beg=19900101&end=20500101` | **字段序坑**：date,open,**close(f53)**,high,low |
| 年报财务 | `datacenter.eastmoney.com/securities/api/data/v1/get?reportName=RPT_F10_FINANCE_MAINFINADATA&filter=(SECUCODE="600519.SH")&...&pageSize=40` | 年+季混合 → **客户端过滤 REPORT_DATE 以 `-12-31` 结尾**；列名实现时实测（ROEJQ/XSMLL/XSJLL/ZCFZL/EPSJB/BPS/PARENTNETPROFIT） |
| 全市场粗筛 | `push2.eastmoney.com/api/qt/clist/get?pn=N&pz=100&fields=f12,f14,f2,f3,f9,f115,f23,f20` | 翻页；f12代码/f14名称/f9动态PE/f115 PE_TTM/f23 PB/f20总市值 |

### 3.4 限速与缓存

- `RateLimiter` 令牌桶：Yahoo ~1 请求/秒、Eastmoney ≥1 请求/秒（被断开则退避）、FMP ≤10 请求/秒 + **日配额 250 硬顶**
- `DataCache` TTL：行情 1–5 分钟（盘中）/ 财务 24h / 历史 24h / 股票池 24h；分析报告持久化
- UI 显示「今日 FMP 剩余配额」，避免中途停摆

---

## 4. 领域层（巴菲特引擎）

```swift
nonisolated struct BuffettEngine {
    static func analyze(_ f: FundamentalsBundle, price: Double) -> BuffetScore
}
```

- 输入已是 `FundamentalsBundle` 归一化的逐年快照（revenue/netIncome/eps/roe/netMargin/grossMargin/debtEquity/debtToAsset/interestCoverage/fcf/marketCap/year），**一套引擎通吃美股与 A股**
- 5 个维度（财务质量25 / 资产负债表20 / 盈利稳定与增长20 / 现金流15 / 估值与安全边际20）各算 0–100 分 → 加权总分
- `DCFValuation`：两阶段 DCF（见 STRATEGY §3），输出 `intrinsicValue`、`marginOfSafety`
- `BuffetScore` 输出：分项分 + 理由字符串、总分、内在价值、安全边际、**结论（买入区间/观望/回避）**、`coverageYears`
- 金融股（银行/保险/券商，按行业分类）豁免 D/E、资产负债率标准

---

## 5. AI 层（Claude 集成）

- `ClaudeClient`：`URLSession` 直连 `POST https://api.anthropic.com/v1/messages`
  - 头：`x-api-key`（Keychain）、`anthropic-version: 2023-06-01`、`Content-Type: application/json`
  - 模型：默认 `claude-opus-5`，设置可切 `claude-sonnet-5`（省钱档）
  - **不传** `temperature/top_p/budget_tokens`（Opus/Sonnet 5 会 400 拒绝）；`max_tokens≈16000`；超时 60–120s
  - 处理 `stop_reason == "refusal"` 为友好中文错误
- `BuffettAnalysisPrompts`：稳定中文 **system** 提示词（巴菲特框架 + "你是定性分析，不得更改量化结论"），带 `cache_control` 缓存；**user** 消息为结构化 Markdown（10 年财务表 + 分项评分 + 结论 + 价格/安全边际），请求中文定性分析
- **渲染策略**：量化结果立即渲染；Claude 报告异步补充；**API 失败不影响量化展示**

---

## 6. 持久化（SwiftData）

- `@Model` 实体：`WatchItem`（自选）、`Holding`（持仓：数量/成本/买卖记录）、`AnalysisReport`（量化+AI 报告快照）、`CachedQuote`（行情缓存）
- 单 `ModelContainer`，主线程 `mainContext`（v1 不用 @ModelActor）
- **Xcode 26 默认 MainActor 隔离**：所有 `@Model` 标 `nonisolated`；不跨隔离域传模型实例（跨域传 `persistentModelID`）
- 需要 API Key：`KeychainStore`（`SecItemAdd/CopyMatching/Update`），沙盒下默认可访问，遇 `errSecMissingEntitlement(-34018)` 再加 keychain-access-groups

---

## 7. UI 设计（参考苹果「股市」App）

- **导航**：`NavigationSplitView` 侧栏（看板/自选/持仓/筛选/设置）+ 主区详情
- **列表行**：symbol + 中文公司名 + 现价 + 日涨跌幅（颜色标记，居中右对齐）
- **详情页**：
  - 顶部：大字号现价 + 涨跌幅 + 公司名 + 市场标签
  - 交互式 K 线/折线（Swift Charts）：时间区间 1D/1W/1M/3M/1Y/全，十字准星
  - 关键指标网格（PE/PB/ROE/负债率/市值/52周高低）
  - 巴菲特评分：分维度进度条 + 总分 + 结论徽章
  - AI 分析报告：Markdown 渲染（护城河/管理层/风险 + 自然语言报告）
- **涨跌颜色**：默认按市场自适应（美股绿涨/红跌，A股红涨/绿跌），设置可全局切换
- **风格**：SF Symbols、系统 Material、深浅色自适应、圆角卡片、无衬线数字字体（monospacedDigit）

---

## 8. 分阶段实施与里程碑

| 阶段 | 内容 | 验收 |
|---|---|---|
| P0 | 文档 | STRATEGY.md / DESIGN.md |
| P1 | 脚手架 + 美股价格 | App 可启动、沙盒出网、AAPL 实时价 |
| P2 | 美股财务 + 引擎 + Claude + 报告页 | AAPL 完整中文报告（量化+AI） |
| P3 | A股适配器 | 600519 人民币报告 |
| P4 | 自选 + 持仓 | 组合健康度仪表盘 |
| P5 | 全市场筛选器 | 可筛选排序 |
| P6 | 打磨 | 图表交互/错误态/深浅色 |

## 9. 已知风险

- Yahoo/FMP/东方财富均为**免费接口，无 SLA**，可能变动；统一经 Provider 协议隔离，便于替换
- FMP 5 年历史 < 巴菲特 10 年判定目标 → coverageYears 缩放 + 报告标注局限
- 东方财富公开接口高频访问会被封 IP → 强限速 + 缓存
- 沙盒出网必须配置 `com.apple.security.network.client`
