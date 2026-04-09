import boto3
from datetime import datetime, timedelta, timezone
from src.config import get_settings


def get_table():
    settings = get_settings()
    dynamodb = boto3.resource("dynamodb", region_name=settings.aws_region)
    return dynamodb.Table(settings.table_name)


# --- Heartbeat Snapshots ---

def write_heartbeat(snapshot: dict):
    """Write a heartbeat tick to DynamoDB."""
    table = get_table()
    now = datetime.now(timezone.utc)
    date_str = now.strftime("%Y-%m-%d")
    time_str = now.strftime("%H:%M:%S")

    table.put_item(Item={
        "PK": f"DATE#{date_str}",
        "SK": f"HB#{time_str}#{snapshot['symbol']}",
        "symbol": snapshot["symbol"],
        "price": str(snapshot.get("price", 0)),
        "rsi_14": str(snapshot.get("rsi_14", 0)),
        "macd": str(snapshot.get("macd", 0)),
        "ema_9": str(snapshot.get("ema_9", 0)),
        "ema_21": str(snapshot.get("ema_21", 0)),
        "ai_signal": snapshot.get("ai_signal", "none"),
        "ai_confidence": snapshot.get("ai_confidence", 0),
        "ai_reason": snapshot.get("ai_reason", ""),
        "model": snapshot.get("model", ""),
        "timestamp": now.isoformat(),
        "expires_at": int((now + timedelta(days=7)).timestamp()),  # TTL: 7 days
    })


def get_heartbeats_today() -> list[dict]:
    """Get all heartbeat snapshots from today."""
    table = get_table()
    date_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    response = table.query(
        KeyConditionExpression="PK = :pk AND begins_with(SK, :prefix)",
        ExpressionAttributeValues={
            ":pk": f"DATE#{date_str}",
            ":prefix": "HB#",
        },
        ScanIndexForward=False,  # newest first
    )
    return response.get("Items", [])


# --- Trades ---

def write_trade(trade: dict):
    """Log a trade to DynamoDB."""
    table = get_table()
    now = datetime.now(timezone.utc)

    item = {
        "PK": "USER#hank",
        "SK": f"TRADE#{now.isoformat()}",
        "symbol": trade["symbol"],
        "side": trade["side"],
        "notional": trade.get("notional", "0"),
        "order_id": trade.get("order_id", ""),
        "status": trade.get("status", ""),
        "timestamp": now.isoformat(),
    }

    # GSI1: query trades by ticker
    item["GSI1PK"] = f"TICKER#{trade['symbol']}"
    item["GSI1SK"] = f"TRADE#{now.isoformat()}"

    table.put_item(Item=item)


def get_trades_by_ticker(symbol: str) -> list[dict]:
    """Get all trades for a specific ticker via GSI1."""
    table = get_table()

    response = table.query(
        IndexName="GSI1",
        KeyConditionExpression="GSI1PK = :pk",
        ExpressionAttributeValues={
            ":pk": f"TICKER#{symbol}",
        },
        ScanIndexForward=False,
    )
    return response.get("Items", [])


def get_recent_trades(limit: int = 20) -> list[dict]:
    """Get most recent trades."""
    table = get_table()

    response = table.query(
        KeyConditionExpression="PK = :pk AND begins_with(SK, :prefix)",
        ExpressionAttributeValues={
            ":pk": "USER#hank",
            ":prefix": "TRADE#",
        },
        ScanIndexForward=False,
        Limit=limit,
    )
    return response.get("Items", [])


# --- Positions (your tracked positions with stop loss, reasoning) ---

def write_position(position: dict):
    """Write/update a tracked position."""
    table = get_table()

    table.put_item(Item={
        "PK": "USER#hank",
        "SK": f"POS#{position['symbol']}",
        "symbol": position["symbol"],
        "qty": str(position.get("qty", 0)),
        "avg_entry": str(position.get("avg_entry", 0)),
        "stop_loss": str(position.get("stop_loss", 0)),
        "take_profit": str(position.get("take_profit", 0)),
        "reasoning": position.get("reasoning", ""),
        "updated_at": datetime.now(timezone.utc).isoformat(),
    })


def get_tracked_positions() -> list[dict]:
    """Get all tracked positions."""
    table = get_table()

    response = table.query(
        KeyConditionExpression="PK = :pk AND begins_with(SK, :prefix)",
        ExpressionAttributeValues={
            ":pk": "USER#hank",
            ":prefix": "POS#",
        },
    )
    return response.get("Items", [])


# --- Alerts ---

def write_alert(alert: dict):
    """Write a trade alert."""
    table = get_table()
    now = datetime.now(timezone.utc)
    date_str = now.strftime("%Y-%m-%d")
    confidence = str(alert.get("ai_confidence", 0)).zfill(3)

    table.put_item(Item={
        "PK": f"DATE#{date_str}",
        "SK": f"ALERT#{confidence}#{alert['symbol']}",
        "GSI1PK": "STATUS#pending",
        "GSI1SK": f"ALERT#{now.isoformat()}",
        "symbol": alert["symbol"],
        "signal": alert.get("ai_signal", ""),
        "confidence": alert.get("ai_confidence", 0),
        "reason": alert.get("ai_reason", ""),
        "price": str(alert.get("price", 0)),
        "status": "pending",
        "timestamp": now.isoformat(),
        "expires_at": int((now + timedelta(days=2)).timestamp()),
    })


def get_pending_alerts() -> list[dict]:
    """Get all pending alerts via GSI1."""
    table = get_table()

    response = table.query(
        IndexName="GSI1",
        KeyConditionExpression="GSI1PK = :pk",
        ExpressionAttributeValues={
            ":pk": "STATUS#pending",
        },
        ScanIndexForward=False,
    )
    return response.get("Items", [])