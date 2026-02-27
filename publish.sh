#!/usr/bin/env bash
set -euo pipefail

VAULT_BLOG_DIR="$HOME/Documents/Obsidian/BLTSEC/Blog"
HUGO_CONTENT_DIR="$(dirname "$0")/content/posts"
HUGO_STATIC_DIR="$(dirname "$0")/static/images/posts"

usage() {
  echo "Usage: $0 <post-slug>"
  echo "  Publishes a post from Obsidian to Hugo."
  echo "  Expects: \$VAULT_BLOG_DIR/<slug>/<slug>.md"
  exit 1
}

[[ $# -lt 1 ]] && usage

SLUG="$1"
SRC_DIR="$VAULT_BLOG_DIR/$SLUG"
SRC_MD="$SRC_DIR/$SLUG.md"
SRC_IMAGES="$SRC_DIR/images"
DEST_MD="$HUGO_CONTENT_DIR/$SLUG.md"
DEST_IMAGES="$HUGO_STATIC_DIR/$SLUG"

# Validate source
if [[ ! -f "$SRC_MD" ]]; then
  echo "Error: Not found: $SRC_MD"
  exit 1
fi

echo "Publishing: $SLUG"

# Create destination dirs
mkdir -p "$HUGO_CONTENT_DIR"
mkdir -p "$DEST_IMAGES"

# Copy and convert markdown
convert_markdown() {
  local content
  content=$(cat "$SRC_MD")

  # Add Hugo frontmatter if not present
  if ! echo "$content" | head -1 | grep -q "^---"; then
    local title
    title=$(echo "$SLUG" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2)); print}')
    local today
    today=$(date +%Y-%m-%d)
    content="---
title: \"$title\"
date: $today
draft: false
---

$content"
  fi

  # Convert Obsidian image embeds: ![[image.png|alt]] → ![alt](/images/posts/slug/image.png)
  content=$(echo "$content" | sed -E "s/!\[\[([^|]+)\|([^]]+)\]\]/![\2](\/images\/posts\/$SLUG\/\1)/g")
  # Convert Obsidian image embeds: ![[image.png]] → ![image](/images/posts/slug/image.png)
  content=$(echo "$content" | sed -E "s/!\[\[([^]]+)\]\]/![\1](\/images\/posts\/$SLUG\/\1)/g")

  # Convert Obsidian highlights: ==text== → <mark>text</mark>
  content=$(echo "$content" | sed -E 's/==([^=]+)==/<mark>\1<\/mark>/g')

  # Strip [[wiki-links]] to plain text (remove brackets, keep display text)
  content=$(echo "$content" | sed -E 's/\[\[([^|]+)\|([^]]+)\]\]/\2/g')
  content=$(echo "$content" | sed -E 's/\[\[([^]]+)\]\]/\1/g')

  echo "$content"
}

convert_markdown > "$DEST_MD"
echo "  Wrote: $DEST_MD"

# Copy images if present
if [[ -d "$SRC_IMAGES" ]]; then
  cp -r "$SRC_IMAGES/." "$DEST_IMAGES/"
  COUNT=$(ls "$DEST_IMAGES" | wc -l | tr -d ' ')
  echo "  Copied $COUNT image(s) to: $DEST_IMAGES"
else
  echo "  No images folder found, skipping."
fi

echo ""
echo "Review changes:"
git -C "$(dirname "$0")" diff --stat
echo ""
echo "To publish:"
echo "  git add content/posts/$SLUG.md static/images/posts/$SLUG"
echo "  git commit -m \"New post: $SLUG\""
echo "  git push"
