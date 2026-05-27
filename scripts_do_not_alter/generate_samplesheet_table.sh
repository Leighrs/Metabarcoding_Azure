#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# 1. Environment & Variables Setup (with Aggressive \r Cleanup)
# -----------------------------------------------------------------------------
PROJECT_NAME="$(tr -d '\r\n' < "$HOME/Metabarcoding_Azure/current_project_name.txt")"

# Source Azure credentials and configuration
source "$HOME/azure_blob_info.sh"

# STRIP ALL HIDDEN CARRIAGE RETURNS (\r) AND NEWLINES (\n)
STORAGE_ACCOUNT="$(echo "$STORAGE_ACCOUNT" | tr -d '\r\n')"
CONTAINER="$(echo "$CONTAINER" | tr -d '\r\n')"
BLOB_PREFIX="$(echo "$BLOB_PREFIX" | tr -d '\r\n')"
SAS_TOKEN="$(echo "$AZURE_STORAGE_SAS_TOKEN" | tr -d '\r\n')"

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
# Explicitly use tr -d '\r' to ensure absolutely no Windows line endings land in our temp file
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
# Initialize samplesheet with header
echo -e "sampleID\tforwardReads\treverseReads\trun" > "$OUTPUT_FILE"

# Process only the forward reads, ensuring we strip any trailing artifacts
grep '_R1_001.fastq.gz$' "$TMP_LIST" | while IFS= read -r fwd_blob; do
  # Double check: ensure the line itself is stripped of any hidden '\r'
  fwd_blob="$(echo "$fwd_blob" | tr -d '\r\n')"
  
  fname="$(basename "$fwd_blob")"

  # Strip the R1 suffix to get a unique sample ID
  sampleID="${fname%_R1_001.fastq.gz}"

  # Swap _R1_ for _R2_ to find the matching reverse read blob path
  rev_blob="${fwd_blob/_R1_/_R2_}"

  # Construct URIs
  fwd_uri="az://${CONTAINER}/${fwd_blob}"
  rev_uri="az://${CONTAINER}/${rev_blob}"

  # Append to samplesheet
  echo -e "${sampleID}\t${fwd_uri}\t${rev_uri}\t${RUN_VALUE}" >> "$OUTPUT_FILE"
done

# Cleanup
rm -f "$TMP_LIST"

echo "Success! Sample sheet written to: $OUTPUT_FILE"
