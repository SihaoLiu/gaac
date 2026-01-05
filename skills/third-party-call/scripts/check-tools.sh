#!/bin/bash
#
# Check which third-party AI tools are available
#

set -euo pipefail

echo "=== Third-Party Tool Availability ==="
echo ""

AVAILABLE=()
UNAVAILABLE=()

# Check Codex
if command -v codex &>/dev/null; then
    echo "✓ codex: Available"
    CODEX_VERSION=$(codex --version 2>/dev/null | head -1 || echo "version unknown")
    echo "  Version: $CODEX_VERSION"
    AVAILABLE+=("codex")
else
    echo "✗ codex: Not installed"
    UNAVAILABLE+=("codex")
fi

# Check Claude CLI
if command -v claude &>/dev/null; then
    echo "✓ claude: Available"
    CLAUDE_VERSION=$(claude --version 2>/dev/null | head -1 || echo "version unknown")
    echo "  Version: $CLAUDE_VERSION"
    AVAILABLE+=("claude")
else
    echo "✗ claude: Not installed"
    UNAVAILABLE+=("claude")
fi

# Check Gemini
if command -v gemini &>/dev/null; then
    echo "✓ gemini: Available"
    GEMINI_VERSION=$(gemini --version 2>/dev/null | head -1 || echo "version unknown")
    echo "  Version: $GEMINI_VERSION"
    AVAILABLE+=("gemini")
else
    echo "✗ gemini: Not installed"
    UNAVAILABLE+=("gemini")
fi

echo ""
echo "=== Summary ==="
echo "Available: ${AVAILABLE[*]:-none}"
echo "Missing: ${UNAVAILABLE[*]:-none}"
echo ""

# Recommendations
if [[ ! " ${AVAILABLE[*]} " =~ " codex " ]] && [[ ! " ${AVAILABLE[*]} " =~ " claude " ]]; then
    echo "⚠️  Warning: Neither codex nor claude is available."
    echo "   Peer-check and independent analysis will not work."
    echo "   Install at least one: https://openai.com/codex or https://claude.ai/cli"
fi

if [[ ! " ${AVAILABLE[*]} " =~ " gemini " ]]; then
    echo "ℹ️  Note: gemini not available."
    echo "   Web-enhanced research will be skipped."
fi

# Output JSON for programmatic use
echo ""
echo "JSON_OUTPUT:"
jq -n \
    --argjson codex "$(command -v codex &>/dev/null && echo 'true' || echo 'false')" \
    --argjson claude "$(command -v claude &>/dev/null && echo 'true' || echo 'false')" \
    --argjson gemini "$(command -v gemini &>/dev/null && echo 'true' || echo 'false')" \
    '{codex: $codex, claude: $claude, gemini: $gemini}'
