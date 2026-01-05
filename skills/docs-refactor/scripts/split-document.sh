#!/bin/bash
#
# Split a large markdown document into smaller parts
# Attempts to split at logical boundaries (headings)
#

set -euo pipefail

# Parse arguments
INPUT_FILE=""
MAX_LINES=1000
OUTPUT_DIR=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --input|-i)
            INPUT_FILE="$2"
            shift 2
            ;;
        --max-lines|-m)
            MAX_LINES="$2"
            shift 2
            ;;
        --output-dir|-o)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [ -z "$INPUT_FILE" ]; then
    echo "Usage: split-document.sh --input <file.md> [--max-lines 1000] [--output-dir <dir>]" >&2
    exit 1
fi

if [ ! -f "$INPUT_FILE" ]; then
    echo "❌ Error: File not found: $INPUT_FILE" >&2
    exit 1
fi

# Get file info
TOTAL_LINES=$(wc -l < "$INPUT_FILE")
BASENAME=$(basename "$INPUT_FILE" .md)
DIRNAME=$(dirname "$INPUT_FILE")
OUTPUT_DIR="${OUTPUT_DIR:-$DIRNAME}"

echo "=== Document Split Plan ==="
echo ""
echo "Input: $INPUT_FILE ($TOTAL_LINES lines)"
echo "Max lines per part: $MAX_LINES"
echo "Output directory: $OUTPUT_DIR"
echo ""

if [ "$TOTAL_LINES" -le "$MAX_LINES" ]; then
    echo "✓ Document is already within size limit. No split needed."
    exit 0
fi

# Find heading positions (## level headings as split points)
HEADING_LINES=$(grep -n "^## " "$INPUT_FILE" | cut -d: -f1)
HEADING_COUNT=$(echo "$HEADING_LINES" | wc -w)

echo "Found $HEADING_COUNT ## headings as potential split points"

# Calculate approximate number of parts needed
PARTS_NEEDED=$(( (TOTAL_LINES + MAX_LINES - 1) / MAX_LINES ))
echo "Estimated parts needed: $PARTS_NEEDED"
echo ""

# Find optimal split points
SPLIT_POINTS=()
CURRENT_START=1
PART_NUM=1

while IFS= read -r heading_line; do
    # Skip if this heading is too close to current start
    if [ "$heading_line" -le "$CURRENT_START" ]; then
        continue
    fi

    # Calculate lines in current part if we split here
    PART_LINES=$((heading_line - CURRENT_START))

    # If we've accumulated enough lines, mark this as a split point
    if [ "$PART_LINES" -ge "$MAX_LINES" ]; then
        SPLIT_POINTS+=("$heading_line")
        CURRENT_START=$heading_line
        PART_NUM=$((PART_NUM + 1))
    fi
done <<< "$HEADING_LINES"

# Add end of file as final point
SPLIT_POINTS+=("$((TOTAL_LINES + 1))")

echo "Split points (line numbers): ${SPLIT_POINTS[*]}"
echo ""

# Generate split plan
echo "=== Split Plan ==="
PREV_LINE=1
PART_NUM=1

for split_line in "${SPLIT_POINTS[@]}"; do
    PART_LINES=$((split_line - PREV_LINE))
    OUTPUT_FILE="$OUTPUT_DIR/${BASENAME}-part${PART_NUM}.md"

    echo "Part $PART_NUM: lines $PREV_LINE-$((split_line - 1)) ($PART_LINES lines) -> $OUTPUT_FILE"

    if [ "$DRY_RUN" = false ]; then
        # Extract lines for this part
        sed -n "${PREV_LINE},$((split_line - 1))p" "$INPUT_FILE" > "$OUTPUT_FILE"

        # Add navigation footer
        if [ "$PART_NUM" -gt 1 ]; then
            PREV_FILE="${BASENAME}-part$((PART_NUM - 1)).md"
            echo "" >> "$OUTPUT_FILE"
            echo "---" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
            echo "> **Previous:** [Part $((PART_NUM - 1))](./$PREV_FILE)" >> "$OUTPUT_FILE"
        fi

        if [ "$split_line" -lt "$TOTAL_LINES" ]; then
            NEXT_FILE="${BASENAME}-part$((PART_NUM + 1)).md"
            if [ "$PART_NUM" -eq 1 ]; then
                echo "" >> "$OUTPUT_FILE"
                echo "---" >> "$OUTPUT_FILE"
                echo "" >> "$OUTPUT_FILE"
            fi
            echo "**Next:** [Part $((PART_NUM + 1))](./$NEXT_FILE)" >> "$OUTPUT_FILE"
        fi
    fi

    PREV_LINE=$split_line
    PART_NUM=$((PART_NUM + 1))
done

echo ""

if [ "$DRY_RUN" = true ]; then
    echo "Dry run complete. Use without --dry-run to perform split."
else
    # Create index file
    INDEX_FILE="$OUTPUT_DIR/${BASENAME}-index.md"
    echo "Creating index file: $INDEX_FILE"

    echo "# ${BASENAME} Index" > "$INDEX_FILE"
    echo "" >> "$INDEX_FILE"
    echo "This document has been split into multiple parts:" >> "$INDEX_FILE"
    echo "" >> "$INDEX_FILE"

    for i in $(seq 1 $((PART_NUM - 1))); do
        echo "- [Part $i](./${BASENAME}-part${i}.md)" >> "$INDEX_FILE"
    done

    echo "" >> "$INDEX_FILE"
    echo "---" >> "$INDEX_FILE"
    echo "*Original file: $INPUT_FILE ($TOTAL_LINES lines)*" >> "$INDEX_FILE"

    echo ""
    echo "✓ Split complete!"
    echo "  Created $((PART_NUM - 1)) part files plus index"
    echo ""
    echo "Next steps:"
    echo "  1. Review split files for logical coherence"
    echo "  2. Update cross-references as needed"
    echo "  3. Consider renaming parts by topic instead of number"
    echo "  4. Delete or archive the original large file"
fi
