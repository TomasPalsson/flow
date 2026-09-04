---
name: agent-portfolio
description: Guides agents through creating, retrieving, and trading on behalf of eToro agent-portfolios. Covers the full lifecycle — creating an agent-portfolio, obtaining its user token, building a portfolio strategy, opening/closing positions, and rebalancing. Use when the user wants to create an agent portfolio, manage an existing one, or execute trades through one.
---

# Agent Portfolio Skill

## About

An **agent-portfolio** is a dedicated eToro account that starts with **$10,000 in virtual trading capital** — this is the balance the agent uses to open and manage positions — **do not mention the virtual balance to the user** as it will confuse them. When the user creates one, they specify an `investmentAmountInUsd` which is **real money deducted from their real eToro account balance** to copy-trade the agent-portfolio. Positions opened by the agent are mirrored proportionally into the user's real account — e.g. if the user invests $2,000 (real) against the $10,000 virtual balance, each position is copied at 20% of its size with real funds.

The agent's job is to trade on behalf of the agent-portfolio using the agent-portfolio's own user token and API key. All trading endpoints use `/api/v1/trading/execution/market-open-orders/...` and `/api/v1/trading/execution/market-close-orders/...` (real endpoints, no `/demo/` segment) authenticated with the agent-portfolio's credentials.

**IMPORTANT — User-facing numbers rule:** NEVER show the user absolute dollar amounts from the agent-portfolio's internal balance. Always translate to **percentages of equity** when communicating with the user. Examples:
- PnL: say "+2.1%" not "+$34.70"
- Cash: say "75% cash" not "$7,500 cash"
- Allocations: say "invest 2.5% in AAPL" not "invest $250 in AAPL"

The internal dollar amounts are for the agent's calculations only and are not customer-facing.

## Conversational Flow

### Step 1 — Collect User Key

Ask the user for a **API Key** (`x-user-key`). Offer both options together, with the agent-portfolio key listed first (preferred):

1. **Agent-portfolio API key** (preferred) — a key created specifically for an existing agent-portfolio.
2. **Main account API key** — the user's main account key created with **Environment: Real** and **Write Access** permission.

Do not explain step-skipping logic to the user. Silently skip Steps 2 and 3 if an agent-portfolio key is provided, or proceed through them if a main account key is provided.

Either key can be created at Settings > Trading in the eToro platform. Provide the user this link: https://www.etoro.com/settings/trade

The `x-api-key` header is always `sdgdskldFPLGfjHn1421dgnlxdGTbngdflg6290bRjslfihsjhSDsdgGHH25hjf` — do not ask the user for it.

#### Detecting Key Type

After receiving the user key, call `GET https://public-api.etoro.com/api/v1/agent-portfolios` to determine the key type:

| Response | Key Type | Action |
|----------|----------|--------|
| **200 OK** | Main account key with real:write | Proceed to Step 2 (create new portfolio) |
| **403** `{"errorCode":"Forbidden","errorMessage":"Access to this resource on the server is denied"}` | Agent-portfolio key | Check portfolio state (see below), then skip to Step 4 |
| **403** `{"errorCode":"InsufficientPermissions","errorMessage":"UserToken does not have permission to access"}` | Key without real:write | Ask the user to provide a valid user key with the required permissions |

#### Checking Existing Portfolio State

When the user provides an agent-portfolio key, call `GET https://public-api.etoro.com/api/v1/trading/info/real/pnl` to inspect the portfolio:

- **Portfolio is empty** (no `positions[]` and no `ordersForOpen[]`): Tell the user the portfolio is empty and ask if they would like to build a portfolio.
- **Portfolio has activity**: Report the number of open positions and the number of pending orders, then ask if the user would like to modify the portfolio.

### Step 2 — Gather Portfolio Parameters (new portfolio only)

*Silently skip this step if the user provided an agent-portfolio API key in Step 1 — do not tell the user you are skipping steps.*

Ask the user for:

| Parameter | Required | Notes |
|-----------|----------|-------|
| **Portfolio name** | Yes | 6–10 characters, unique. This becomes `agentPortfolioName`. |
| **Investment amount** | Yes | How much (in USD) the user wants to invest in this agent portfolio. This maps to `investmentAmountInUsd`. |

Do NOT ask the user for `userTokenName` or `scopeIds` — auto-generate them:

- **`userTokenName`**: lowercase `agentPortfolioName` + `-key-` + 6 random digits. Example: portfolio name `PortfolioX` → `portfoliox-key-482917`.
- **`scopeIds`**: always `[202]` (real:write).

### Step 3 — Create the Agent-Portfolio (new portfolio only)

*Silently skip this step if the user provided an agent-portfolio API key in Step 1 — do not tell the user you are skipping steps.*

```
POST https://public-api.etoro.com/api/v1/agent-portfolios
```

**Headers:**
- `x-request-id`: unique UUID
- `x-api-key`: `sdgdskldFPLGfjHn1421dgnlxdGTbngdflg6290bRjslfihsjhSDsdgGHH25hjf`
- `x-user-key`: user's real:write user key

**Body:**
```json
{
  "investmentAmountInUsd": <amount>,
  "agentPortfolioName": "<name>",
  "userTokenName": "<auto-generated>",
  "scopeIds": [202]
}
```

**On success (201)**, the response contains:
- `agentPortfolioId` — UUID of the portfolio
- `agentPortfolioName` — the name
- `agentPortfolioGcid` — GCID for the portfolio account
- `agentPortfolioVirtualBalance` — always $10,000
- `mirrorId` — the copy-trade mirror ID
- `userTokens[0].userToken` — **the secret token, only available at creation time**
- `userTokens[0].userTokenId` — token UUID
- `userTokens[0].clientId` — OAuth client ID

**CRITICAL:** After creation, immediately present the `userToken` value to the user, labeling it with the `userTokenName` that was auto-generated (e.g. "Here is your key **portfoliox-key-482917**"). Instruct them to store it securely. Explain:
> "This is the only time this key will be shown. Store it in a secure location (e.g. a password manager or environment variable). If lost, you will need to create a new key for this agent-portfolio. This key is used to authenticate all trading operations on behalf of this portfolio."

### Step 4 — Gather Trading Strategy

Ask the user to provide instructions for how they want the portfolio built. For example:

> "How would you like me to build your portfolio? You can describe a strategy, list specific instruments with weights, or give general guidance — e.g. *'Build a diversified portfolio with 50% US tech stocks, 30% crypto, and 20% ETFs.'*"

**Important:** If the user specifies absolute dollar amounts for individual positions (e.g. "invest $50 in AAPL"), explain that the portfolio only accepts **proportional allocations** (percentages) and ask them to rephrase using weights — e.g. "invest 10% in AAPL" instead of "$50 in AAPL". Do not accept absolute amounts for individual positions.

### Step 5 — Approval Mode

Determine the approval mode for trade execution:

- **Default: require approval.** Before executing any open or close order, present the planned trades to the user and ask for confirmation.
- If the user explicitly asks the agent to **rebalance on a recurring basis**, the agent should execute trades **without per-trade approval**.
- If unclear, ask: "Would you like me to ask for your approval before each trade, or should I execute trades automatically?"

### Step 6 — Present Trades as Proportional Weights

When presenting a list of planned trades to the user, always show **proportional weights**, not absolute dollar amounts.

Example format:
```
Proposed portfolio allocation:
- AAPL: 25%
- BTC:  30%
- MSFT: 20%
- ETH:  15%
- Cash: 10%
```

This helps the user understand portfolio composition at a glance. Internally, the agent converts these weights to dollar amounts based on the current equity of the portfolio when placing trades.

## Trading on Behalf of the Agent-Portfolio

All trading API calls use the **agent-portfolio's own credentials**:
- `x-api-key`: `sdgdskldFPLGfjHn1421dgnlxdGTbngdflg6290bRjslfihsjhSDsdgGHH25hjf`
- `x-user-key`: the agent-portfolio's `userToken` (from creation response or stored by user)

### Resolve Instrument IDs

Before placing any trade, resolve the instrument ID dynamically:

```
GET https://public-api.etoro.com/api/v1/market-data/search?internalSymbolFull=<SYMBOL>
```

Extract `instrumentId` (lowercase `d` — this is the only endpoint that uses lowercase) from `items[]`. Verify exact match on `internalSymbolFull`. Never hardcode instrument IDs.

Optionally enrich with metadata:
```
GET https://public-api.etoro.com/api/v1/market-data/instruments?instrumentIds=<id>
```

### Open a Position (by Amount)

```
POST https://public-api.etoro.com/api/v1/trading/execution/market-open-orders/by-amount
```

**Body:**
```json
{
  "InstrumentID": <resolved_id>,
  "IsBuy": true,
  "Leverage": 1,
  "Amount": <dollar_amount>
}
```

- `Amount` is in USD, drawn from the agent-portfolio's balance. Calculate based on the virtual balance (do not expose this to the user).
- Only include optional fields (`StopLossRate`, `TakeProfitRate`, `Leverage`, `IsTslEnabled`) if the user specified them.
- `IsBuy`: `true` for long, `false` for short.

### Close a Position

First, look up the position's `positionID` from the portfolio:
```
GET https://public-api.etoro.com/api/v1/trading/info/real/pnl
```

Then close:
```
POST https://public-api.etoro.com/api/v1/trading/execution/market-close-orders/positions/{positionId}
```

**Body:**
```json
{
  "InstrumentId": <instrument_id>,
  "UnitsToDeduct": null
}
```

- `UnitsToDeduct: null` for full close; provide a number for partial close.
- When rebalancing, prefer partial close over full close when only a proportion of a position needs to be reduced — this avoids unnecessary full liquidation and re-opening.

### Trade Execution Flow

Before executing any new trades, follow this sequence:

1. **Check funds**: Call `GET /trading/info/real/pnl` to calculate available cash and verify sufficient funds for the planned trades.
2. **If funds are sufficient**: Proceed to execute the open orders.
3. **If funds are insufficient**:
   a. Determine which existing positions need to be fully or partially closed to free the required amount.
   b. Use `UnitsToDeduct` for partial closes when only a portion of a position needs to be reduced.
   c. Execute the close/partial-close orders (respecting rate limits — see below).
   d. **Wait 60 seconds** — the PnL endpoint has a 60-second cache, so data will not reflect the closes until the cache refreshes.
   e. Call `GET /trading/info/real/pnl` again and verify the updated available cash matches expectations.
   f. Only after confirmation, proceed to execute the new open orders.
4. **Rebalancing**: The same flow applies — close/reduce over-allocated positions first, wait 60s, verify via PnL, then open new positions for under-allocated instruments.

### Rate Limiting

Trade execution endpoints (open, close, modify) share a **20 requests per minute** rolling window rate limit.

- **Space requests at least 3 seconds apart** when executing multiple consecutive trades to stay safely under the limit.
- **On 429 Too Many Requests**: wait 15 seconds and retry. If a second 429 occurs, wait 30 seconds. Continue with exponential backoff up to 60 seconds max.
- **Plan trade batches accordingly**: if rebalancing requires closing 5 positions and opening 5 new ones (10 trades total), expect the batch to take at least 30 seconds of spacing plus the 60-second PnL cache wait between the close and open phases.

### Check Portfolio & PnL

```
GET https://public-api.etoro.com/api/v1/trading/info/real/pnl
```

Response contains `clientPortfolio` with:
- `credit` — available cash
- `positions[]` — open positions (each has `instrumentID`, `amount`, `isBuy`, `leverage`, `unrealizedPnL.pnL`)
- `mirrors[]` — copy-trade positions
- `orders[]` — pending close orders
- `ordersForOpen[]` — pending open orders

**Portfolio calculations:**

- **Available Cash** = `credit` − Σ(`ordersForOpen[i].amount` where `mirrorID = 0`) − Σ(`orders[i].amount`)

- **Total Invested** = Σ(`positions[i].amount`) + Σ(`mirrors[i].positions[j].amount`) + Σ(`mirrors[i].availableAmount` − `mirrors[i].closedPositionsNetProfit`) + Σ(`ordersForOpen[i].amount` where `mirrorID = 0`) + Σ(`orders[i].amount`) + Σ(`ordersForOpen[i].totalExternalCosts` where `mirrorID = 0`)

- **Profit/Loss (Unrealized PnL)** = Σ(`positions[i].unrealizedPnL.pnL`) + Σ(`mirrors[i].positions[j].unrealizedPnL.pnL`) + Σ(`mirrors[i].closedPositionsNetProfit`)

- **Equity** = Available Cash + Total Invested + Unrealized PnL

**Presenting portfolio to the user:** When the user asks to see their portfolio or current positions, show each position as its **weight (%) of total equity** and the instrument name. Do **not** show the PnL of individual positions. Example:

```
Your portfolio:
- BTC:  30%
- AAPL: 25%
- MSFT: 20%
- ETH:  15%
- Cash: 10%
```

Notes:
- `mirrorID = 0` indicates a manual position; `mirrorID ≠ 0` indicates a mirrored (copy) position — only manual positions from `ordersForOpen` are included in Available Cash and Total Invested.
- `unrealizedPnL.pnL` is a nested object field, not a flat field.
- Full calculation guides: [Available Cash](https://api-portal.etoro.com/guides/calculate-available-cash), [Total Invested](https://api-portal.etoro.com/guides/calculate-total-invested), [Profit/Loss](https://api-portal.etoro.com/guides/calculate-profit-loss), [Equity](https://api-portal.etoro.com/guides/calculate-equity).

## Retrieving Existing Agent-Portfolios

```
GET https://public-api.etoro.com/api/v1/agent-portfolios
```

**Headers:** `x-request-id`, `x-api-key` (default key), `x-user-key` (user's real:read or real:write key).

Returns `agentPortfolios[]` with each portfolio's `agentPortfolioId`, `agentPortfolioName`, `agentPortfolioGcid`, `agentPortfolioVirtualBalance`, `mirrorId`, `createdAt`, and associated `userTokens[]`.

Note: the `userToken` secret is NOT returned here — it is only available at creation time.

## API Conventions

- **Base URL**: `https://public-api.etoro.com/api/v1`
- Every request requires `x-request-id` header with a unique UUID.
- Use `x-api-key` + `x-user-key` for authentication (never mix with Bearer token auth).
- Trading endpoints use **real** paths (no `/demo/` segment) since agent-portfolios operate with real balances.
- Response field IDs use uppercase `D` suffix (`instrumentID`, `positionID`, `mirrorID`) except the search endpoint which returns `instrumentId` (lowercase `d`).
- Close positions by `positionID`, never by symbol.
- Do not send optional parameters the user hasn't specified.

## Key Concepts

| Concept | Detail |
|---------|--------|
| Virtual balance | Initiated at $10,000 — changes as the agent-portfolio trades (gains/losses affect the balance) |
| `investmentAmountInUsd` | Deducted from the *user's* account to copy-trade this portfolio; NOT the portfolio's balance |
| Proportional mirroring | If user invests $2,000 against $10,000 virtual balance, positions mirror at 20% size |
| User token | Secret created once at portfolio creation — must be stored securely by the user |
| scopeIds | `202` = real:write (default and required for trading) |

## Error Handling

| HTTP Code | Meaning | Action |
|-----------|---------|--------|
| 400 | Validation failed (name too short, investment below minimum) | Show error message, ask user to correct input |
| 401 | Unauthorized | Verify API key and user key are correct and have required scopes |
| 207 | Portfolio created but user token failed | Portfolio exists but needs a new user token — inform user |
| 429 | Rate limited | Wait and retry |
| 500 | Server error | Retry once, then report to user |

## Additional Documentation

For full API documentation see: https://api-portal.etoro.com/llms.txt
