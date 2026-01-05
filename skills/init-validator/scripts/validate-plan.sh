#!/bin/bash
#
# Validate /plan-arch-to-issues arguments
# Input: glob pattern matching impl-*.md files
#

set -euo pipefail

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
IMPL_PATTERN="${1:-}"

if [ -z "$IMPL_PATTERN" ]; then
    echo "❌ Error: No impl file pattern provided"
    echo ""
    echo "Usage: /plan-arch-to-issues <impl-*.md pattern or path>"
    echo ""
    echo "Examples:"
    echo "  /plan-arch-to-issues ./docs/draft/impl-*.md"
    echo "  /plan-arch-to-issues ./docs/draft/impl-memory-addressing.md"
    exit 1
fi

# Find matching impl files
IMPL_FILES=()
while IFS= read -r -d '' file; do
    IMPL_FILES+=("$file")
done < <(find "$PROJECT_ROOT" -path "$IMPL_PATTERN" -type f -print0 2>/dev/null || true)

# Fallback: try glob expansion
if [ ${#IMPL_FILES[@]} -eq 0 ]; then
    shopt -s nullglob
    IMPL_FILES=($IMPL_PATTERN)
    shopt -u nullglob
fi

if [ ${#IMPL_FILES[@]} -eq 0 ]; then
    echo "❌ Error: No impl-*.md files found matching: $IMPL_PATTERN"
    echo ""
    echo "Expected files in docs/draft/ or similar location:"
    echo "  impl-feature-name.md"
    echo "  impl-feature-name-part1.md"
    echo "  impl-feature-name-part2.md"
    echo ""
    echo "Run /refine-spec-to-arch first to generate impl files."
    exit 1
fi

echo "✓ Found ${#IMPL_FILES[@]} impl file(s):"
TOTAL_LINES=0
for file in "${IMPL_FILES[@]}"; do
    if [ -f "$file" ]; then
        LINES=$(wc -l < "$file")
        TOTAL_LINES=$((TOTAL_LINES + LINES))
        echo "  - $file ($LINES lines)"
    fi
done

echo ""
echo "Total: $TOTAL_LINES lines across ${#IMPL_FILES[@]} file(s)"

# Check for corresponding arch files
echo ""
echo "Checking for architecture anchor files..."

ARCH_FILES=$(find "$PROJECT_ROOT/docs" -name "arch-*.md" -type f 2>/dev/null || true)
if [ -z "$ARCH_FILES" ]; then
    echo "⚠️  Warning: No arch-*.md files found"
    echo "   Implementation plans should reference architecture documents."
else
    ARCH_COUNT=$(echo "$ARCH_FILES" | wc -l)
    echo "✓ Found $ARCH_COUNT architecture file(s):"
    echo "$ARCH_FILES" | while read -r f; do
        echo "  - $f"
    done
fi

# Estimate number of issues to create
echo ""
if [ "$TOTAL_LINES" -lt 200 ]; then
    echo "ℹ️  Estimated: 1-2 issues (small implementation)"
elif [ "$TOTAL_LINES" -lt 500 ]; then
    echo "ℹ️  Estimated: 2-4 issues (medium implementation)"
elif [ "$TOTAL_LINES" -lt 1000 ]; then
    echo "ℹ️  Estimated: 4-8 issues (large implementation)"
else
    echo "ℹ️  Estimated: 8+ issues (very large implementation)"
    echo "   Consider breaking down further."
fi

echo ""
echo "✅ Validation passed"
exit 0
