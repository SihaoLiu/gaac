#!/bin/bash
#
# Validate internal markdown links in documentation
# Checks file existence and section anchors
#

set -euo pipefail

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Find GAAC plugin root for config helper
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CONFIG_HELPER="$PLUGIN_ROOT/scripts/gaac-config.sh"

# Get docs paths from config
get_docs_paths() {
    if [ -f "$CONFIG_HELPER" ]; then
        bash "$CONFIG_HELPER" list "gaac.docs_paths" 2>/dev/null || echo "docs"
    else
        echo "docs"
    fi
}

# Parse arguments
TARGET_DIR=""
FIX_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --fix)
            FIX_MODE=true
            shift
            ;;
        *)
            TARGET_DIR="$1"
            shift
            ;;
    esac
done

# Build list of directories to scan
DOC_PATHS=()
if [ -n "$TARGET_DIR" ]; then
    # Explicit target specified
    DOC_PATHS=("$TARGET_DIR")
else
    # Use configured docs paths
    CUSTOM_PATHS=$(get_docs_paths)
    if [ -n "$CUSTOM_PATHS" ]; then
        while IFS= read -r path; do
            path=$(echo "$path" | xargs)  # Trim whitespace
            if [ -n "$path" ]; then
                if [[ "$path" = /* ]]; then
                    DOC_PATHS+=("$path")
                else
                    DOC_PATHS+=("$PROJECT_ROOT/$path")
                fi
            fi
        done <<< "$CUSTOM_PATHS"
    else
        DOC_PATHS=("$PROJECT_ROOT/docs")
    fi
fi

echo "=== Markdown Link Validator ==="
echo ""
echo "Scanning: ${DOC_PATHS[*]}"
echo ""

# Portable path normalization (works on macOS and Linux)
normalize_path() {
    local path="$1"
    # Use Python if available for robust path normalization
    if command -v python3 &>/dev/null; then
        python3 -c "import os.path; print(os.path.normpath('$path'))"
    elif command -v python &>/dev/null; then
        python -c "import os.path; print(os.path.normpath('$path'))"
    else
        # Basic fallback: just use the path as-is
        echo "$path"
    fi
}

TOTAL_LINKS=0
BROKEN_FILE_LINKS=0
BROKEN_SECTION_LINKS=0
VALID_LINKS=0

BROKEN_REPORT=""

# Function to convert heading to anchor
heading_to_anchor() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9 -]//g' | tr ' ' '-' | sed 's/--*/-/g'
}

# Function to check if section exists in file
check_section() {
    local file="$1"
    local section="$2"

    # Extract all headings and convert to anchors
    while IFS= read -r heading; do
        anchor=$(heading_to_anchor "$heading")
        if [ "$anchor" = "$section" ]; then
            return 0
        fi
    done < <(grep -E "^#+\s+" "$file" 2>/dev/null | sed 's/^#*\s*//')

    return 1
}

# Process markdown files in each configured path
process_markdown_file() {
    local file="$1"
    FILE_RELATIVE="${file#$PROJECT_ROOT/}"
    FILE_DIR=$(dirname "$file")

    # Extract markdown links: [text](path) or [text](path#section)
    while IFS= read -r link_match; do
        [ -z "$link_match" ] && continue

        # Extract the path part
        LINK_PATH=$(echo "$link_match" | sed 's/.*](\([^)]*\)).*/\1/')

        # Skip external links
        if [[ "$LINK_PATH" =~ ^https?:// ]] || [[ "$LINK_PATH" =~ ^mailto: ]]; then
            continue
        fi

        # Skip empty links
        [ -z "$LINK_PATH" ] && continue

        TOTAL_LINKS=$((TOTAL_LINKS + 1))

        # Split path and section
        if [[ "$LINK_PATH" == *"#"* ]]; then
            FILE_PATH="${LINK_PATH%%#*}"
            SECTION="${LINK_PATH#*#}"
        else
            FILE_PATH="$LINK_PATH"
            SECTION=""
        fi

        # Handle different path types
        if [[ "$FILE_PATH" == /* ]]; then
            # Absolute path from project root
            TARGET_FILE="$PROJECT_ROOT$FILE_PATH"
        elif [[ "$FILE_PATH" == ./* ]]; then
            # Explicit relative path
            TARGET_FILE="$FILE_DIR/${FILE_PATH#./}"
        elif [ -n "$FILE_PATH" ]; then
            # Relative path
            TARGET_FILE="$FILE_DIR/$FILE_PATH"
        else
            # In-document link (just #section)
            TARGET_FILE="$file"
        fi

        # Normalize path (portable, works on macOS)
        TARGET_FILE=$(normalize_path "$TARGET_FILE")

        # Check file exists (if path specified)
        if [ -n "$FILE_PATH" ] && [ ! -f "$TARGET_FILE" ]; then
            BROKEN_FILE_LINKS=$((BROKEN_FILE_LINKS + 1))
            BROKEN_REPORT="${BROKEN_REPORT}\n❌ $FILE_RELATIVE: [$LINK_PATH] -> File not found"
            continue
        fi

        # Check section exists
        if [ -n "$SECTION" ]; then
            if [ -f "$TARGET_FILE" ]; then
                if ! check_section "$TARGET_FILE" "$SECTION"; then
                    BROKEN_SECTION_LINKS=$((BROKEN_SECTION_LINKS + 1))
                    BROKEN_REPORT="${BROKEN_REPORT}\n⚠️  $FILE_RELATIVE: [$LINK_PATH] -> Section '#$SECTION' not found"
                    continue
                fi
            fi
        fi

        VALID_LINKS=$((VALID_LINKS + 1))

    done < <(grep -oE '\[[^]]*\]\([^)]+\)' "$file" 2>/dev/null || true)
}

# Find all markdown files in configured doc paths
for doc_path in "${DOC_PATHS[@]}"; do
    # Skip if path doesn't exist
    [ ! -e "$doc_path" ] && continue

    # If it's a markdown file, process directly
    if [ -f "$doc_path" ] && [[ "$doc_path" == *.md ]]; then
        process_markdown_file "$doc_path"
        continue
    fi

    # If it's a directory, find markdown files within
    while IFS= read -r -d '' file; do
        process_markdown_file "$file"
    done < <(find "$doc_path" -name "*.md" -type f -print0 2>/dev/null)
done

# Report results
echo "=== Results ==="
echo ""
echo "Total links checked: $TOTAL_LINKS"
echo "  Valid: $VALID_LINKS"
echo "  Broken file links: $BROKEN_FILE_LINKS"
echo "  Broken section links: $BROKEN_SECTION_LINKS"
echo ""

if [ -n "$BROKEN_REPORT" ]; then
    echo "=== Broken Links ==="
    echo -e "$BROKEN_REPORT"
    echo ""
fi

TOTAL_BROKEN=$((BROKEN_FILE_LINKS + BROKEN_SECTION_LINKS))

if [ "$TOTAL_BROKEN" -gt 0 ]; then
    echo "Found $TOTAL_BROKEN broken link(s)."
    echo ""
    echo "To fix:"
    echo "  - Update broken file paths"
    echo "  - Add missing section headings"
    echo "  - Remove links to deleted content"
    exit 1
else
    echo "✓ All links are valid!"
    exit 0
fi
