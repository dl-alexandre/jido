#!/bin/bash
#
# CI Guard: Check for Eager Interpolated Logger Calls
#
# This script detects non-lazy logging patterns that can cause:
# - Unnecessary computation when log level is disabled
# - Performance issues on hot paths
# - Memory pressure from large interpolated strings
#
# Usage:
#   ./scripts/check_lazy_logging.sh [directory]
#
# Returns:
#   0 - No violations found
#   1 - Violations detected
#
# Integrate into CI:
#   - mix quality
#   - GitHub Actions
#   - pre-commit hooks
#

set -euo pipefail

# Default to lib/ directory if no argument provided
TARGET_DIR="${1:-lib}"

# Colors for output (disabled in CI)
if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  NC='\033[0m' # No Color
else
  RED=''
  GREEN=''
  YELLOW=''
  NC=''
fi

echo "🔍 Checking for eager interpolated Logger calls in ${TARGET_DIR}/..."
echo ""

# Track violations
VIOLATIONS=0

# Check if ripgrep (rg) is available
if command -v rg &> /dev/null; then
  RIPGREP_AVAILABLE=true
else
  RIPGREP_AVAILABLE=false
  echo "${YELLOW}Warning: ripgrep (rg) not found, falling back to grep${NC}"
  echo "For better performance, install ripgrep: https://github.com/BurntSushi/ripgrep"
  echo ""
fi

# Patterns for eager interpolation (BAD)
# These match Logger calls with string interpolation using #{...}
BAD_PATTERNS=(
  # Logger calls with string interpolation (NOT inside a function)
  'Logger\.(debug|info|warning|warn|error)\s*\(\s*"[^"]*#{[^}]+}[^"]*"'
  # Multi-line string interpolation in Logger
  'Logger\.(debug|info|warning|warn|error)\s*\(\s*"""[^"]*#{[^}]+}'
)

# Patterns that are allowed (GOOD)
# These should NOT be flagged as violations
GOOD_PATTERNS=(
  # Function-based lazy logging (fn -> ... end or &(...))
  'Logger\.(debug|info|warning|warn|error)\s*\(\s*fn\s*->'
  'Logger\.(debug|info|warning|warn|error)\s*\(\s*&'
  # Existing lazy logging functions
  'Jido\.Observe\.(debug|info|warning|error)\s*\(\s*fn'
  # Comments explaining the logging
  '#\s*Logger\.'
  # Strings in test files (often legitimate)
  'test.*Logger'
)

# Function to check if a match should be excluded (is actually OK)
should_exclude() {
  local line="$1"
  local file="$2"

  # Exclude test files (they often need eager logging for assertions)
  if [[ "$file" == *test* ]] || [[ "$file" == *spec* ]]; then
    return 0
  fi

  # Exclude if line contains a function definition (fn ->)
  if echo "$line" | grep -qE 'fn\s*->|fn\s*\(|&\('; then
    return 0
  fi

  # Exclude commented lines
  if echo "$line" | grep -qE '^\s*#'; then
    return 0
  fi

  # Exclude if using Jido.Observe lazy logging
  if echo "$line" | grep -qE 'Jido\.Observe\.(debug|info|warning|error)\s*\(\s*fn'; then
    return 0
  fi

  # Exclude if using Log.log_lazy
  if echo "$line" | grep -qE 'Log\.log_lazy|Jido\.Observe\.Log\.log_lazy'; then
    return 0
  fi

  return 1
}

# Function to check a file for violations
check_file() {
  local file="$1"
  local line_num=0
  local has_violations=false

  while IFS= read -r line; do
    ((line_num++))

    # Skip empty lines
    [[ -z "$line" ]] && continue

    # Check for bad patterns
    if echo "$line" | grep -qE 'Logger\.(debug|info|warning|warn|error)\s*\(\s*"[^"]*#[^{]*{[^}]*}'; then

      # Check if this should be excluded
      if ! should_exclude "$line" "$file"; then
        if [[ "$has_violations" == "false" ]]; then
          echo "${RED}❌ VIOLATION${NC}: ${file}"
          has_violations=true
        fi

        echo "   Line ${line_num}: ${line}"
        echo ""
        ((VIOLATIONS++))
      fi
    fi
  done < "$file"
}

# Find all Elixir files and check them
if [ "$RIPGREP_AVAILABLE" = true ]; then
  # Use ripgrep for faster searching
  while IFS= read -r file; do
    check_file "$file"
  done < <(rg --type elixir -l 'Logger\.' "${TARGET_DIR}" 2>/dev/null || true)
else
  # Fallback to find + grep
  while IFS= read -r file; do
    check_file "$file"
  done < <(find "${TARGET_DIR}" -name "*.ex" -o -name "*.exs" 2>/dev/null | xargs grep -l 'Logger\.' 2>/dev/null || true)
fi

# Summary
echo ""
echo "=========================================="
if [ $VIOLATIONS -eq 0 ]; then
  echo "${GREEN}✅ No eager interpolated Logger calls found!${NC}"
  echo "All logging follows the lazy logging policy."
  echo ""
  echo "Good patterns to use:"
  echo "  • Jido.Observe.debug(fn -> \"msg: \#{value}\" end)"
  echo "  • Logger.debug(fn -> \"msg: \#{value}\" end)"
  echo "  • Log.log_lazy(:debug, fn -> \"msg: \#{value}\" end)"
  exit 0
else
  echo "${RED}❌ Found ${VIOLATIONS} eager interpolated Logger call(s)${NC}"
  echo ""
  echo "Fix by converting to lazy logging:"
  echo ""
  echo "  BAD (eager - always evaluated):"
  echo "    Logger.info(\"Value: \#{expensive_call()}\")"
  echo ""
  echo "  GOOD (lazy - only when enabled):"
  echo "    Jido.Observe.info(fn -> \"Value: \#{expensive_call()}\" end)"
  echo "    Logger.info(fn -> \"Value: \#{expensive_call()}\" end)"
  echo "    Log.log_lazy(:info, fn -> \"Value: \#{expensive_call()}\" end)"
  echo ""
  echo "See guides/observability_policy.md for full policy."
  exit 1
fi
