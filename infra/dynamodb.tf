# =============================================================================
# DynamoDB — Single Table Design
# =============================================================================
#
# | Entity     | PK                | SK                        | GSI1PK          | GSI1SK              |
# |------------|-------------------|---------------------------|-----------------|---------------------|
# | Position   | USER#hank         | POS#NVDA                  | —               | —                   |
# | Heartbeat  | DATE#2026-04-09   | HB#09:35:00               | —               | —                   |
# | Trade      | USER#hank         | TRADE#2026-04-09T10:30:00 | TICKER#NVDA     | TRADE#2026-04-09... |
# | Alert      | DATE#2026-04-09   | ALERT#95#NVDA             | STATUS#pending  | ALERT#2026-04-09... |
# | Playbook   | USER#hank         | PLAYBOOK#2026-04-09       | —               | —                   |
# | Config     | USER#hank         | CONFIG#risk               | —               | —                   |
# =============================================================================

resource "aws_dynamodb_table" "trading" {
  name         = "${var.project_name}-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  attribute {
    name = "GSI1PK"
    type = "S"
  }

  attribute {
    name = "GSI1SK"
    type = "S"
  }

  global_secondary_index {
    name            = "GSI1"
    hash_key        = "GSI1PK"
    range_key       = "GSI1SK"
    projection_type = "ALL"
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "${var.project_name}-single-table"
  }
}
