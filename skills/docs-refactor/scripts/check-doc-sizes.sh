#!/bin/bash
#
# Check sizes of all markdown documents in documentation folders
# Reports documents that exceed size thresholds
#

set -euo pipefail

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
GAAC_CONFIG="$PROJECT_ROOT/.claude/rules/gaac.md"

# Thresholds
WARN_THRESHOLD=1000
ERROR_THRESHOLD=1500

# Colors (if terminal supports it)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    YELLOW='\033[0;33m'
    GREEN='\033[0;32m'
    NC='\033[0m'
else
    RED=''
    YELLOW=''
    GREEN=''
    NC=''
fi

# Get documentation paths from gaac.md or use defaults
DOC_PATHS=("docs" "README.md")

# Find GAAC plugin root for config helper
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CONFIG_HELPER="$PLUGIN_ROOT/scripts/gaac-config.sh"

# Use gaac-config.sh if available for reliable config reading
if [ -f "$CONFIG_HELPER" ]; then
    CUSTOM_PATHS=$(bash "$CONFIG_HELPER" list "gaac.docs_paths" 2>/dev/null || true)
    if [ -n "$CUSTOM_PATHS" ]; then
        DOC_PATHS=()
        while IFS= read -r path; do
            path=$(echo "$path" | xargs)  # Trim whitespace
            if [ -n "$path" ] && [ -e "$PROJECT_ROOT/$path" ]; then
                DOC_PATHS+=("$path")
            fi
        done <<< "$CUSTOM_PATHS"
    fi
elif [ -f "$GAAC_CONFIG" ]; then
    # Fallback: Try to extract doc paths from gaac.md
    CUSTOM_PATHS=$(grep -E "^\s*-\s*\`?[a-zA-Z]" "$GAAC_CONFIG" 2>/dev/null | grep -v "draft" | sed "s/.*\`\([^']*\)\`.*/\1/" | head -10 || echo "")
    if [ -n "$CUSTOM_PATHS" ]; then
        while IFS= read -r path; do
            path=$(echo "$path" | tr -d '`' | tr -d ' ' | tr -d '-')
            if [ -n "$path" ] && [ -e "$PROJECT_ROOT/$path" ]; then
                DOC_PATHS+=("$path")
            fi
        done <<< "$CUSTOM_PATHS"
    fi
fi

echo "=== Document Size Report ==="
echo ""
echo "Thresholds: Warning > $WARN_THRESHOLD lines, Error > $ERROR_THRESHOLD lines"
echo ""

TOTAL_DOCS=0
WARN_DOCS=0
ERROR_DOCS=0

# Find all markdown files
while IFS= read -r -d '' file; do
    LINES=$(wc -l < "$file")
    RELATIVE_PATH="${file#$PROJECT_ROOT/}"
    TOTAL_DOCS=$((TOTAL_DOCS + 1))

    if [ "$LINES" -gt "$ERROR_THRESHOLD" ]; then
        echo -e "${RED}ERROR${NC}: $RELATIVE_PATH ($LINES lines) - MUST SPLIT"
        ERROR_DOCS=$((ERROR_DOCS + 1))
    elif [ "$LINES" -gt "$WARN_THRESHOLD" ]; then
        echo -e "${YELLOW}WARN${NC}: $RELATIVE_PATH ($LINES lines) - Consider splitting"
        WARN_DOCS=$((WARN_DOCS + 1))
    else
        echo -e "${GREEN}OK${NC}: $RELATIVE_PATH ($LINES lines)"
    fi
# Portable approach: limit file count without head -z (not available on macOS)
done < <(find "$PROJECT_ROOT" \( -path "*/docs/*" -o -name "*.md" \) -name "*.md" -type f -print0 2>/dev/null)

echo ""
echo "=== Summary ==="
echo "Total documents: $TOTAL_DOCS"
echo -e "  ${GREEN}OK${NC}: $((TOTAL_DOCS - WARN_DOCS - ERROR_DOCS))"
echo -e "  ${YELLOW}Warnings${NC}: $WARN_DOCS"
echo -e "  ${RED}Errors${NC}: $ERROR_DOCS"

if [ "$ERROR_DOCS" -gt 0 ]; then
    echo ""
    echo "Documents exceeding $ERROR_THRESHOLD lines must be split."
    echo "Use: bash \"\${CLAUDE_PLUGIN_ROOT}/skills/docs-refactor/scripts/split-document.sh\" --input <file>"
    exit 1
fi

exit 0
