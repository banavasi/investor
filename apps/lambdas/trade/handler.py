"""Lambda handler for trade execution via Alpaca + DynamoDB logging.

Routes:
  GET  /api/account   -> get_account_summary
  GET  /api/positions -> get_positions (Alpaca live positions)
  POST /api/trade     -> submit_market_order + log to DynamoDB
"""

import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "shared"))

from response import error, success
from dynamo import write_trade

from alpaca.trading.client import TradingClient
from alpaca.trading.requests import MarketOrderRequest
from alpaca.trading.enums import OrderSide, TimeInForce


def _get_client() -> TradingClient:
    return TradingClient(
        api_key=os.environ["ALPACA_API_KEY"],
        secret_key=os.environ["ALPACA_SECRET_KEY"],
        paper=os.environ.get("ALPACA_PAPER_MODE", "true").lower() == "true",
    )


def _account_summary() -> dict:
    account = _get_client().get_account()
    equity = float(account.equity)
    last_equity = float(account.last_equity)
    return {
        "status": account.status.value,
        "cash": float(account.cash),
        "portfolio_value": float(account.portfolio_value),
        "buying_power": float(account.buying_power),
        "equity": equity,
        "long_market_value": float(account.long_market_value),
        "pnl_today": round(equity - last_equity, 2),
        "pnl_today_pct": (
            round(((equity - last_equity) / last_equity * 100), 2)
            if last_equity > 0
            else 0.0
        ),
        "paper": os.environ.get("ALPACA_PAPER_MODE", "true").lower() == "true",
    }


def _positions() -> list[dict]:
    positions = _get_client().get_all_positions()
    return [
        {
            "symbol": p.symbol,
            "qty": float(p.qty),
            "avg_entry": float(p.avg_entry_price),
            "current_price": float(p.current_price),
            "market_value": float(p.market_value),
            "unrealized_pl": float(p.unrealized_pl),
            "unrealized_pl_pct": round(float(p.unrealized_plpc) * 100, 2),
        }
        for p in positions
    ]


def _submit_order(body: dict) -> dict:
    symbol = body["symbol"]
    notional = float(body["notional"])
    side = body.get("side", "buy")

    if notional <= 0:
        raise ValueError("Notional must be positive")
    if side not in ("buy", "sell"):
        raise ValueError("Side must be 'buy' or 'sell'")

    order = MarketOrderRequest(
        symbol=symbol,
        notional=round(notional, 2),
        side=OrderSide.BUY if side == "buy" else OrderSide.SELL,
        time_in_force=TimeInForce.DAY,
    )
    result = _get_client().submit_order(order_data=order)
    trade = {
        "order_id": str(result.id),
        "symbol": result.symbol,
        "side": result.side.value,
        "notional": str(result.notional),
        "status": result.status.value,
    }
    write_trade(trade)
    return trade


def handler(event, context):
    method = event.get("requestContext", {}).get("http", {}).get("method", "GET")
    path = event.get("rawPath", "")

    if path.startswith("/api"):
        path = path[4:]

    try:
        if method == "GET" and path == "/account":
            return success(_account_summary())

        if method == "GET" and path == "/positions":
            return success(_positions())

        if method == "POST" and path == "/trade":
            body = json.loads(event.get("body", "{}"))
            return success(_submit_order(body))

        return error(f"Not found: {method} {path}", 404)

    except ValueError as e:
        return error(str(e), 400)
    except Exception as e:
        return error(str(e), 500)
