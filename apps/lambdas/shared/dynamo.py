"""DynamoDB operations extracted from apps/api/src/dynamo.py.
Used by Lambda CRUD handlers. Table name comes from TABLE_NAME env var.
"""

import os
from datetime import datetime, timedelta, timezone

import boto3

_table = None


def get_table():
    global _table
    if _table is None:
        dynamodb = boto3.resource("dynamodb", region_name=os.environ.get("AWS_REGION", "us-east-1"))
        _table = dynamodb.Table(os.environ["TABLE_NAME"])
    return _table


def get_heartbeats_today() -> list[dict]:
    table = get_table()
    date_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    response = table.query(
        KeyConditionExpression="PK = :pk AND begins_with(SK, :prefix)",
        ExpressionAttributeValues={":pk": f"DATE#{date_str}", ":prefix": "HB#"},
        ScanIndexForward=False,
    )
    return response.get("Items", [])


def get_recent_trades(limit: int = 20) -> list[dict]:
    table = get_table()
    response = table.query(
        KeyConditionExpression="PK = :pk AND begins_with(SK, :prefix)",
        ExpressionAttributeValues={":pk": "USER#hank", ":prefix": "TRADE#"},
        ScanIndexForward=False,
        Limit=limit,
    )
    return response.get("Items", [])


def get_trades_by_ticker(symbol: str) -> list[dict]:
    table = get_table()
    response = table.query(
        IndexName="GSI1",
        KeyConditionExpression="GSI1PK = :pk",
        ExpressionAttributeValues={":pk": f"TICKER#{symbol}"},
        ScanIndexForward=False,
    )
    return response.get("Items", [])


def get_tracked_positions() -> list[dict]:
    table = get_table()
    response = table.query(
        KeyConditionExpression="PK = :pk AND begins_with(SK, :prefix)",
        ExpressionAttributeValues={":pk": "USER#hank", ":prefix": "POS#"},
    )
    return response.get("Items", [])


def get_pending_alerts() -> list[dict]:
    table = get_table()
    response = table.query(
        IndexName="GSI1",
        KeyConditionExpression="GSI1PK = :pk",
        ExpressionAttributeValues={":pk": "STATUS#pending"},
        ScanIndexForward=False,
    )
    return response.get("Items", [])


def write_trade(trade: dict) -> None:
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
        "GSI1PK": f"TICKER#{trade['symbol']}",
        "GSI1SK": f"TRADE#{now.isoformat()}",
    }
    table.put_item(Item=item)
