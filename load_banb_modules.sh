#!/bin/bash
# Load all banb_* modules from a given directory

# Resolve the directory where this script resides
BANB_LIB_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

if [[ ! -d "$BANB_LIB_DIR" ]]; then
  echo "❌ Module directory not found: $BANB_LIB_DIR"
  return 1
fi

# Load common functions first
if [[ -f "$BANB_LIB_DIR/banb_common.sh" ]]; then
  source "$BANB_LIB_DIR/banb_common.sh"
  echo "✅ Loaded: banb_common.sh"
fi

# Load other modules
for file in "$BANB_LIB_DIR"/banb_*.sh; do
  # Skip common file as it's already loaded
  [[ "$file" == "$BANB_LIB_DIR/banb_common.sh" ]] && continue
  [[ -f "$file" ]] && source "$file" && echo "✅ Loaded: $(basename "$file")"
done
