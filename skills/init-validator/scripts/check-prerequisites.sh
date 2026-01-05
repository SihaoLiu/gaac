#!/bin/bash
#
# GAAC Prerequisites Checker
# Validates required tools and gaac.md configuration
#

set -euo pipefail

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
GAAC_CONFIG="$PROJECT_ROOT/.claude/rules/gaac.md"

echo "=== GAAC Prerequisites Check ==="
echo ""

# Track errors
ERRORS=()
WARNINGS=()

# ========================================
# Required Tools
# ========================================

echo "Checking required tools..."

# Check gh (GitHub CLI)
if command -v gh &>/dev/null; then
    GH_VERSION=$(gh --version | head -1)
    echo "  ✓ gh: $GH_VERSION"

    # Check gh authentication
    if ! gh auth status &>/dev/null; then
        ERRORS+=("gh is not authenticated. Run: gh auth login")
    fi
else
    ERRORS+=("gh (GitHub CLI) is not installed. Install from: https://cli.github.com/")
fi

# Check jq
if command -v jq &>/dev/null; then
    JQ_VERSION=$(jq --version)
    echo "  ✓ jq: $JQ_VERSION"
else
    ERRORS+=("jq is not installed. Install via your package manager (apt, brew, etc.)")
fi

echo ""

# ========================================
# Optional Tools
# ========================================

echo "Checking optional tools..."

# Check codex (for peer-check)
if command -v codex &>/dev/null; then
    echo "  ✓ codex: available (for peer-check)"
else
    WARNINGS+=("codex not found. Peer-check will fall back to claude CLI.")
fi

# Check gemini (for web research)
if command -v gemini &>/dev/null; then
    echo "  ✓ gemini: available (for web research)"
else
    WARNINGS+=("gemini not found. Web-enhanced research will be skipped.")
fi

# Check claude CLI
if command -v claude &>/dev/null; then
    echo "  ✓ claude: available"
else
    ERRORS+=("claude CLI not found. Required for fallback operations.")
fi

echo ""

# ========================================
# gaac.md Configuration
# ========================================

echo "Checking gaac.md configuration..."

if [ ! -f "$GAAC_CONFIG" ]; then
    ERRORS+=("gaac.md not found at $GAAC_CONFIG")
    ERRORS+=("Copy from GAAC plugin: cp <gaac-plugin>/templates/gaac-template.md .claude/rules/gaac.md")
else
    echo "  ✓ gaac.md exists"

    # Check for required sections
    GAAC_CONTENT=$(cat "$GAAC_CONFIG")

    # Check GitHub Repository URL
    if echo "$GAAC_CONTENT" | grep -qE "GitHub Repository URL.*\[|git@github.com:|https://github.com/"; then
        echo "  ✓ GitHub Repository URL: configured"
    else
        WARNINGS+=("GitHub Repository URL may not be configured in gaac.md")
    fi

    # Check GitHub Project URL
    if echo "$GAAC_CONTENT" | grep -qE "GitHub Project.*URL|projects/[0-9]+"; then
        echo "  ✓ GitHub Project URL: configured"
    else
        WARNINGS+=("GitHub Project URL may not be configured in gaac.md")
    fi

    # Check for L1 tags
    if echo "$GAAC_CONTENT" | grep -qE "\[.*\].*-|Level 1 Tags"; then
        echo "  ✓ L1 Tags: defined"
    else
        WARNINGS+=("L1 Tags may not be defined in gaac.md")
    fi

    # Check for documentation paths
    if echo "$GAAC_CONTENT" | grep -qE "Documentation Folders|docs/"; then
        echo "  ✓ Documentation paths: configured"
    else
        WARNINGS+=("Documentation paths may not be configured in gaac.md")
    fi

    # Check for build commands
    if echo "$GAAC_CONTENT" | grep -qE "Full Build|Incremental Build|make|npm|cargo"; then
        echo "  ✓ Build commands: configured"
    else
        WARNINGS+=("Build commands may not be configured in gaac.md")
    fi
fi

echo ""

# ========================================
# GitHub Project Access
# ========================================

echo "Checking GitHub project access..."

# Check if project scope is available
if gh auth status 2>&1 | grep -q "project"; then
    echo "  ✓ GitHub project scope: available"
else
    WARNINGS+=("GitHub project scope not enabled. Run: gh auth refresh -s project")
fi

echo ""

# ========================================
# Summary
# ========================================

echo "=== Summary ==="
echo ""

# Display warnings
if [ ${#WARNINGS[@]} -gt 0 ]; then
    echo "Warnings (${#WARNINGS[@]}):"
    for warn in "${WARNINGS[@]}"; do
        echo "  ⚠️  $warn"
    done
    echo ""
fi

# Display errors
if [ ${#ERRORS[@]} -gt 0 ]; then
    echo "Errors (${#ERRORS[@]}):"
    for err in "${ERRORS[@]}"; do
        echo "  ❌ $err"
    done
    echo ""
    echo "Please fix the errors above before using GAAC."
    exit 1
fi

echo "✅ All prerequisites met. GAAC is ready to use."
exit 0
