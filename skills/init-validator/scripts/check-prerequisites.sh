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
# Optional Tools (at least codex or claude required for code review)
# ========================================

echo "Checking optional tools..."

# Track if at least one external AI tool is available
EXTERNAL_TOOL_AVAILABLE=false

# Check codex (preferred for code review)
if command -v codex &>/dev/null; then
    echo "  ✓ codex: available (preferred for code review)"
    EXTERNAL_TOOL_AVAILABLE=true
else
    echo "  - codex: not found"
fi

# Check claude CLI (fallback for code review)
if command -v claude &>/dev/null; then
    echo "  ✓ claude: available (fallback for code review)"
    EXTERNAL_TOOL_AVAILABLE=true
else
    echo "  - claude: not found"
fi

# Check gemini (for web research)
if command -v gemini &>/dev/null; then
    echo "  ✓ gemini: available (for web research)"
else
    WARNINGS+=("gemini not found. Web-enhanced research will be skipped.")
fi

# Warn if no external AI tool available
if [ "$EXTERNAL_TOOL_AVAILABLE" = false ]; then
    WARNINGS+=("No external AI tools (codex, claude) available. Code review will be limited to self-check only.")
fi

echo ""

# ========================================
# gaac.md Configuration
# ========================================

echo "Checking gaac.md configuration..."

# Find GAAC plugin root for config helper
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CONFIG_HELPER="$PLUGIN_ROOT/scripts/gaac-config.sh"

if [ ! -f "$GAAC_CONFIG" ]; then
    ERRORS+=("gaac.md not found at $GAAC_CONFIG")
    ERRORS+=("Copy from GAAC plugin: cp <gaac-plugin>/templates/gaac-template.md .claude/rules/gaac.md")
else
    echo "  ✓ gaac.md exists"

    # Check machine-readable keys if config helper is available
    if [ -f "$CONFIG_HELPER" ]; then
        echo "  Checking machine-readable keys..."

        REQUIRED_KEYS=(
            "gaac.repo_url"
            "gaac.project_url"
            "gaac.docs_paths"
            "gaac.quick_test"
            "gaac.quick_build"
        )

        for key in "${REQUIRED_KEYS[@]}"; do
            value=$(bash "$CONFIG_HELPER" get "$key" 2>/dev/null || true)
            if [ -n "$value" ] && [ "$value" != "<" ]; then
                echo "    ✓ $key: configured"
            else
                WARNINGS+=("$key may not be configured in gaac.md")
            fi
        done

        # Check tag system configuration
        echo "  Checking tag system..."
        TAGS_L1=$(bash "$CONFIG_HELPER" get "gaac.tags.l1" 2>/dev/null || true)
        if [ -n "$TAGS_L1" ] && [ "$TAGS_L1" != "MISSING" ] && [[ "$TAGS_L1" == *"["* ]]; then
            echo "    ✓ gaac.tags.l1: configured"
        else
            WARNINGS+=("gaac.tags.l1 not configured - tag inference will use defaults")
        fi
    else
        # Fallback to pattern matching
        GAAC_CONTENT=$(cat "$GAAC_CONFIG")

        # Check GitHub Repository URL
        if echo "$GAAC_CONTENT" | grep -qE "gaac.repo_url:|GitHub Repository URL.*git@|https://github.com/"; then
            echo "  ✓ GitHub Repository URL: configured"
        else
            WARNINGS+=("GitHub Repository URL may not be configured in gaac.md")
        fi

        # Check GitHub Project URL
        if echo "$GAAC_CONTENT" | grep -qE "gaac.project_url:|projects/[0-9]+"; then
            echo "  ✓ GitHub Project URL: configured"
        else
            WARNINGS+=("GitHub Project URL may not be configured in gaac.md")
        fi

        # Check for documentation paths
        if echo "$GAAC_CONTENT" | grep -qE "gaac.docs_paths:|Documentation Folders|docs/"; then
            echo "  ✓ Documentation paths: configured"
        else
            WARNINGS+=("Documentation paths may not be configured in gaac.md")
        fi

        # Check for build commands
        if echo "$GAAC_CONTENT" | grep -qE "gaac.quick_build:|gaac.quick_test:|Incremental Build|make|npm|cargo"; then
            echo "  ✓ Build commands: configured"
        else
            WARNINGS+=("Build commands may not be configured in gaac.md")
        fi
    fi

    # Validate docs paths exist
    if [ -f "$CONFIG_HELPER" ]; then
        docs_paths=$(bash "$CONFIG_HELPER" get "gaac.docs_paths" 2>/dev/null || true)
        if [ -n "$docs_paths" ]; then
            missing_paths=()
            while IFS= read -r path; do
                [ -z "$path" ] && continue
                path=$(echo "$path" | xargs)  # Trim whitespace
                if [ ! -d "$PROJECT_ROOT/$path" ]; then
                    missing_paths+=("$path")
                fi
            done < <(echo "$docs_paths" | tr ',' '\n')
            if [ ${#missing_paths[@]} -gt 0 ]; then
                WARNINGS+=("Docs paths not found: ${missing_paths[*]}")
            else
                echo "  ✓ All docs paths exist"
            fi
        fi
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
