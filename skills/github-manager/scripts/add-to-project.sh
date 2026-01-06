#!/bin/bash
#
# Add issue to GitHub Project board (ISSUES ONLY)
# GAAC design: PRs are NOT tracked in the project board.
# PRs link to issues via "Resolves #N" and inherit their tracking.
# Parses project URL from gaac.md config
#

set -euo pipefail

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
GAAC_CONFIG="$PROJECT_ROOT/.claude/rules/gaac.md"

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

if echo "$RESULT" | grep -q '"item"'; then
    ITEM_ID=$(echo "$RESULT" | jq -r '.data.addProjectV2ItemByContentId.item.id')
    echo "✓ Successfully added issue #$ITEM_NUMBER to project"
    echo "  Project item ID: $ITEM_ID"
else
    if echo "$RESULT" | grep -qi "already exists"; then
        echo "ℹ️  Issue #$ITEM_NUMBER is already in the project"
    else
        echo "❌ Error adding to project:" >&2
        echo "$RESULT" >&2
        exit 1
    fi
fi
