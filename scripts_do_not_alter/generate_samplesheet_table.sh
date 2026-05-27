#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# 1. Environment & Variables Setup
# -----------------------------------------------------------------------------
PROJECT_NAME="$(tr -d '\r\n' < "$HOME/Metabarcoding_Azure/current_project_name.txt")"

# Source Azure credentials and configuration
source "$HOME/azure_blob_info.sh"

# Clean variables cleanly
STORAGE_ACCOUNT="$(echo "$STORAGE_ACCOUNT" | tr -d '\r\n[:space:]')"
CONTAINER="$(echo "$CONTAINER" | tr -d '\r\n[:space:]')"
BLOB_PREFIX="$(echo "$BLOB_PREFIX" | tr -d '\r\n[:space:]')"
SAS_TOKEN="$(echo "$AZURE_STORAGE_SAS_TOKEN" | tr -d '\r\n[:space:]')"

SAS_TOKEN="${SAS_TOKEN#\?}"
BLOB_PREFIX="${BLOB_PREFIX%/}"

OUTPUT_DIR="$HOME/Metabarcoding_Azure/$PROJECT_NAME/samplesheet"
OUTPUT_FILE="$OUTPUT_DIR/${PROJECT_NAME}_samplesheet.txt"
mkdir -p "$OUTPUT_DIR"

# -----------------------------------------------------------------------------
# 2. User Input handling
# -----------------------------------------------------------------------------
echo "Did you sequence samples using multiple sequencing runs? [yes/no]"
read -r multi_runs

case "$multi_runs" in
  no|No|NO|n|N)   RUN_VALUE="A" ;;
  yes|Yes|YES|y|Y) RUN_VALUE="" ;;
  *) echo "Invalid response"; exit 1 ;;
esac

# -----------------------------------------------------------------------------
# 3. Fetch Blob List from Azure
# -----------------------------------------------------------------------------
TMP_LIST="$(mktemp)"

echo "Fetching blob list from Azure..."
az storage blob list \
  --account-name "$STORAGE_ACCOUNT" \
  --container-name "$CONTAINER" \
  --prefix "${BLOB_PREFIX}/" \
  --sas-token "$SAS_TOKEN" \
  --query "[].name" \
  -o tsv \
  | tr -d '\r' > "$TMP_LIST"

# -----------------------------------------------------------------------------
# 4. Generate Samplesheet
# -----------------------------------------------------------------------------
echo -e "sampleID\tforwardReads\treverseReads\trun" > "$OUTPUT_FILE"

# Loop through R1 files found in the temp list
grep '_R1_001.fastq.gz$' "$TMP_LIST" | while IFS= read -r fwd_blob; do
  
  # Absolute sanitation check of the incoming line
  fwd_blob="$(echo "$fwd_blob" | tr -d '\r\n[:space:]')"
  [ -z "$fwd_blob" ] && continue

  fname="$(basename "$fwd_blob")"

  # 1. Extract Sample ID by chopping off the trailing _R1_001.fastq.gz completely
  sampleID="$(echo "$fname" | sed 's/_R1_001.fastq.gz$//')"

  # 2. CRITICAL FIX: Explicitly target the END of the string ($) using sed 
  # to swap R1 for R2. This completely avoids broken Bash internal variable expansion.
  rev_blob="$(echo "$fwd_blob" | sed 's/_R1_001.fastq.gz$/_R2_001.fastq.gz/')"

  # 3. Check if the generated R2 file exists in our master list
  if ! grep -qF "$rev_blob" "$TMP_LIST"; then
    echo "WARNING: No matching R2 found for: $fwd_blob" >&2
    echo "Attempted to look for: $rev_blob" >&2
    continue
  fi

  # 4. Construct URIs
  fwd_uri="az://${CONTAINER}/${fwd_blob}"
  rev_uri="az://${CONTAINER}/${rev_blob}"

  # 5. Output to samplesheet
  echo -e "${sampleID}\t${fwd_uri}\t${rev_uri}\t${RUN_VALUE}" >> "$OUTPUT_FILE"
done

rm -f "$TMP_LIST"

echo "Success! Sample sheet written to: $OUTPUT_FILE"
