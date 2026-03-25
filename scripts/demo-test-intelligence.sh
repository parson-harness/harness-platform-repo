#!/bin/bash
################################################################################
# Demo Script: Test Intelligence Showcase
# 
# This script creates a branch with a minor change to ChaosService.java
# to demonstrate Harness Test Intelligence selecting only affected tests.
#
# Usage:
#   ./scripts/demo-test-intelligence.sh [--push]
#
# Options:
#   --push    Push the branch to remote (triggers CI pipeline)
#   --dry-run Show what would be done without making changes
#
# What it does:
#   1. Creates a feature branch: demo/test-intelligence-<timestamp>
#   2. Adds a simple method to ChaosService.java
#   3. Commits the change
#   4. Optionally pushes to trigger CI pipeline
#
# Expected Test Intelligence Results:
#   - Total tests: 72
#   - Tests selected: ~29 (ChaosService-related)
#   - Tests skipped: ~43 (unaffected by change)
#   - Time savings: ~60%
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_FILE="src/main/java/io/harness/demo/service/ChaosService.java"
BRANCH_PREFIX="demo/test-intelligence"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BRANCH_NAME="${BRANCH_PREFIX}-${TIMESTAMP}"

# Parse arguments
PUSH_BRANCH=false
DRY_RUN=false
for arg in "$@"; do
    case $arg in
        --push)
            PUSH_BRANCH=true
            ;;
        --dry-run)
            DRY_RUN=true
            ;;
        --help|-h)
            echo "Usage: $0 [--push] [--dry-run]"
            echo ""
            echo "Options:"
            echo "  --push     Push branch to remote (triggers CI)"
            echo "  --dry-run  Show what would be done"
            exit 0
            ;;
    esac
done

cd "$REPO_ROOT"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     HARNESS TEST INTELLIGENCE DEMO                           ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if we're in a git repo
if [ ! -d .git ]; then
    echo -e "${RED}Error: Not in a git repository${NC}"
    exit 1
fi

# Check if target file exists
if [ ! -f "$TARGET_FILE" ]; then
    echo -e "${RED}Error: Target file not found: $TARGET_FILE${NC}"
    exit 1
fi

# Check for uncommitted changes
if [ -n "$(git status --porcelain)" ]; then
    echo -e "${YELLOW}Warning: You have uncommitted changes${NC}"
    git status --short
    echo ""
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo -e "${GREEN}Step 1: Creating feature branch${NC}"
echo "  Branch: $BRANCH_NAME"

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}  [DRY RUN] Would create branch: $BRANCH_NAME${NC}"
else
    git checkout -b "$BRANCH_NAME"
fi

echo ""
echo -e "${GREEN}Step 2: Adding demo method to ChaosService.java${NC}"

# The code to add - a simple health check method
DEMO_CODE='
    /**
     * Demo method for Test Intelligence showcase.
     * Added: '"$TIMESTAMP"'
     * 
     * This method demonstrates how Harness Test Intelligence
     * selects only tests affected by code changes.
     * 
     * Expected: Only ChaosServiceTest and ChaosApiTest will run,
     * while AppConfigTest, MetricsServiceTest, etc. are skipped.
     */
    public boolean isSystemHealthy() {
        return !isChaosActive() && getCurrentErrorRate() == 0.0;
    }
'

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}  [DRY RUN] Would add method to ChaosService.java:${NC}"
    echo "$DEMO_CODE"
else
    # Find the last closing brace and insert before it
    # Using sed for macOS compatibility (head -n -1 doesn't work on macOS)
    TEMP_FILE=$(mktemp)
    
    # Get total lines and remove the last line (closing brace)
    TOTAL_LINES=$(wc -l < "$TARGET_FILE" | tr -d ' ')
    LINES_TO_KEEP=$((TOTAL_LINES - 1))
    
    # Insert the new method before the final closing brace
    head -n "$LINES_TO_KEEP" "$TARGET_FILE" > "$TEMP_FILE"
    echo "$DEMO_CODE" >> "$TEMP_FILE"
    echo "}" >> "$TEMP_FILE"
    
    mv "$TEMP_FILE" "$TARGET_FILE"
    
    echo "  Added isSystemHealthy() method"
fi

echo ""
echo -e "${GREEN}Step 3: Committing changes${NC}"

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}  [DRY RUN] Would commit with message:${NC}"
    echo "  'demo: Add health check method to showcase Test Intelligence'"
else
    git add "$TARGET_FILE"
    git commit -m "demo: Add health check method to showcase Test Intelligence

This commit adds a simple isSystemHealthy() method to ChaosService.java
to demonstrate Harness Test Intelligence.

Expected results:
- Total tests: 72
- Tests selected: ~29 (ChaosService-related)
- Tests skipped: ~43 (unaffected)
- Time savings: ~60%

Timestamp: $TIMESTAMP"
    
    echo "  Committed changes"
fi

echo ""
if [ "$PUSH_BRANCH" = true ]; then
    echo -e "${GREEN}Step 4: Pushing to remote${NC}"
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}  [DRY RUN] Would push branch: $BRANCH_NAME${NC}"
    else
        git push -u origin "$BRANCH_NAME"
        echo "  Pushed to origin/$BRANCH_NAME"
    fi
else
    echo -e "${YELLOW}Step 4: Skipped push (use --push to push)${NC}"
fi

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     DEMO READY                                               ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}What to show in Harness:${NC}"
echo "  1. Navigate to CI Pipeline"
echo "  2. Run pipeline with branch: $BRANCH_NAME"
echo "  3. Open the 'Tests' tab after completion"
echo "  4. Show Test Intelligence visualization:"
echo "     - Tests Selected vs Tests Skipped"
echo "     - Time saved by running only affected tests"
echo ""
echo -e "${GREEN}Expected Results:${NC}"
echo "  ┌─────────────────────────────────────┐"
echo "  │ Total Tests:     72                 │"
echo "  │ Tests Selected:  ~29 (40%)          │"
echo "  │ Tests Skipped:   ~43 (60%)          │"
echo "  │ Time Savings:    ~60%               │"
echo "  └─────────────────────────────────────┘"
echo ""

if [ "$PUSH_BRANCH" = false ] && [ "$DRY_RUN" = false ]; then
    echo -e "${YELLOW}To push and trigger CI:${NC}"
    echo "  git push -u origin $BRANCH_NAME"
    echo ""
fi

echo -e "${YELLOW}To clean up after demo:${NC}"
echo "  git checkout main"
echo "  git branch -D $BRANCH_NAME"
if [ "$PUSH_BRANCH" = true ]; then
    echo "  git push origin --delete $BRANCH_NAME"
fi
