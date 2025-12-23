#!/usr/bin/env bash
set -euo pipefail

# NixActions - Compile Examples Script
# 
# Compiles all flake packages with "example-" prefix to compiled-examples/
# 
# Usage:
#   ./scripts/compile-examples.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPILED_DIR="$REPO_ROOT/compiled-examples"

cd "$REPO_ROOT"

echo "╔═══════════════════════════════════════════════════════╗"
echo "║ NixActions - Compile Examples                         ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""

# Make compiled-examples writable
chmod -R +w "$COMPILED_DIR" 2>/dev/null || true

# Get all example packages from flake
echo "→ Discovering example packages..."
EXAMPLES=$(nix flake show --json 2>/dev/null | \
  jq -r '.packages."'"$(nix eval --impure --expr 'builtins.currentSystem' --raw)"'" | keys[]' | \
  grep '^example-' | \
  sort)

if [ -z "$EXAMPLES" ]; then
  echo "✗ No example packages found"
  exit 1
fi

EXAMPLE_COUNT=$(echo "$EXAMPLES" | wc -l | tr -d ' ')
echo "→ Found $EXAMPLE_COUNT examples"
echo ""

# Compile each example
SUCCESS_COUNT=0
FAILED_COUNT=0
declare -a FAILED_EXAMPLES

for example in $EXAMPLES; do
  # Remove 'example-' prefix for output filename
  output_name="${example#example-}"
  output_file="$COMPILED_DIR/${output_name}.sh"
  
  echo "==> Compiling $example"
  
  # Build example
  if nix build ".#$example" -o "/tmp/nixactions-result-$output_name" 2>&1 | \
     grep -v "warning: Git tree" | \
     grep -v "^$" | \
     sed 's/^/    /'; then
    true
  fi
  
  # Check if build succeeded
  if [ ! -d "/tmp/nixactions-result-$output_name" ]; then
    echo "    ✗ Build failed"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    FAILED_EXAMPLES+=("$example")
    echo ""
    continue
  fi
  
  # Find the executable (should be in bin/)
  if [ -d "/tmp/nixactions-result-$output_name/bin" ]; then
    executable=$(ls "/tmp/nixactions-result-$output_name/bin/" | head -1)
    
    if [ -n "$executable" ]; then
      # Copy to compiled-examples
      cp "/tmp/nixactions-result-$output_name/bin/$executable" "$output_file"
      chmod +x "$output_file"
      
      # Get file size
      size=$(du -h "$output_file" | cut -f1)
      
      echo "    ✓ $output_file ($size)"
      SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
      echo "    ✗ No executable found in bin/"
      FAILED_COUNT=$((FAILED_COUNT + 1))
      FAILED_EXAMPLES+=("$example")
    fi
  else
    echo "    ✗ No bin/ directory found"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    FAILED_EXAMPLES+=("$example")
  fi
  
  # Cleanup
  rm -f "/tmp/nixactions-result-$output_name"
  echo ""
done

# Summary
echo "╔═══════════════════════════════════════════════════════╗"
echo "║ Summary                                                ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""
echo "Total examples: $EXAMPLE_COUNT"
echo "  ✓ Success: $SUCCESS_COUNT"
echo "  ✗ Failed:  $FAILED_COUNT"
echo ""

if [ $FAILED_COUNT -gt 0 ]; then
  echo "Failed examples:"
  for failed in "${FAILED_EXAMPLES[@]}"; do
    echo "  - $failed"
  done
  echo ""
  exit 1
fi

echo "✓ All examples compiled successfully!"
echo ""
echo "Compiled files in: $COMPILED_DIR"
ls -lh "$COMPILED_DIR"/*.sh | awk '{printf "  - %-30s %5s\n", $9, $5}' | sed "s|$COMPILED_DIR/||"
