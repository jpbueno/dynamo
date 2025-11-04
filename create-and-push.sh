#!/bin/bash

# Script to create GitHub repository and push code
# Usage: ./create-and-push.sh [GITHUB_TOKEN]

set -e

REPO_NAME="dynamo"
GITHUB_USER="jpbueno"
GITHUB_TOKEN="${1:-${GITHUB_TOKEN}}"

echo "🚀 Creating GitHub repository: $GITHUB_USER/$REPO_NAME"

if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ GitHub token not provided."
    echo ""
    echo "Please either:"
    echo "1. Create the repository manually at: https://github.com/new"
    echo "   Repository name: $REPO_NAME"
    echo "   Visibility: Public or Private (your choice)"
    echo "   Then run: git push -u origin main"
    echo ""
    echo "OR"
    echo ""
    echo "2. Get a GitHub token from: https://github.com/settings/tokens"
    echo "   Then run: GITHUB_TOKEN=your_token ./create-and-push.sh"
    exit 1
fi

# Create repository via GitHub API
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/user/repos \
  -d "{\"name\":\"$REPO_NAME\",\"description\":\"NVIDIA Dynamo Platform - Workshop Preparation Kit\",\"private\":false}")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "201" ]; then
    echo "✅ Repository created successfully!"
    echo "📤 Pushing code to GitHub..."
    git push -u origin main
    echo "✅ Done! Repository available at: https://github.com/$GITHUB_USER/$REPO_NAME"
elif [ "$HTTP_CODE" = "422" ]; then
    echo "⚠️  Repository might already exist, attempting to push..."
    git push -u origin main || echo "❌ Push failed. Please check repository permissions."
else
    echo "❌ Failed to create repository. HTTP Code: $HTTP_CODE"
    echo "Response: $BODY"
    exit 1
fi

