#!/bin/bash
set -euo pipefail

MODEL_DIR="Qwen3-8B"

echo "=========================================="
echo " Qwen3-8B RECONSTRUCTION"
echo "=========================================="

for i in 1 2 3 4 5; do

    NUM=$(printf "%05d" "$i")
    BASE="$MODEL_DIR/model-${NUM}-of-00005.safetensors"

    echo
    echo "=========================================="
    echo " RECONSTRUCTING SHARD $i"
    echo "=========================================="

    PARTS=( "${BASE}.part-"* )

    if [ ! -e "${PARTS[0]}" ]; then
        echo "ERROR: No chunks found for shard $i"
        exit 1
    fi

    echo "Chunks:"
    ls -lh "${BASE}.part-"*

    echo
    echo "==> Combining..."

    cat "${BASE}.part-"* > "$BASE"

    echo "Created:"
    ls -lh "$BASE"

    # Verify reconstructed file size
    EXPECTED_SIZE=$(python3 - "$MODEL_DIR" "$NUM" <<'PY'
import os
import sys

model_dir = sys.argv[1]
num = sys.argv[2]

prefix = f"model-{num}-of-00005.safetensors.part-"

total = sum(
    os.path.getsize(os.path.join(model_dir, f))
    for f in os.listdir(model_dir)
    if f.startswith(prefix)
)

print(total)
PY
)

    ACTUAL_SIZE=$(stat -f%z "$BASE")

    if [ "$EXPECTED_SIZE" -ne "$ACTUAL_SIZE" ]; then
        echo "ERROR: Size mismatch for shard $i!"
        echo "Expected: $EXPECTED_SIZE"
        echo "Actual:   $ACTUAL_SIZE"
        exit 1
    fi

    echo "OK: Shard $i verified."

done

echo
echo "=========================================="
echo " ALL 5 SHARDS RECONSTRUCTED"
echo "=========================================="

ls -lh "$MODEL_DIR"/*.safetensors

echo
echo "Qwen3-8B reconstruction complete."
