#!/bin/bash
#
# Validate /research-idea-to-spec arguments
# Input: idea text or path to markdown file
#

set -euo pipefail

INPUT="${1:-}"

if [ -z "$INPUT" ]; then
    echo "❌ Error: No input provided"
    echo ""
    echo "Usage: /research-idea-to-spec <idea text or markdown file path>"
    echo ""
    echo "Examples:"
    echo "  /research-idea-to-spec 'Add support for 2D memory addressing in the compiler'"
    echo "  /research-idea-to-spec ./docs/draft/my-idea.md"
    exit 1
fi

# Check if input is a file path
if [[ "$INPUT" == *.md ]] || [[ "$INPUT" == ./* ]] || [[ "$INPUT" == /* ]]; then
    # Input looks like a file path
    if [ -f "$INPUT" ]; then
        echo "✓ Input file exists: $INPUT"

        # Check file is readable
        if [ ! -r "$INPUT" ]; then
            echo "❌ Error: File is not readable: $INPUT"
            exit 1
        fi

        # Check file is not empty
        if [ ! -s "$INPUT" ]; then
            echo "❌ Error: File is empty: $INPUT"
            exit 1
        fi

        LINE_COUNT=$(wc -l < "$INPUT")
        echo "✓ File has $LINE_COUNT lines"
        exit 0
    else
        echo "❌ Error: File not found: $INPUT"
        echo ""
        echo "Please provide a valid markdown file path or idea text."
        exit 1
    fi
else
    # Input is idea text
    WORD_COUNT=$(echo "$INPUT" | wc -w)

    if [ "$WORD_COUNT" -lt 3 ]; then
        echo "⚠️  Warning: Idea text is very short ($WORD_COUNT words)"
        echo "   Consider providing more detail for better results."
    else
        echo "✓ Idea text provided ($WORD_COUNT words)"
    fi

    exit 0
fi
