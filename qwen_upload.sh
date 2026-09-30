#!/bin/bash
set -euo pipefail

MODEL_DIR="Qwen3-8B"
CHUNK_SIZE="1800m"
MAX_BYTES=2147483648

echo "=========================================="
echo " Qwen3-8B MASTER UPLOAD"
echo "=========================================="

git fetch origin main
git lfs install

# Never upload original >2GB safetensors
touch .gitignore
grep -qxF 'Qwen3-8B/*.safetensors' .gitignore || \
    echo 'Qwen3-8B/*.safetensors' >> .gitignore

# Store split chunks in Git LFS
touch .gitattributes
grep -qxF 'Qwen3-8B/*.safetensors.part-* filter=lfs diff=lfs merge=lfs -text' .gitattributes || \
    echo 'Qwen3-8B/*.safetensors.part-* filter=lfs diff=lfs merge=lfs -text' >> .gitattributes

git add .gitignore .gitattributes
git commit -m "Configure Qwen3-8B split upload" 2>/dev/null || true

# Push any existing local commits.
# This will push shard 3 (81cb000) in your current situation.
if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
    echo
    echo "==> Existing local commit found."
    echo "==> Pushing it first..."
    git push origin main
fi

# ============================================================
# PROCESS ALL 5 SHARDS
# ============================================================

for i in 1 2 3 4 5; do

    NUM=$(printf "%05d" "$i")

    ORIGINAL="$MODEL_DIR/model-${NUM}-of-00005.safetensors"
    PREFIX="${ORIGINAL}.part-"

    echo
    echo "=========================================="
    echo " SHARD $i"
    echo "=========================================="

    # Check GitHub for existing chunks
    REMOTE_COUNT=$(git ls-tree -r origin/main --name-only | \
        grep -c "^${PREFIX}" || true)

    if [ "$REMOTE_COUNT" -gt 0 ]; then
        echo "==> Shard $i already uploaded."
        echo "==> Skipping."
        continue
    fi

    # Check whether chunks already exist locally
    EXISTING_COUNT=$(find "$MODEL_DIR" \
        -maxdepth 1 \
        -name "model-${NUM}-of-00005.safetensors.part-*" \
        | wc -l | tr -d ' ')

    if [ "$EXISTING_COUNT" -eq 0 ]; then

        if [ ! -f "$ORIGINAL" ]; then
            echo "ERROR: Missing:"
            echo "$ORIGINAL"
            exit 1
        fi

        echo "==> Splitting $ORIGINAL..."

        split -b "$CHUNK_SIZE" -a 3 "$ORIGINAL" "$PREFIX"

    else
        echo "==> Found $EXISTING_COUNT existing chunks."
        echo "==> Using them."
    fi

    echo
    echo "Chunks:"
    ls -lh "${PREFIX}"*

    echo
    echo "==> Checking chunk sizes..."

    for f in "${PREFIX}"*; do

        SIZE=$(stat -f%z "$f")

        if [ "$SIZE" -ge "$MAX_BYTES" ]; then
            echo "ERROR: Chunk is >= 2 GiB:"
            echo "$f"
            exit 1
        fi

        echo "OK: $(basename "$f") - $(du -h "$f" | cut -f1)"

    done

    echo
    echo "==> Adding shard $i..."

    git add "${PREFIX}"*

    if ! git diff --cached --quiet; then
        git commit -m "Add Qwen3-8B shard $i chunks"
    fi

    echo
    echo "=========================================="
    echo " PUSHING SHARD $i"
    echo "=========================================="

    git push origin main

    echo
    echo "==> Shard $i successfully pushed."

    # Only delete chunks AFTER successful push
    rm -f "${PREFIX}"*

    echo "==> Local chunks removed."

    echo
    echo "==> Disk space:"
    df -h .

done

# ============================================================
# CREATE RECONSTRUCTION SCRIPT
# ============================================================

echo
echo "=========================================="
echo " CREATING RECONSTRUCTION SCRIPT"
echo "=========================================="

cat > reconstruct_qwen.sh <<'RECONSTRUCT'
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
RECONSTRUCT

chmod +x reconstruct_qwen.sh

# ============================================================
# ADD METADATA + SCRIPTS
# ============================================================

echo
echo "=========================================="
echo " ADDING METADATA + SCRIPTS"
echo "=========================================="

git add \
    Qwen3-8B/LICENSE \
    Qwen3-8B/README.md \
    Qwen3-8B/config.json \
    Qwen3-8B/generation_config.json \
    Qwen3-8B/merges.txt \
    Qwen3-8B/model.safetensors.index.json \
    Qwen3-8B/tokenizer.json \
    Qwen3-8B/tokenizer_config.json \
    Qwen3-8B/vocab.json \
    reconstruct_qwen.sh

# Add this master script itself
SCRIPT_NAME="$(basename "$0")"
git add "$SCRIPT_NAME"

if ! git diff --cached --quiet; then
    git commit -m "Add Qwen3-8B metadata and reconstruction scripts"
fi

echo
echo "=========================================="
echo " FINAL PUSH"
echo "=========================================="

git push origin main

echo
echo "=========================================="
echo " QWEN3-8B UPLOAD COMPLETE"
echo "=========================================="

echo
echo "On office laptop:"
echo
echo "    ./reconstruct_qwen.sh"
echo