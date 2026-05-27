#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# 1. Environment & Variables Setup
# -----------------------------------------------------------------------------
PROJECT_NAME="$(tr -d '\r\n' < "$HOME/Metabarcoding_Azure/current_project_name.txt")"

# Source Azure credentials and configuration
source "$HOME/azure_blob_info.sh"

# Clean carriage returns/newlines from Azure configuration variables
STORAGE_ACCOUNT="$(echo "$STORAGE_ACCOUNT" | tr -d '\r\n[:space:]')"
CONTAINER="$(echo "$CONTAINER" | tr -d '\r\n[:space:]')"
BLOB_PREFIX="$(echo "$BLOB_PREFIX" | tr -d '\r\n[:space:]')"
SAS_TOKEN="$(echo "$AZURE_STORAGE_SAS_TOKEN" | tr -d '\r\n[:space:]')"

# Strip leading '?' from SAS token and trailing '/' from prefix if present
SAS_TOKEN="${SAS_TOKEN#\?}"
BLOB_PREFIX="${BLOB_PREFIX%/}"

# Setup output directories and files
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
# Use az storage, clean it, and pass it directly to the temporary file
az storage blob list \
  --account-name "$STORAGE_ACCOUNT" \
  --container-name "$CONTAINER" \
  --prefix "${BLOB_PREFIX}/" \
  --sas-token "$SAS_TOKEN" \
  --query "[].name" \
  -o tsv > "$TMP_LIST"

# -----------------------------------------------------------------------------
# 4. Generate Samplesheet
# -----------------------------------------------------------------------------
# Initialize samplesheet with header
echo -e "sampleID\tforwardReads\treverseReads\trun" > "$OUTPUT_FILE"

# CRITICAL FIX: Instead of relying on tr to drop \r, we use grep -o to extract ONLY
# the valid path characters, leaving behind any carriage returns or hidden artifacts.
grep -o '[A-Za-z0-9_\.\/-]*_R1_001\.fastq\.gz' "$TMP_LIST" | while IFS= read -r fwd_blob; do
  
  # Isolate the clean file name
  fname="$(basename "$fwd_blob")"

  # 1. Extract clean SampleID (e.g., B12A1_02_4_S14_L001)
  sampleID="${fname%_R1_001.fastq.gz}"

  # 2. Create the R2 string path from the clean fwd_blob variable
  rev_blob="${fwd_blob/_R1_/_R2_}"

  # 3. Double check verification using a clean grep lookup
  if ! grep -qF "$rev_blob" "$TMP_LIST"; then
    echo "WARNING: No matching R2 found for: $fwd_blob" >&2
    echo "Attempted to look for: $rev_blob" >&2
    continue
  fi

  # 4. Construct URIs
  fwd_uri="az://${CONTAINER}/${fwd_blob}"
  rev_uri="az://${CONTAINER}/${rev_blob}"

  # 5. Append to samplesheet
  echo -e "${sampleID}\t${fwd_uri}\t${rev_uri}\t${RUN_VALUE}" >> "$OUTPUT_FILE"
done

# Cleanup
rm -f "$TMP_LIST"

echo "Success! Sample sheet written to: $OUTPUT_FILE"
