#!/usr/bin/env bash

set -euo pipefail

#################################
# READ PROJECT NAME
#################################

PROJECT_FILE="$HOME/Metabarcoding_Azure/current_project_name.txt"

if [[ ! -f "$PROJECT_FILE" ]]; then
  echo "ERROR: Missing $PROJECT_FILE"
  exit 1
fi

PROJECT_NAME="$(tr -d '\r\n' < "$PROJECT_FILE")"

#################################
# LOAD AZURE SETTINGS
#################################

AZ_INFO="$HOME/azure_blob_info.sh"

if [[ ! -f "$AZ_INFO" ]]; then
  echo "ERROR: Missing $AZ_INFO"
  exit 1
fi

# shellcheck disable=SC1090
source "$AZ_INFO"

# Clean possible hidden Windows characters
STORAGE_ACCOUNT="$(printf '%s' "${STORAGE_ACCOUNT:-}" | tr -d '\r\n')"
CONTAINER="$(printf '%s' "${CONTAINER:-}" | tr -d '\r\n')"
BLOB_PREFIX="$(printf '%s' "${BLOB_PREFIX:-}" | tr -d '\r\n')"
AZURE_STORAGE_SAS_TOKEN="$(printf '%s' "${AZURE_STORAGE_SAS_TOKEN:-}" | tr -d '\r\n')"

# Remove trailing slash from prefix
BLOB_PREFIX="${BLOB_PREFIX%/}"

if [[ -z "$STORAGE_ACCOUNT" || -z "$CONTAINER" || -z "$BLOB_PREFIX" ]]; then
  echo "ERROR: STORAGE_ACCOUNT, CONTAINER, or BLOB_PREFIX is empty."
  echo "Check $AZ_INFO"
  exit 1
fi

SAS_TOKEN="${AZURE_STORAGE_SAS_TOKEN#\?}"

if [[ -z "$SAS_TOKEN" ]]; then
  echo "ERROR: AZURE_STORAGE_SAS_TOKEN is empty in $AZ_INFO"
  exit 1
fi

#################################
# OUTPUT FILE
#################################

OUTPUT_DIR="$HOME/Metabarcoding_Azure/$PROJECT_NAME/samplesheet"
OUTPUT_FILE="$OUTPUT_DIR/${PROJECT_NAME}_samplesheet.txt"

mkdir -p "$OUTPUT_DIR"

#################################
# CHECK AZURE CLI
#################################

if ! command -v az >/dev/null 2>&1; then
  echo "ERROR: Azure CLI az not found."
  exit 1
fi

echo "Using container: $CONTAINER"
echo "Using prefix: ${BLOB_PREFIX}/"
echo "SAS token present: yes"

#################################
# ASK USER ABOUT MULTIPLE RUNS
#################################

echo "Did you sequence samples using multiple sequencing runs? [yes/no]"
read -r multi_runs
multi_runs="$(printf '%s' "$multi_runs" | tr -d '\r\n')"

case "$multi_runs" in
  no|No|NO|n|N)
    RUN_VALUE="A"
    echo "All samples will be assigned to run 'A'."
    ;;
  yes|Yes|YES|y|Y)
    RUN_VALUE=""
    echo "NOTE: You will need to manually edit the 'run' column in the samplesheet."
    echo "Use letters, e.g. A, B, etc., to distinguish sequencing runs."
    ;;
  *)
    echo "Invalid response. Please answer yes or no."
    exit 1
    ;;
esac

#################################
# SAMPLE NAME FUNCTION
#################################

extract_sample_id() {
  local filename="$1"
  filename="$(printf '%s' "$filename" | tr -d '\r\n')"

  local base="${filename%_R1_001.fastq.gz}"

  echo "$base" | awk -F'_' '{print $1"_"$2}'
}

#################################
# LIST ALL FASTQ BLOBS ONCE
#################################

echo "Listing FASTQ files from Azure..."

TMP_FASTQ_LIST="$(mktemp)"

if ! az storage blob list \
  --account-name "$STORAGE_ACCOUNT" \
  --container-name "$CONTAINER" \
  --prefix "${BLOB_PREFIX}/" \
  --sas-token "$SAS_TOKEN" \
  --query "[?ends_with(name, '.fastq.gz')].name" \
  -o tsv > "$TMP_FASTQ_LIST"; then

  echo "ERROR: Azure blob listing failed."
  echo "This may be an Azure CLI, SAS token, SSL certificate, VPN, or proxy issue."
  rm -f "$TMP_FASTQ_LIST"
  exit 1
fi

# Clean hidden carriage returns
sed -i 's/\r$//' "$TMP_FASTQ_LIST"

R1_COUNT="$(grep -c '_R1_001.fastq.gz$' "$TMP_FASTQ_LIST" || true)"
R2_COUNT="$(grep -c '_R2_001.fastq.gz$' "$TMP_FASTQ_LIST" || true)"

echo "Found $R1_COUNT R1 FASTQ files."
echo "Found $R2_COUNT R2 FASTQ files."

if [[ "$R1_COUNT" -eq 0 ]]; then
  echo "ERROR: No R1 FASTQs found under az://${CONTAINER}/${BLOB_PREFIX}/"
  echo "First few FASTQs found, if any:"
  head "$TMP_FASTQ_LIST"
  rm -f "$TMP_FASTQ_LIST"
  exit 1
fi

#################################
# WRITE SAMPLE SHEET
#################################

echo -e "sampleID\tforwardReads\treverseReads\trun" > "$OUTPUT_FILE"

grep '_R1_001.fastq.gz$' "$TMP_FASTQ_LIST" | while IFS= read -r fwd_blob; do
  fwd_blob="$(printf '%s' "$fwd_blob" | tr -d '\r\n')"

  fname="$(basename "$fwd_blob")"
  sampleID="$(extract_sample_id "$fname")"

  rev_blob="${fwd_blob/_R1_001.fastq.gz/_R2_001.fastq.gz}"

  fwd_uri="az://${CONTAINER}/${fwd_blob}"

  if grep -Fxq "$rev_blob" "$TMP_FASTQ_LIST"; then
    rev_uri="az://${CONTAINER}/${rev_blob}"
  else
    echo "WARNING: No matching R2 found."
    printf '  Forward:     %s\n' "$fwd_blob"
    printf '  Expected R2: %s\n' "$rev_blob"
    rev_uri=""
  fi

  echo -e "${sampleID}\t${fwd_uri}\t${rev_uri}\t${RUN_VALUE}" >> "$OUTPUT_FILE"
done

rm -f "$TMP_FASTQ_LIST"

echo "Sample sheet written to: $OUTPUT_FILE"
echo "Fastq test data input folder: az://${CONTAINER}/${BLOB_PREFIX}/"
