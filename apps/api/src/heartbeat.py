import json

import boto3
import pandas as pd
import pandas_ta as ta
import requests
import yfinance as yf
from datetime import datetime

from src.config import get_settings
from src.dynamo import write_heartbeat, write_alert

# Yahoo frequently returns empty data for scripts with no browser-like User-Agent.
_YAHOO_UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
)


def _yahoo_session() -> requests.Session:
    s = requests.Session()
    s.headers.update(
        {
            "User-Agent": _YAHOO_UA,
            "Accept": "*/*",
            "Accept-Language": "en-US,en;q=0.9",
        }
    )
    return s


def _flatten_ohlcv(df: pd.DataFrame) -> pd.DataFrame:
    if df.empty or not isinstance(df.columns, pd.MultiIndex):
        return df
    # yf.download multi-index columns: metric then ticker
    out = df.copy()
    out.columns = out.columns.get_level_values(0)
    return out


def _pick_frame(
    df: pd.DataFrame, min_bars: int, fallback: pd.DataFrame | None
) -> tuple[pd.DataFrame | None, pd.DataFrame | None]:
    if df.empty:
        return None, fallback
    if len(df) >= min_bars:
        return df, fallback
    if fallback is None or len(df) > len(fallback):
        fallback = df
    return None, fallback


def _load_ohlcv(symbol: str) -> pd.DataFrame:
    """Yahoo often returns empty data without a real browser UA; download() is a second path."""
    session = _yahoo_session()
    ticker = yf.Ticker(symbol, session=session)
    attempts = [
        {"period": "5d", "interval": "5m"},
        {"period": "15d", "interval": "15m"},
        {"period": "60d", "interval": "1h"},
        {"period": "3mo", "interval": "1d"},
        {"period": "1y", "interval": "1d"},
    ]
    min_bars = 22
    fallback = None
    last_df = pd.DataFrame()

    for kwargs in attempts:
        df = ticker.history(
            **kwargs,
            auto_adjust=True,
            prepost=False,
            actions=False,
        )
        last_df = df
        picked, fallback = _pick_frame(df, min_bars, fallback)
        if picked is not None:
            return picked

    for kwargs in attempts:
        df = yf.download(
            symbol,
            progress=False,
            threads=False,
            auto_adjust=True,
            ignore_tz=True,
            session=session,
            **kwargs,
        )
        df = _flatten_ohlcv(df)
        last_df = df
        picked, fallback = _pick_frame(df, min_bars, fallback)
        if picked is not None:
            return picked

    return fallback if fallback is not None and not fallback.empty else last_df


def fetch_indicators(symbol: str) -> dict:
    """Fetch price data and compute technical indicators."""
    df = _load_ohlcv(symbol.strip().upper())

    if df.empty:
        return {
            "symbol": symbol,
            "error": "no data",
            "hint": "Yahoo Finance returned no bars (rate limit, network, or symbol). Retry or try again later.",
        }

    df.ta.rsi(length=14, append=True)
    df.ta.macd(append=True)
    df.ta.ema(length=9, append=True)
    df.ta.ema(length=21, append=True)
    df.ta.bbands(length=20, append=True)

    latest = df.iloc[-1]

    return {
        "symbol": symbol,
        "price": round(float(latest["Close"]), 2),
        "volume": int(latest["Volume"]),
        "rsi_14": round(float(latest.get("RSI_14", 0)), 2),
        "macd": round(float(latest.get("MACD_12_26_9", 0)), 4),
        "macd_signal": round(float(latest.get("MACDs_12_26_9", 0)), 4),
        "macd_hist": round(float(latest.get("MACDh_12_26_9", 0)), 4),
        "ema_9": round(float(latest.get("EMA_9", 0)), 2),
        "ema_21": round(float(latest.get("EMA_21", 0)), 2),
        "bb_upper": round(float(latest.get("BBU_20_2.0", 0)), 2),
        "bb_lower": round(float(latest.get("BBL_20_2.0", 0)), 2),
        "timestamp": datetime.now().isoformat(),
    }


def classify_signal_gemma(indicators: dict) -> dict:
    """Use Bedrock Gemma 3 4B to classify the signal."""
    settings = get_settings()
    bedrock = boto3.client("bedrock-runtime", region_name=settings.aws_region)

    prompt = f"""You are a stock signal classifier. Given these technical indicators,
respond with ONLY a JSON object (no markdown, no explanation):

Symbol: {indicators['symbol']}
Price: ${indicators['price']}
RSI(14): {indicators['rsi_14']}
MACD: {indicators['macd']}
MACD Signal: {indicators['macd_signal']}
MACD Histogram: {indicators['macd_hist']}
EMA(9): {indicators['ema_9']}
EMA(21): {indicators['ema_21']}
Bollinger Upper: {indicators['bb_upper']}
Bollinger Lower: {indicators['bb_lower']}

Respond with this exact JSON structure:
{{"signal": "bullish" or "bearish" or "neutral", "confidence": 0-100, "reason": "one sentence"}}"""

    response = bedrock.converse(
        modelId="us.google.gemma-3-4b-it-v1:0",
        messages=[{"role": "user", "content": [{"text": prompt}]}],
        inferenceConfig={"maxTokens": 200, "temperature": 0.1},
    )

    raw = response["output"]["message"]["content"][0]["text"]
    cleaned = raw.strip()
    if cleaned.startswith("```"):
        cleaned = cleaned.split("\n", 1)[-1].rsplit("```", 1)[0].strip()

    try:
        result = json.loads(cleaned)
    except json.JSONDecodeError:
        result = {"signal": "error", "confidence": 0, "reason": f"Parse failed: {raw[:100]}"}

    return {
        **indicators,
        "ai_signal": result.get("signal", "unknown"),
        "ai_confidence": result.get("confidence", 0),
        "ai_reason": result.get("reason", ""),
        "model": "gemma-3-4b",
    }


def run_heartbeat(symbols: list[str], persist: bool = True) -> list[dict]:
    """Full heartbeat tick: fetch → indicators → classify → persist."""
    results = []
    for symbol in symbols:
        indicators = fetch_indicators(symbol)
        if "error" in indicators:
            results.append(indicators)
            continue

        classified = classify_signal_gemma(indicators)
        results.append(classified)

        if persist:
            # Write snapshot to DynamoDB
            write_heartbeat(classified)

            # If confidence > 70, create an alert
            if classified.get("ai_confidence", 0) >= 70:
                write_alert(classified)

    return results