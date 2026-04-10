"""Lambda handler that proxies compute-heavy requests to EC2.

The EC2 instance runs FastAPI on port 8000 in the same VPC.
This Lambda forwards requests via EC2's private IP.

Routes:
  POST /api/heartbeat             -> EC2 POST /heartbeat
  POST /api/heartbeat/indicators-only -> EC2 POST /heartbeat/indicators-only

EC2_PRIVATE_IP env var is set by Terraform.
"""

import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "shared"))

import urllib.error
import urllib.request

from response import error, success


EC2_BASE = f"http://{os.environ['EC2_PRIVATE_IP']}:8000"


def _proxy_to_ec2(method: str, path: str, body: str | None = None) -> dict:
    """Forward a request to the EC2 FastAPI instance."""
    url = f"{EC2_BASE}{path}"
    headers = {"Content-Type": "application/json"}

    data = body.encode("utf-8") if body else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)

    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            response_body = json.loads(resp.read().decode("utf-8"))
            return success(response_body)
    except urllib.error.HTTPError as e:
        body_text = e.read().decode("utf-8", errors="replace")
        return error(f"EC2 returned {e.code}: {body_text}", e.code)
    except urllib.error.URLError as e:
        return error(f"Cannot reach EC2: {e.reason}", 502)


def handler(event, context):
    method = event.get("requestContext", {}).get("http", {}).get("method", "GET")
    path = event.get("rawPath", "")
    body = event.get("body")

    if path.startswith("/api"):
        path = path[4:]

    try:
        if method == "POST" and path == "/heartbeat":
            return _proxy_to_ec2("POST", "/heartbeat", body)

        if method == "POST" and path == "/heartbeat/indicators-only":
            return _proxy_to_ec2("POST", "/heartbeat/indicators-only", body)

        return error(f"Not found: {method} {path}", 404)

    except Exception as e:
        return error(str(e), 500)
