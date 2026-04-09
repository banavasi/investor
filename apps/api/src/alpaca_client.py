from alpaca.trading.client import TradingClient
from alpaca.trading.requests import MarketOrderRequest
from alpaca.trading.enums import OrderSide, TimeInForce
from src.config import get_settings


def get_trading_client() -> TradingClient:
    s = get_settings()
    return TradingClient(
        api_key=s.alpaca_api_key,
        secret_key=s.alpaca_secret_key,
        paper=s.alpaca_paper_mode,
    )


def get_account_summary() -> dict:
    account = get_trading_client().get_account()
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
        "pnl_today_pct": round(
            ((equity - last_equity) / last_equity * 100), 2
        ) if last_equity > 0 else 0.0,
        "paper": get_settings().alpaca_paper_mode,
    }


def get_positions() -> list[dict]:
    positions = get_trading_client().get_all_positions()
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


def submit_market_order(symbol: str, notional: float, side: str = "buy") -> dict:
    order = MarketOrderRequest(
        symbol=symbol,
        notional=round(notional, 2),
        side=OrderSide.BUY if side == "buy" else OrderSide.SELL,
        time_in_force=TimeInForce.DAY,
    )
    result = get_trading_client().submit_order(order_data=order)
    return {
        "order_id": str(result.id),
        "symbol": result.symbol,
        "side": result.side.value,
        "notional": str(result.notional),
        "status": result.status.value,
    }