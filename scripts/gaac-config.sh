#!/bin/bash
#
# GAAC Configuration Helper
# Provides structured access to gaac.md configuration values
#
# Usage:
#   gaac-config.sh get <key>        - Get value (empty if not found)
#   gaac-config.sh require <key>    - Get value (error if not found)
#   gaac-config.sh list <key>       - Get comma-separated values as lines
#   gaac-config.sh exists <key>     - Exit 0 if key exists, 1 otherwise
#

set -euo pipefail

COMMAND="${1:-}"
KEY="${2:-}"

if [ -z "$COMMAND" ] || [ -z "$KEY" ]; then
    echo "Usage: gaac-config.sh <get|require|list|exists> <key>" >&2
    exit 2
fi

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
CONFIG_FILE="${GAAC_CONFIG_FILE:-$PROJECT_ROOT/.claude/rules/gaac.md}"

if [ ! -f "$CONFIG_FILE" ]; then
    if [ "$COMMAND" = "exists" ]; then
        exit 1
    fi
    echo "GAAC config not found: $CONFIG_FILE" >&2
    exit 1
fi

# Read a value from the config file
# Supports both "gaac.key: value" format and "**Key**: value" natural language format
read_value() {
    local key="$1"
    local line=""

    # Try machine-readable format first: "gaac.key: value"
    line=$(grep -E "^[[:space:]]*${key}[[:space:]]*:" "$CONFIG_FILE" 2>/dev/null | head -n 1 || true)

    if [ -z "$line" ]; then
        # Fallback: Try natural language format
        # Convert gaac.key to "Key" for lookup
        local natural_key=""
        case "$key" in
            gaac.repo_url|gaac.repository_url)
                natural_key="GitHub Repository URL"
                ;;
            gaac.project_url)
                natural_key="GitHub Project.*URL"
                ;;
            gaac.docs_paths)
                natural_key="Documentation Folders"
                ;;
            gaac.quick_test)
                natural_key="Quick Test"
                ;;
            gaac.quick_build)
                natural_key="Incremental Build"
                ;;
            gaac.tags.l1)
                natural_key="L1 Tags"
                ;;
            gaac.tags.l2)
                natural_key="L2 Tags"
                ;;
            gaac.tags.l3)
                natural_key="L3 Tags"
                ;;
            gaac.default_branch)
                natural_key="Default branch"
                ;;
        esac

        if [ -n "$natural_key" ]; then
            # Look for "**Key**: value" or "Key: value" pattern
            line=$(grep -iE "(^\*\*${natural_key}\*\*:|^${natural_key}:)" "$CONFIG_FILE" 2>/dev/null | head -n 1 || true)
        fi
    fi

    if [ -z "$line" ]; then
        echo ""
        return 0
    fi

    # Extract value after the colon
    echo "$line" | sed -E 's/^[^:]*:[[:space:]]*//' | sed -E 's/[[:space:]]+$//'
}

case "$COMMAND" in
    get)
        read_value "$KEY"
        ;;
    require)
        value=$(read_value "$KEY")
        if [ -z "$value" ]; then
            echo "Missing required config key: $KEY" >&2
            exit 1
        fi
        echo "$value"
        ;;
    list)
        value=$(read_value "$KEY")
        if [ -z "$value" ]; then
            exit 0
        fi
        # Normalize comma-separated lists to one item per line
        echo "$value" | tr ',' '\n' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | sed '/^$/d'
        ;;
    exists)
        value=$(read_value "$KEY")
        if [ -n "$value" ]; then
            exit 0
        fi
        exit 1
        ;;
    *)
        echo "Unknown command: $COMMAND" >&2
        exit 2
        ;;
esac
