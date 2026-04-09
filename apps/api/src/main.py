from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from src.alpaca_client import get_account_summary, get_positions, submit_market_order
from src.heartbeat import run_heartbeat, fetch_indicators
from src.dynamo import (
    get_heartbeats_today,
    get_recent_trades,
    get_trades_by_ticker,
    get_pending_alerts,
    get_tracked_positions,
    write_trade,
)

app = FastAPI(title="Trading Copilot API", version="0.1.0")


# --- Health ---
@app.get("/health")
def health():
    return {"status": "ok"}


# --- Alpaca Account ---
@app.get("/account")
def account():
    try:
        return get_account_summary()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/positions")
def positions():
    try:
        return get_positions()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# --- Heartbeat ---
class HeartbeatRequest(BaseModel):
    symbols: list[str] = ["NVDA", "AAPL", "TSLA"]


@app.post("/heartbeat")
def heartbeat(req: HeartbeatRequest):
    """Run heartbeat tick → Gemma 3 classify → persist to DynamoDB."""
    try:
        return run_heartbeat(req.symbols, persist=True)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/heartbeat/indicators-only")
def heartbeat_indicators(req: HeartbeatRequest):
    """Indicators only (no AI, no DynamoDB, no cost)."""
    try:
        return [fetch_indicators(s) for s in req.symbols]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# --- DynamoDB Reads ---
@app.get("/heartbeats/today")
def heartbeats_today():
    """Get all heartbeat snapshots from today."""
    try:
        return get_heartbeats_today()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/alerts/pending")
def pending_alerts():
    """Get all pending trade alerts."""
    try:
        return get_pending_alerts()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/trades")
def trades(limit: int = 20):
    """Get recent trades."""
    try:
        return get_recent_trades(limit)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/trades/{symbol}")
def trades_by_ticker(symbol: str):
    """Get trades for a specific ticker."""
    try:
        return get_trades_by_ticker(symbol.upper())
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/positions/tracked")
def tracked_positions():
    """Get tracked positions (with stop loss, reasoning)."""
    try:
        return get_tracked_positions()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# --- Trade (with DynamoDB logging) ---
class TradeRequest(BaseModel):
    symbol: str
    notional: float
    side: str = "buy"


@app.post("/trade")
def trade(req: TradeRequest):
    """Submit order via Alpaca + log to DynamoDB."""
    if req.notional <= 0:
        raise HTTPException(status_code=400, detail="Notional must be positive")
    if req.side not in ("buy", "sell"):
        raise HTTPException(status_code=400, detail="Side must be 'buy' or 'sell'")
    try:
        result = submit_market_order(req.symbol, req.notional, req.side)
        write_trade(result)
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))