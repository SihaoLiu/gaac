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
#   gaac-config.sh get-tags <level> - Get L1/L2/L3 tags as array
#   gaac-config.sh get-file-mappings - Get file-to-tag mappings
#   gaac-config.sh append-tag <level> <tag> - Add new tag to L1/L2/L3
#   gaac-config.sh append-file-mapping <pattern> <tag> - Add new file mapping
#   gaac-config.sh run-quick-test   - Execute gaac.quick_test command
#   gaac-config.sh run-quick-build  - Execute gaac.quick_build command
#   gaac-config.sh run-full-test    - Execute gaac.full_test command
#   gaac-config.sh run-lint         - Execute gaac.lint command (optional)
#   gaac-config.sh run-env-setup    - Execute gaac.env_setup command (optional)
#   gaac-config.sh infer-tag <file-path> - Infer tag from file path
#

set -euo pipefail

COMMAND="${1:-}"
KEY="${2:-}"

# Validate command is provided
if [ -z "$COMMAND" ]; then
    echo "Usage: gaac-config.sh <command> [key] [value]" >&2
    echo ""
    echo "Commands requiring <key>:"
    echo "  get <key>              - Get value (empty if not found)"
    echo "  require <key>          - Get value (error if not found)"
    echo "  list <key>             - Get comma-separated values as lines"
    echo "  exists <key>           - Exit 0 if key exists, 1 otherwise"
    echo "  get-tags <level>       - Get L1/L2/L3 tags (level: l1, l2, l3)"
    echo "  append-tag <level> <tag>           - Add new tag to L1/L2/L3"
    echo "  append-file-mapping <pattern> <tag> - Add new file mapping"
    echo "  infer-tag <file-path>  - Infer tag from file path"
    echo ""
    echo "Commands without arguments:"
    echo "  docs-base              - Get base docs directory"
    echo "  draft-dir              - Get draft directory path"
    echo "  arch-dir               - Get architecture directory path"
    echo "  get-file-mappings      - Get file-to-tag mappings"
    echo "  run-quick-test         - Execute gaac.quick_test command"
    echo "  run-quick-build        - Execute gaac.quick_build command"
    echo "  run-full-test          - Execute gaac.full_test command"
    echo "  run-lint               - Execute gaac.lint command (optional)"
    echo "  run-env-setup          - Execute gaac.env_setup command (optional)"
    exit 2
fi

# Commands that require a key parameter
COMMANDS_REQUIRING_KEY="get require list exists get-tags append-tag append-file-mapping infer-tag"

# Check if command requires key
if [[ " $COMMANDS_REQUIRING_KEY " =~ " $COMMAND " ]] && [ -z "$KEY" ]; then
    echo "Error: Command '$COMMAND' requires a key argument" >&2
    echo "Usage: gaac-config.sh $COMMAND <key>" >&2
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

# Portable sed in-place edit (works on both macOS and Linux)
# Usage: sed_inplace 's/pattern/replacement/' file
sed_inplace() {
    local pattern="$1"
    local file="$2"
    local tmpfile
    tmpfile=$(mktemp)
    sed "$pattern" "$file" > "$tmpfile" && mv "$tmpfile" "$file"
}

# Run a configured command
# Usage: run_configured_command <key> <required|optional>
run_configured_command() {
    local key="$1"
    local required="${2:-required}"
    local cmd
    cmd=$(read_value "$key")

    if [ -z "$cmd" ] || [[ "$cmd" == "<"* ]]; then
        if [ "$required" = "optional" ]; then
            echo "SKIP: $key not configured (optional)"
            exit 0
        fi
        echo "ERROR: $key not configured" >&2
        exit 1
    fi
    echo "Running: $cmd"
    eval "$cmd"
}

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
            gaac.full_test)
                natural_key="Full Test"
                ;;
            gaac.lint)
                natural_key="Lint.*Format"
                ;;
            gaac.env_setup)
                natural_key="Environment Setup"
                ;;
            gaac.project_fields)
                natural_key="Project Fields"
                ;;
            gaac.comment_attribution_prefix)
                natural_key="Comment Attribution"
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

# Get docs paths as array
get_docs_paths() {
    local value
    value=$(read_value "gaac.docs_paths")
    if [ -z "$value" ]; then
        echo "docs"
        return
    fi
    echo "$value" | tr ',' '\n' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | sed '/^$/d'
}

# Check if path looks like a file (ends with common extensions)
is_file_path() {
    local p="$1"
    # Filter out paths that look like files (end with .md, .txt, .rst, etc.)
    [[ "$p" =~ \.(md|txt|rst|adoc|html|htm)$ ]]
}

# Find the base docs directory (the shortest path that's a parent of others)
find_docs_base() {
    local paths=()
    while IFS= read -r p; do
        [ -n "$p" ] && paths+=("$p")
    done < <(get_docs_paths)

    if [ ${#paths[@]} -eq 0 ]; then
        echo "docs"
        return
    fi

    # Find the shortest path that:
    # 1. Is not a file path (doesn't end with .md, .txt, etc.)
    # 2. Doesn't end with /draft or /architecture
    local base=""
    for p in "${paths[@]}"; do
        # Skip file paths (e.g., README.md) - they can't be base directories
        if is_file_path "$p"; then
            continue
        fi
        if [[ ! "$p" =~ /draft$ ]] && [[ ! "$p" =~ /architecture$ ]] && [[ ! "$p" =~ /arch$ ]]; then
            if [ -z "$base" ] || [ ${#p} -lt ${#base} ]; then
                base="$p"
            fi
        fi
    done

    # If no suitable base found, extract from paths ending with /draft or /architecture
    if [ -z "$base" ]; then
        for p in "${paths[@]}"; do
            # Skip file paths
            if is_file_path "$p"; then
                continue
            fi
            local candidate="${p%/draft}"
            candidate="${candidate%/architecture}"
            candidate="${candidate%/arch}"
            if [ -z "$base" ] || [ ${#candidate} -lt ${#base} ]; then
                base="$candidate"
            fi
        done
    fi

    echo "${base:-docs}"
}

# Find or construct the draft directory
find_draft_dir() {
    local paths=()
    while IFS= read -r p; do
        [ -n "$p" ] && paths+=("$p")
    done < <(get_docs_paths)

    # Look for existing path ending with /draft
    for p in "${paths[@]}"; do
        if [[ "$p" =~ /draft$ ]] || [ "$p" = "draft" ]; then
            echo "$p"
            return
        fi
    done

    # Not found, construct from base
    local base
    base=$(find_docs_base)
    echo "${base}/draft"
}

# Find or construct the architecture directory
find_arch_dir() {
    local paths=()
    while IFS= read -r p; do
        [ -n "$p" ] && paths+=("$p")
    done < <(get_docs_paths)

    # Look for existing path ending with /architecture or /arch
    for p in "${paths[@]}"; do
        if [[ "$p" =~ /architecture$ ]] || [[ "$p" =~ /arch$ ]] || [ "$p" = "architecture" ]; then
            echo "$p"
            return
        fi
    done

    # Not found, construct from base
    local base
    base=$(find_docs_base)
    echo "${base}/architecture"
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
    docs-base)
        find_docs_base
        ;;
    draft-dir)
        find_draft_dir
        ;;
    arch-dir)
        find_arch_dir
        ;;
    get-tags)
        # Get tags for a specific level (l1, l2, l3)
        LEVEL="${KEY:-l1}"
        TAG_KEY="gaac.tags.${LEVEL}"
        value=$(read_value "$TAG_KEY")
        if [ -z "$value" ]; then
            exit 0
        fi
        # Extract tags from [Tag1][Tag2] format
        echo "$value" | grep -oE '\[[^]]+\]' | tr -d '[]' | sort -u
        ;;
    get-file-mappings)
        # Get file-to-tag mappings
        # Format: pattern:[Tag], pattern:[Tag]
        value=$(read_value "gaac.file_mappings")
        if [ -z "$value" ]; then
            # Return empty - no mappings configured
            exit 0
        fi
        # Output as: pattern TAB tag
        echo "$value" | tr ',' '\n' | sed 's/^[[:space:]]*//' | while read -r mapping; do
            if [[ "$mapping" =~ ^([^:]+):(\[.+\])$ ]]; then
                pattern="${BASH_REMATCH[1]}"
                tag="${BASH_REMATCH[2]}"
                echo -e "${pattern}\t${tag}"
            fi
        done
        ;;
    append-tag)
        # Append a new tag to L1/L2/L3
        LEVEL="$KEY"
        TAG="${3:-}"
        if [ -z "$TAG" ]; then
            echo "Usage: gaac-config.sh append-tag <level> <tag>" >&2
            exit 2
        fi
        TAG_KEY="gaac.tags.${LEVEL}"
        current=$(read_value "$TAG_KEY")
        # Check if tag already exists
        if echo "$current" | grep -qF "[$TAG]"; then
            echo "Tag [$TAG] already exists in $TAG_KEY"
            exit 0
        fi
        # Append tag
        new_value="${current}[${TAG}]"
        # Update in file
        if grep -qE "^[[:space:]]*${TAG_KEY}:" "$CONFIG_FILE"; then
            sed_inplace "s|^\([[:space:]]*${TAG_KEY}:\).*|\1 ${new_value}|" "$CONFIG_FILE"
            echo "Appended [$TAG] to $TAG_KEY"
        else
            echo "$TAG_KEY: $new_value" >> "$CONFIG_FILE"
            echo "Added $TAG_KEY: $new_value"
        fi
        ;;
    append-file-mapping)
        # Append a new file-to-tag mapping
        PATTERN="$KEY"
        TAG="${3:-}"
        if [ -z "$TAG" ]; then
            echo "Usage: gaac-config.sh append-file-mapping <pattern> <tag>" >&2
            exit 2
        fi
        current=$(read_value "gaac.file_mappings")
        # Check if pattern already exists
        if echo "$current" | grep -qF "$PATTERN:"; then
            echo "Pattern '$PATTERN' already has a mapping"
            exit 0
        fi
        # Append mapping
        if [ -n "$current" ]; then
            new_value="${current}, ${PATTERN}:${TAG}"
        else
            new_value="${PATTERN}:${TAG}"
        fi
        # Update in file
        if grep -qE "^[[:space:]]*gaac\.file_mappings:" "$CONFIG_FILE"; then
            sed_inplace "s|^\([[:space:]]*gaac\.file_mappings:\).*|\1 ${new_value}|" "$CONFIG_FILE"
            echo "Appended mapping: $PATTERN:$TAG"
        else
            echo "gaac.file_mappings: $new_value" >> "$CONFIG_FILE"
            echo "Added gaac.file_mappings: $new_value"
        fi
        ;;
    infer-tag)
        # Infer tag from file path using configured mappings
        FILE_PATH="$KEY"
        if [ -z "$FILE_PATH" ]; then
            echo "Usage: gaac-config.sh infer-tag <file-path>" >&2
            exit 2
        fi
        # First check file mappings
        while IFS=$'\t' read -r pattern tag; do
            [ -z "$pattern" ] && continue
            # Convert glob pattern to regex
            regex=$(echo "$pattern" | sed 's/\*\*/.*/' | sed 's/\*/.*/g')
            if [[ "$FILE_PATH" =~ $regex ]]; then
                echo "$tag"
                exit 0
            fi
        done < <(bash "$0" get-file-mappings 2>/dev/null || true)
        # Fallback to heuristic inference
        if [[ "$FILE_PATH" =~ ^docs/ ]] || [[ "$FILE_PATH" =~ \.md$ ]]; then
            echo "[Docs]"
        elif [[ "$FILE_PATH" =~ ^tests?/ ]] || [[ "$FILE_PATH" =~ _test\. ]] || [[ "$FILE_PATH" =~ \.test\. ]]; then
            echo "[Tests]"
        elif [[ "$FILE_PATH" =~ /api/ ]] || [[ "$FILE_PATH" =~ ^api/ ]]; then
            echo "[API]"
        elif [[ "$FILE_PATH" =~ /ui/ ]] || [[ "$FILE_PATH" =~ ^ui/ ]] || [[ "$FILE_PATH" =~ /components/ ]]; then
            echo "[UI]"
        elif [[ "$FILE_PATH" =~ /infra/ ]] || [[ "$FILE_PATH" =~ ^infra/ ]] || [[ "$FILE_PATH" =~ /deploy/ ]]; then
            echo "[Infra]"
        else
            echo "[Core]"
        fi
        ;;
    run-quick-test)
        run_configured_command "gaac.quick_test"
        ;;
    run-quick-build)
        run_configured_command "gaac.quick_build"
        ;;
    run-full-test)
        run_configured_command "gaac.full_test"
        ;;
    run-lint)
        run_configured_command "gaac.lint" "optional"
        ;;
    run-env-setup)
        run_configured_command "gaac.env_setup" "optional"
        ;;
    *)
        echo "Unknown command: $COMMAND" >&2
        exit 2
        ;;
esac
