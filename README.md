# ichimoku-grok

An MT5 Expert Advisor built by prompting Grok for iterative modifications. Trades precious metals (Gold, Silver) using full Ichimoku alignment across multiple timeframes, organized into three conviction tiers.

## Strategy

The EA checks for complete Ichimoku alignment across all required timeframes before entering a trade. Both price and the Chikou Span must be clear of the cloud, Tenkan, and Kijun on every timeframe in the tier.

### Conviction Tiers

| Tier | Alignment Required | Positions | Risk | Exit TF |
|------|--------------------|-----------|------|---------|
| Full | MN → M1 (all 9 TFs) | 3x | 2% | M15 break |
| H4   | H4 → M1 (6 TFs)    | 3x | 1% | M5 break  |
| H1   | H1 → M1 (5 TFs)    | 1x | 0.5% | M1 break |

- Higher tiers take priority — H4 and H1 tiers only activate when no higher tier is active for that symbol.
- Exits are tier-specific: each tier exits when its designated exit timeframe breaks alignment.

## Inputs

| Parameter | Default | Description |
|-----------|---------|-------------|
| `Symbols` | `GOLD,XAUUSD,SILVER,XAGUSD` | Comma-separated symbols to trade |
| `Tenkan` | 9 | Tenkan-sen period |
| `Kijun` | 26 | Kijun-sen period |
| `SenkouB` | 52 | Senkou Span B period |
| `RiskFullPct` | 2.0 | % account risk for Full tier |
| `RiskH4Pct` | 1.0 | % account risk for H4 tier |
| `RiskH1Pct` | 0.5 | % account risk for H1 tier |
| `RiskRefSL` | 1000 | Reference stop-loss in points (used for lot sizing) |
| `ATRPeriod` | 14 | ATR period for hard stop-loss placement |
| `RiskATRMult` | 3.0 | ATR multiplier for hard stop-loss distance |
| `Slippage` | 30 | Max slippage in points |

## Requirements

- MetaTrader 5
- Symbols must be available in Market Watch
- Sufficient historical data for all timeframes (MN down to M1)

## Notes

- The EA recovers open position state on restart via magic numbers.
- Alerts and push notifications are sent on entry and exit signals.
- Lot sizing is calculated per-tier based on account balance, reference SL, and tick value.
