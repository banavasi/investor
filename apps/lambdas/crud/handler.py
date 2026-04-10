"""Lambda handler for DynamoDB CRUD operations.

Routes based on API Gateway HTTP method + path:
  GET  /api/heartbeats/today  -> get_heartbeats_today
  GET  /api/trades            -> get_recent_trades
  GET  /api/trades/{symbol}   -> get_trades_by_ticker
  GET  /api/positions/tracked -> get_tracked_positions
  GET  /api/alerts/pending    -> get_pending_alerts
  GET  /api/health            -> health check
"""

import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "shared"))

from dynamo import (
    get_heartbeats_today,
    get_pending_alerts,
    get_recent_trades,
    get_tracked_positions,
    get_trades_by_ticker,
)
from response import error, success


def handler(event, context):
    method = event.get("requestContext", {}).get("http", {}).get("method", "GET")
    path = event.get("rawPath", "")

    if path.startswith("/api"):
        path = path[4:]

    try:
        if method == "GET" and path == "/health":
            return success({"status": "ok"})

        if method == "GET" and path == "/heartbeats/today":
            return success(get_heartbeats_today())

        if method == "GET" and path == "/alerts/pending":
            return success(get_pending_alerts())

        if method == "GET" and path == "/positions/tracked":
            return success(get_tracked_positions())

        if method == "GET" and path == "/trades":
            limit = int(event.get("queryStringParameters", {}).get("limit", "20"))
            return success(get_recent_trades(limit))

        if method == "GET" and path.startswith("/trades/"):
            symbol = path.split("/trades/")[1].upper()
            return success(get_trades_by_ticker(symbol))

        return error(f"Not found: {method} {path}", 404)

    except Exception as e:
        return error(str(e), 500)
