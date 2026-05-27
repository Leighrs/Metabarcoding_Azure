#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# 1. Environment & Variables Setup
# -----------------------------------------------------------------------------
PROJECT_NAME="$(tr -d '\r\n' < "$HOME/Metabarcoding_Azure/current_project_name.txt")"

source "$HOME/azure_blob_info.sh"

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
# 3. Fetch Blob List from Azure & Segregate
# -----------------------------------------------------------------------------
TMP_ALL="$(mktemp)"
TMP_R1="$(mktemp)"
TMP_R2="$(mktemp)"

echo "Fetching blob list from Azure..."
az storage blob list \
  --account-name "$STORAGE_ACCOUNT" \
  --container-name "$CONTAINER" \
  --prefix "${BLOB_PREFIX}/" \
  --sas-token "$SAS_TOKEN" \
  --query "[].name" \
  -o tsv > "$TMP_ALL"

# Extract R1 and R2 into separate, cleanly sorted files
grep '_R1_001.fastq.gz' "$TMP_ALL" | sort > "$TMP_R1"
grep '_R2_001.fastq.gz' "$TMP_ALL" | sort > "$TMP_R2"

# -----------------------------------------------------------------------------
# 4. Generate Samplesheet (Side-by-Side Stitching)
# -----------------------------------------------------------------------------
echo "Generating sample sheet..."
echo -e "sampleID\tforwardReads\treverseReads\trun" > "$OUTPUT_FILE"

# 'paste' matches line 1 of R1 with line 1 of R2, line 2 with line 2, etc.
paste "$TMP_R1" "$TMP_R2" | while IFS=$'\t' read -r fwd_blob rev_blob; do
  
  # Clean up any trailing hidden garbage using a hard regular expression strip
  fwd_blob="$(echo "$fwd_blob" | grep -o '^[^[:space:]]*')"
  rev_blob="$(echo "$rev_blob" | grep -o '^[^[:space:]]*')"
  
  # Skip if either is empty
  [ -z "$fwd_blob" ] || [ -z "$rev_blob" ] && continue

  # Extract the filename to make the sample ID
  fname="$(basename "$fwd_blob")"
  
  # Safely slice off the suffix using awk with an explicit field separator
  sampleID="$(echo "$fname" | awk -F'_R1_001.fastq.gz' '{print $1}')"

  # Construct final URIs
  fwd_uri="az://${CONTAINER}/${fwd_blob}"
  rev_uri="az://${CONTAINER}/${rev_blob}"

  # Write directly to the output file
  echo -e "${sampleID}\t${fwd_uri}\t${rev_uri}\t${RUN_VALUE}" >> "$OUTPUT_FILE"
done

# Cleanup temporary files
rm -f "$TMP_ALL" "$TMP_R1" "$TMP_R2"

echo "Success! Sample sheet written to: $OUTPUT_FILE"
