#!/bin/bash
#
# Add issue to GitHub Project board (ISSUES ONLY)
# GAAC design: PRs are NOT tracked in the project board.
# PRs link to issues via "Resolves #N" and inherit their tracking.
# Parses project URL from gaac.md config
#
# Features:
# - Adds issue to project board
# - Auto-fills configured project fields (gaac.project_fields)
#

set -euo pipefail

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
GAAC_CONFIG="$PROJECT_ROOT/.claude/rules/gaac.md"

# Find GAAC plugin root for config helper
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CONFIG_HELPER="$PLUGIN_ROOT/scripts/gaac-config.sh"

# Parse arguments
ITEM_NUMBER=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --item-number|--issue-number)
            ITEM_NUMBER="$2"
            shift 2
            ;;
        --item-type)
            # Legacy argument - check if trying to add PR
            if [ "$2" = "pr" ]; then
                echo "❌ Error: PRs should NOT be added to the project board." >&2
                echo "   GAAC design: Only issues are tracked in the project." >&2
                echo "   PRs link to issues via 'Resolves #N' syntax." >&2
                exit 1
            fi
            shift 2
            ;;
        *)
            # Assume first positional arg is item number
            if [ -z "$ITEM_NUMBER" ]; then
                ITEM_NUMBER="$1"
            fi
            shift
            ;;
    esac
done

# Validate
if [ -z "$ITEM_NUMBER" ]; then
    echo "❌ Error: Issue number required" >&2
    echo "Usage: add-to-project.sh --issue-number 42" >&2
    exit 1
fi

# Get project URL from gaac.md
if [ ! -f "$GAAC_CONFIG" ]; then
    echo "❌ Error: gaac.md not found at $GAAC_CONFIG" >&2
    exit 1
fi

# Extract project URL - look for GitHub project URLs
PROJECT_URL=$(grep -oE 'https://github.com/(orgs/[^/]+|users/[^/]+)/projects/[0-9]+' "$GAAC_CONFIG" | head -1)

if [ -z "$PROJECT_URL" ]; then
    echo "⚠️  Warning: No GitHub Project URL found in gaac.md" >&2
    echo "   Add the URL to your gaac.md configuration." >&2
    echo "   Skipping project board integration." >&2
    exit 0
fi

echo "Project URL: $PROJECT_URL"

# Parse project URL to get owner type, owner name, and project number
if [[ "$PROJECT_URL" =~ /orgs/([^/]+)/projects/([0-9]+) ]]; then
    OWNER_TYPE="organization"
    OWNER_NAME="${BASH_REMATCH[1]}"
    PROJECT_NUMBER="${BASH_REMATCH[2]}"
elif [[ "$PROJECT_URL" =~ /users/([^/]+)/projects/([0-9]+) ]]; then
    OWNER_TYPE="user"
    OWNER_NAME="${BASH_REMATCH[1]}"
    PROJECT_NUMBER="${BASH_REMATCH[2]}"
else
    echo "❌ Error: Could not parse project URL: $PROJECT_URL" >&2
    exit 1
fi

echo "Owner: $OWNER_NAME ($OWNER_TYPE)"
echo "Project: #$PROJECT_NUMBER"

# Get project ID
echo "Fetching project ID..."

if [ "$OWNER_TYPE" = "organization" ]; then
    PROJECT_ID=$(gh api graphql -f query='
        query($org: String!, $number: Int!) {
            organization(login: $org) {
                projectV2(number: $number) { id }
            }
        }' -f org="$OWNER_NAME" -F number="$PROJECT_NUMBER" --jq '.data.organization.projectV2.id' 2>/dev/null || echo "")
else
    PROJECT_ID=$(gh api graphql -f query='
        query($login: String!, $number: Int!) {
            user(login: $login) {
                projectV2(number: $number) { id }
            }
        }' -f login="$OWNER_NAME" -F number="$PROJECT_NUMBER" --jq '.data.user.projectV2.id' 2>/dev/null || echo "")
fi

if [ -z "$PROJECT_ID" ]; then
    echo "❌ Error: Could not get project ID" >&2
    echo "   You may need project scope: gh auth refresh -s project" >&2
    exit 1
fi

echo "Project ID: $PROJECT_ID"

# Get issue node ID
echo "Fetching issue node ID..."

ITEM_NODE_ID=$(gh issue view "$ITEM_NUMBER" --json id --jq '.id' 2>/dev/null || echo "")

if [ -z "$ITEM_NODE_ID" ]; then
    echo "❌ Error: Could not get issue #$ITEM_NUMBER node ID" >&2
    exit 1
fi

echo "Issue node ID: $ITEM_NODE_ID"

# Add issue to project
echo "Adding issue #$ITEM_NUMBER to project..."

RESULT=$(gh api graphql -f query='
    mutation($project: ID!, $content: ID!) {
        addProjectV2ItemByContentId(input: {projectId: $project, contentId: $content}) {
            item { id }
        }
    }' -f project="$PROJECT_ID" -f content="$ITEM_NODE_ID" 2>&1)

ITEM_ID=""
if echo "$RESULT" | grep -q '"item"'; then
    ITEM_ID=$(echo "$RESULT" | jq -r '.data.addProjectV2ItemByContentId.item.id')
    echo "  Successfully added issue #$ITEM_NUMBER to project"
    echo "  Project item ID: $ITEM_ID"
else
    if echo "$RESULT" | grep -qi "already exists"; then
        echo "  Issue #$ITEM_NUMBER is already in the project"
        # Get existing item ID by querying issue's project items
        echo "Fetching existing project item ID..."
        REPO_INFO=$(gh repo view --json owner,name --jq '"\(.owner.login) \(.name)"' 2>/dev/null || echo "")
        if [ -n "$REPO_INFO" ]; then
            REPO_OWNER=$(echo "$REPO_INFO" | cut -d' ' -f1)
            REPO_NAME=$(echo "$REPO_INFO" | cut -d' ' -f2)
            ITEM_ID=$(gh api graphql -f query='
                query($owner: String!, $repo: String!, $number: Int!) {
                    repository(owner: $owner, name: $repo) {
                        issue(number: $number) {
                            projectItems(first: 50) {
                                nodes {
                                    id
                                    project { id }
                                }
                            }
                        }
                    }
                }' -f owner="$REPO_OWNER" -f repo="$REPO_NAME" -F number="$ITEM_NUMBER" \
                --jq ".data.repository.issue.projectItems.nodes[] | select(.project.id == \"$PROJECT_ID\") | .id" 2>/dev/null || echo "")
        fi
        if [ -z "$ITEM_ID" ]; then
            echo "  Could not retrieve project item ID, skipping field updates"
        fi
    else
        echo "Error adding to project:" >&2
        echo "$RESULT" >&2
        exit 1
    fi
fi

# ========================================
# Project Field Auto-Fill
# ========================================

# Read configured fields
FIELD_CONFIG=""
if [ -f "$CONFIG_HELPER" ]; then
    FIELD_CONFIG=$(bash "$CONFIG_HELPER" get "gaac.project_fields" 2>/dev/null || echo "")
fi

# Skip if no item ID or no field config
if [ -z "$ITEM_ID" ]; then
    echo ""
    echo "Done (no field updates - item ID unavailable)"
    exit 0
fi

if [ -z "$FIELD_CONFIG" ] || [[ "$FIELD_CONFIG" == "<"* ]]; then
    echo ""
    echo "Done (no field config)"
    exit 0
fi

echo ""
echo "=== Auto-filling project fields ==="
echo "Config: $FIELD_CONFIG"

# Fetch project fields and their types/options
echo "Fetching project field definitions..."

if [ "$OWNER_TYPE" = "organization" ]; then
    FIELDS_DATA=$(gh api graphql -f query='
        query($org: String!, $number: Int!) {
            organization(login: $org) {
                projectV2(number: $number) {
                    id
                    fields(first: 100) {
                        nodes {
                            __typename
                            ... on ProjectV2SingleSelectField {
                                id
                                name
                                options { id name }
                            }
                            ... on ProjectV2Field {
                                id
                                name
                                dataType
                            }
                        }
                    }
                }
            }
        }' -f org="$OWNER_NAME" -F number="$PROJECT_NUMBER" 2>/dev/null || echo "{}")
    FIELDS_JSON=$(echo "$FIELDS_DATA" | jq '.data.organization.projectV2.fields.nodes // []')
else
    FIELDS_DATA=$(gh api graphql -f query='
        query($login: String!, $number: Int!) {
            user(login: $login) {
                projectV2(number: $number) {
                    id
                    fields(first: 100) {
                        nodes {
                            __typename
                            ... on ProjectV2SingleSelectField {
                                id
                                name
                                options { id name }
                            }
                            ... on ProjectV2Field {
                                id
                                name
                                dataType
                            }
                        }
                    }
                }
            }
        }' -f login="$OWNER_NAME" -F number="$PROJECT_NUMBER" 2>/dev/null || echo "{}")
    FIELDS_JSON=$(echo "$FIELDS_DATA" | jq '.data.user.projectV2.fields.nodes // []')
fi

if [ "$FIELDS_JSON" = "[]" ] || [ -z "$FIELDS_JSON" ]; then
    echo "  Could not fetch project fields, skipping field updates"
    exit 0
fi

# Parse field config and update each field
echo "$FIELD_CONFIG" | tr ',' '\n' | while read -r field_pair; do
    # Trim whitespace
    field_pair=$(echo "$field_pair" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -z "$field_pair" ] && continue

    # Parse FieldName=Value
    FIELD_NAME="${field_pair%%=*}"
    FIELD_VALUE="${field_pair#*=}"

    # Trim whitespace from name and value
    FIELD_NAME=$(echo "$FIELD_NAME" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    FIELD_VALUE=$(echo "$FIELD_VALUE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    [ -z "$FIELD_NAME" ] || [ -z "$FIELD_VALUE" ] && continue

    echo "  Setting $FIELD_NAME = $FIELD_VALUE"

    # Find field by name
    FIELD_INFO=$(echo "$FIELDS_JSON" | jq -c --arg name "$FIELD_NAME" '.[] | select(.name == $name)')

    if [ -z "$FIELD_INFO" ]; then
        echo "    Warning: Field '$FIELD_NAME' not found in project, skipping"
        continue
    fi

    FIELD_ID=$(echo "$FIELD_INFO" | jq -r '.id')
    FIELD_TYPE=$(echo "$FIELD_INFO" | jq -r '.__typename')

    # Build value JSON based on field type
    VALUE_JSON=""
    case "$FIELD_TYPE" in
        ProjectV2SingleSelectField)
            # Find option ID by name
            OPTION_ID=$(echo "$FIELD_INFO" | jq -r --arg val "$FIELD_VALUE" '.options[] | select(.name == $val) | .id')
            if [ -z "$OPTION_ID" ]; then
                echo "    Warning: Option '$FIELD_VALUE' not found for field '$FIELD_NAME', skipping"
                continue
            fi
            VALUE_JSON="{\"singleSelectOptionId\":\"$OPTION_ID\"}"
            ;;
        ProjectV2Field)
            DATA_TYPE=$(echo "$FIELD_INFO" | jq -r '.dataType')
            case "$DATA_TYPE" in
                TEXT)
                    VALUE_JSON="{\"text\":\"$FIELD_VALUE\"}"
                    ;;
                NUMBER)
                    # Validate numeric
                    if ! [[ "$FIELD_VALUE" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                        echo "    Warning: '$FIELD_VALUE' is not numeric for field '$FIELD_NAME', skipping"
                        continue
                    fi
                    VALUE_JSON="{\"number\":$FIELD_VALUE}"
                    ;;
                DATE)
                    # Validate date format YYYY-MM-DD
                    if ! [[ "$FIELD_VALUE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
                        echo "    Warning: '$FIELD_VALUE' is not YYYY-MM-DD for field '$FIELD_NAME', skipping"
                        continue
                    fi
                    VALUE_JSON="{\"date\":\"$FIELD_VALUE\"}"
                    ;;
                *)
                    echo "    Warning: Unsupported field type '$DATA_TYPE' for '$FIELD_NAME', skipping"
                    continue
                    ;;
            esac
            ;;
        *)
            echo "    Warning: Unsupported field type '$FIELD_TYPE' for '$FIELD_NAME', skipping"
            continue
            ;;
    esac

    # Update field value
    UPDATE_RESULT=$(gh api graphql -f query='
        mutation($project: ID!, $item: ID!, $field: ID!, $value: ProjectV2FieldValue!) {
            updateProjectV2ItemFieldValue(input: {
                projectId: $project,
                itemId: $item,
                fieldId: $field,
                value: $value
            }) {
                projectV2Item { id }
            }
        }' \
        -f project="$PROJECT_ID" \
        -f item="$ITEM_ID" \
        -f field="$FIELD_ID" \
        -F value="$VALUE_JSON" 2>&1)

    if echo "$UPDATE_RESULT" | grep -q '"projectV2Item"'; then
        echo "    Done"
    else
        echo "    Warning: Failed to set field value"
        echo "    $UPDATE_RESULT" | head -2
    fi
done

echo ""
echo "Done"
