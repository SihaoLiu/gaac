#!/bin/bash
#
# Post a comment to an issue or PR with optional attribution prefix
#
# Usage:
#   post-comment.sh --type issue|pr --number N --body "..."
#   post-comment.sh --type issue --number 42 --body-file ./comment.md
#   post-comment.sh --type pr --number 123 --body "..." --no-attribution
#
# Features:
# - Reads gaac.comment_attribution_prefix from config
# - Prepends prefix to all comments unless --no-attribution is set
# - Supports both inline --body and --body-file
#

set -euo pipefail

# Find GAAC plugin root for config helper
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CONFIG_HELPER="$PLUGIN_ROOT/scripts/gaac-config.sh"

# Parse arguments
COMMENT_TYPE=""
NUMBER=""
BODY=""
BODY_FILE=""
NO_ATTRIBUTION=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --type)
            COMMENT_TYPE="$2"
            shift 2
            ;;
        --number)
            NUMBER="$2"
            shift 2
            ;;
        --body)
            BODY="$2"
            shift 2
            ;;
        --body-file)
            BODY_FILE="$2"
            shift 2
            ;;
        --no-attribution)
            NO_ATTRIBUTION=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Validate arguments
if [ -z "$COMMENT_TYPE" ]; then
    echo "Error: --type is required (issue or pr)" >&2
    exit 1
fi

if [ "$COMMENT_TYPE" != "issue" ] && [ "$COMMENT_TYPE" != "pr" ]; then
    echo "Error: --type must be 'issue' or 'pr'" >&2
    exit 1
fi

if [ -z "$NUMBER" ]; then
    echo "Error: --number is required" >&2
    exit 1
fi

if [ -z "$BODY" ] && [ -z "$BODY_FILE" ]; then
    echo "Error: Either --body or --body-file is required" >&2
    exit 1
fi

# Read body from file if specified
if [ -n "$BODY_FILE" ]; then
    if [ ! -f "$BODY_FILE" ]; then
        echo "Error: Body file not found: $BODY_FILE" >&2
        exit 1
    fi
    BODY=$(cat "$BODY_FILE")
fi

# Read attribution prefix from config
ATTRIBUTION_PREFIX=""
if [ "$NO_ATTRIBUTION" = false ] && [ -f "$CONFIG_HELPER" ]; then
    ATTRIBUTION_PREFIX=$(bash "$CONFIG_HELPER" get "gaac.comment_attribution_prefix" 2>/dev/null || echo "")
fi

# Skip attribution if prefix is empty or placeholder
if [ -z "$ATTRIBUTION_PREFIX" ] || [[ "$ATTRIBUTION_PREFIX" == "<"* ]]; then
    ATTRIBUTION_PREFIX=""
fi

# Build final comment body
if [ -n "$ATTRIBUTION_PREFIX" ]; then
    FINAL_BODY="${ATTRIBUTION_PREFIX}

${BODY}"
else
    FINAL_BODY="$BODY"
fi

# Post comment
if [ "$COMMENT_TYPE" = "issue" ]; then
    gh issue comment "$NUMBER" --body "$FINAL_BODY"
else
    gh pr comment "$NUMBER" --body "$FINAL_BODY"
fi
