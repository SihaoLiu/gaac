#!/bin/bash
#
# Move/rename a markdown document and update all links pointing to it
#
# Usage:
#   move-doc.sh --from path/to/old.md --to path/to/new.md
#   move-doc.sh --from path/to/old.md --to path/to/new.md --dry-run
#
# Features:
# - Updates all markdown links that point to the old document
# - Preserves anchors (#section-name) in links
# - Supports both relative and absolute paths
# - Scans all markdown files in gaac.docs_paths
# - Dry-run mode to preview changes without modifying files
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
FROM_PATH=""
TO_PATH=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --from)
            FROM_PATH="$2"
            shift 2
            ;;
        --to)
            TO_PATH="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: move-doc.sh --from old.md --to new.md [--dry-run]" >&2
            exit 1
            ;;
    esac
done

# Validate arguments
if [ -z "$FROM_PATH" ]; then
    echo "Error: --from is required" >&2
    exit 1
fi

if [ -z "$TO_PATH" ]; then
    echo "Error: --to is required" >&2
    exit 1
fi

# Validate both paths end with .md
if [[ "$FROM_PATH" != *.md ]]; then
    echo "Error: --from path must end with .md" >&2
    exit 1
fi

if [[ "$TO_PATH" != *.md ]]; then
    echo "Error: --to path must end with .md" >&2
    exit 1
fi

# Convert to absolute paths if relative
if [[ "$FROM_PATH" != /* ]]; then
    FROM_PATH="$PROJECT_ROOT/$FROM_PATH"
fi

if [[ "$TO_PATH" != /* ]]; then
    TO_PATH="$PROJECT_ROOT/$TO_PATH"
fi

# Verify source file exists
if [ ! -f "$FROM_PATH" ]; then
    echo "Error: Source file not found: $FROM_PATH" >&2
    exit 1
fi

# Check if target already exists
if [ -f "$TO_PATH" ] && [ "$FROM_PATH" != "$TO_PATH" ]; then
    echo "Error: Target file already exists: $TO_PATH" >&2
    exit 1
fi

echo "=== Document Move ==="
echo ""
echo "From: $FROM_PATH"
echo "To:   $TO_PATH"
echo "Mode: $([ "$DRY_RUN" = true ] && echo 'DRY RUN' || echo 'LIVE')"
echo ""

# Portable path normalization
normalize_path() {
    local path="$1"
    if command -v python3 &>/dev/null; then
        python3 -c "import os.path; print(os.path.normpath('$path'))"
    elif command -v python &>/dev/null; then
        python -c "import os.path; print(os.path.normpath('$path'))"
    else
        echo "$path"
    fi
}

# Convert absolute path to relative path from a given directory
get_relative_path() {
    local from_dir="$1"
    local to_file="$2"

    if command -v python3 &>/dev/null; then
        python3 -c "import os.path; print(os.path.relpath('$to_file', '$from_dir'))"
    elif command -v python &>/dev/null; then
        python -c "import os.path; print(os.path.relpath('$to_file', '$from_dir'))"
    else
        # Fallback: just return the filename
        basename "$to_file"
    fi
}

# Build list of directories to scan
DOC_PATHS=()
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

echo "Scanning directories: ${DOC_PATHS[*]}"
echo ""

# Track files that need updating
AFFECTED_FILES=()
declare -A FILE_CHANGES

# Process each markdown file
process_markdown_file() {
    local file="$1"
    local file_dir
    file_dir=$(dirname "$file")

    # Skip the source file itself
    if [ "$file" = "$FROM_PATH" ]; then
        return
    fi

    # Read file content
    local content
    content=$(cat "$file")
    local original_content="$content"

    # Find all markdown links that might point to the old file
    # Pattern: [text](path) or [text](path#anchor)
    local has_changes=false
    local changes_desc=""

    while IFS= read -r link_match; do
        [ -z "$link_match" ] && continue

        # Extract the full link path (including any anchor)
        LINK_FULL=$(echo "$link_match" | sed 's/.*](\([^)]*\)).*/\1/')

        # Skip external links
        if [[ "$LINK_FULL" =~ ^https?:// ]] || [[ "$LINK_FULL" =~ ^mailto: ]]; then
            continue
        fi

        # Split path and anchor
        if [[ "$LINK_FULL" == *"#"* ]]; then
            LINK_PATH="${LINK_FULL%%#*}"
            LINK_ANCHOR="#${LINK_FULL#*#}"
        else
            LINK_PATH="$LINK_FULL"
            LINK_ANCHOR=""
        fi

        # Skip empty paths (in-document links)
        [ -z "$LINK_PATH" ] && continue

        # Resolve the link to absolute path
        local target_file=""
        if [[ "$LINK_PATH" == /* ]]; then
            target_file="$PROJECT_ROOT$LINK_PATH"
        elif [[ "$LINK_PATH" == ./* ]]; then
            target_file="$file_dir/${LINK_PATH#./}"
        else
            target_file="$file_dir/$LINK_PATH"
        fi

        target_file=$(normalize_path "$target_file")

        # Check if this link points to the old file
        if [ "$target_file" = "$FROM_PATH" ]; then
            # Calculate new relative path from this file to the new location
            local new_relative
            new_relative=$(get_relative_path "$file_dir" "$TO_PATH")

            # Preserve the ./ prefix if original had it
            if [[ "$LINK_PATH" == ./* ]]; then
                new_relative="./$new_relative"
            fi

            # Build new link with anchor preserved
            local new_link="${new_relative}${LINK_ANCHOR}"
            local old_link="$LINK_FULL"

            # Replace in content
            # Escape special characters for sed
            local old_escaped
            old_escaped=$(printf '%s\n' "$old_link" | sed 's/[[\.*^$()+?{|]/\\&/g')
            local new_escaped
            new_escaped=$(printf '%s\n' "$new_link" | sed 's/[&/\]/\\&/g')

            content=$(echo "$content" | sed "s|]($old_escaped)|]($new_escaped)|g")
            has_changes=true
            changes_desc="${changes_desc}  - $old_link -> $new_link"$'\n'
        fi
    done < <(grep -oE '\[[^]]*\]\([^)]+\)' "$file" 2>/dev/null || true)

    if [ "$has_changes" = true ]; then
        AFFECTED_FILES+=("$file")
        FILE_CHANGES["$file"]="$changes_desc"

        if [ "$DRY_RUN" = false ]; then
            echo "$content" > "$file"
        fi
    fi
}

# Find all markdown files in configured doc paths
for doc_path in "${DOC_PATHS[@]}"; do
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

# Report affected files
echo "=== Link Updates ==="
echo ""

if [ ${#AFFECTED_FILES[@]} -eq 0 ]; then
    echo "No files contain links to the old path."
else
    echo "Files with updated links: ${#AFFECTED_FILES[@]}"
    echo ""
    for file in "${AFFECTED_FILES[@]}"; do
        relative_file="${file#$PROJECT_ROOT/}"
        echo "File: $relative_file"
        echo "${FILE_CHANGES[$file]}"
    done
fi

echo ""

# Perform the actual move
if [ "$DRY_RUN" = true ]; then
    echo "=== DRY RUN - No changes made ==="
    echo ""
    echo "Would move: ${FROM_PATH#$PROJECT_ROOT/}"
    echo "       To:  ${TO_PATH#$PROJECT_ROOT/}"
    echo ""
    echo "Would update ${#AFFECTED_FILES[@]} file(s) with link changes."
else
    echo "=== Performing Move ==="
    echo ""

    # Create target directory if needed
    TO_DIR=$(dirname "$TO_PATH")
    if [ ! -d "$TO_DIR" ]; then
        echo "Creating directory: $TO_DIR"
        mkdir -p "$TO_DIR"
    fi

    # Move the file
    mv "$FROM_PATH" "$TO_PATH"
    echo "Moved: ${FROM_PATH#$PROJECT_ROOT/}"
    echo "   To: ${TO_PATH#$PROJECT_ROOT/}"
    echo ""
    echo "Updated ${#AFFECTED_FILES[@]} file(s) with new links."
fi

echo ""
echo "=== Next Steps ==="
echo ""
echo "1. Run link validation to verify all links are correct:"
echo "   bash \"\${CLAUDE_PLUGIN_ROOT}/skills/docs-refactor/scripts/validate-links.sh\""
echo ""
echo "2. Review and commit the changes:"
echo "   git status"
echo "   git add -A"
echo "   git commit -m \"[Docs] Move ${FROM_PATH##*/} to ${TO_PATH##*/}\""
