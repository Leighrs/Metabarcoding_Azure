#!/usr/bin/env bash

set -euo pipefail

PROJECT_FILE="$HOME/Metabarcoding_Azure/current_project_name.txt"
AZ_INFO="$HOME/azure_blob_info.sh"

if [[ ! -f "$PROJECT_FILE" ]]; then
  echo "ERROR: Missing $PROJECT_FILE"
  exit 1
fi

if [[ ! -f "$AZ_INFO" ]]; then
  echo "ERROR: Missing $AZ_INFO"
  exit 1
fi

PROJECT_NAME="$(tr -d '\r\n' < "$PROJECT_FILE")"

# shellcheck disable=SC1090
source "$AZ_INFO"

STORAGE_ACCOUNT="$(printf '%s' "${STORAGE_ACCOUNT:-}" | tr -d '\r\n')"
CONTAINER="$(printf '%s' "${CONTAINER:-}" | tr -d '\r\n')"
BLOB_PREFIX="$(printf '%s' "${BLOB_PREFIX:-}" | tr -d '\r\n')"
AZURE_STORAGE_SAS_TOKEN="$(printf '%s' "${AZURE_STORAGE_SAS_TOKEN:-}" | tr -d '\r\n')"

BLOB_PREFIX="${BLOB_PREFIX%/}"
SAS_TOKEN="${AZURE_STORAGE_SAS_TOKEN#\?}"

OUTPUT_DIR="$HOME/Metabarcoding_Azure/$PROJECT_NAME/samplesheet"
OUTPUT_FILE="$OUTPUT_DIR/${PROJECT_NAME}_samplesheet.txt"

mkdir -p "$OUTPUT_DIR"

if ! command -v az >/dev/null 2>&1; then
  echo "ERROR: Azure CLI az not found."
  exit 1
fi

echo "Using container: $CONTAINER"
echo "Using prefix: ${BLOB_PREFIX}/"
echo "SAS token present: yes"

echo "Did you sequence samples using multiple sequencing runs? [yes/no]"
read -r multi_runs

case "$multi_runs" in
  no|No|NO|n|N)
    RUN_VALUE="A"
    ;;
  yes|Yes|YES|y|Y)
    RUN_VALUE=""
    echo "NOTE: Manually edit the run column using A, B, etc."
    ;;
  *)
    echo "Invalid response. Please answer yes or no."
    exit 1
    ;;
esac

extract_sample_id() {
  local filename="$1"
  filename="$(printf '%s' "$filename" | tr -d '\r\n')"

  local base="${filename%_R1_001.fastq.gz}"

  echo "$base" | awk -F'_' '{print $1"_"$2}'
}

TMP_FASTQ_LIST="$(mktemp)"

echo "Listing FASTQ files from Azure..."

az storage blob list \
  --account-name "$STORAGE_ACCOUNT" \
  --container-name "$CONTAINER" \
  --prefix "${BLOB_PREFIX}/" \
  --sas-token "$SAS_TOKEN" \
  --query "[].name" \
  -o tsv \
  | tr -d '\r' \
  | grep '\.fastq\.gz$' > "$TMP_FASTQ_LIST"

R1_COUNT="$(grep -c '_R1_' "$TMP_FASTQ_LIST" || true)"
R2_COUNT="$(grep -c '_R2_' "$TMP_FASTQ_LIST" || true)"

echo "Found $R1_COUNT R1 FASTQ files."
echo "Found $R2_COUNT R2 FASTQ files."

if [[ "$R1_COUNT" -eq 0 ]]; then
  echo "ERROR: No R1 FASTQs found."
  rm -f "$TMP_FASTQ_LIST"
  exit 1
fi

echo -e "sampleID\tforwardReads\treverseReads\trun" > "$OUTPUT_FILE"

grep '_R1_' "$TMP_FASTQ_LIST" | while IFS= read -r fwd_blob; do
  fwd_blob="$(printf '%s' "$fwd_blob" | tr -d '\r\n')"

  fname="$(basename "$fwd_blob")"
  sampleID="$(extract_sample_id "$fname")"

  rev_blob="$(printf '%s' "$fwd_blob" | sed 's/_R1_/_R2_/')"

  fwd_uri="az://${CONTAINER}/${fwd_blob}"

  if grep -Fq "$rev_blob" "$TMP_FASTQ_LIST"; then
    rev_uri="az://${CONTAINER}/${rev_blob}"
  else
    echo "WARNING: No matching R2 found."
    echo "Forward:     $fwd_blob"
    echo "Expected R2: $rev_blob"
    rev_uri=""
  fi

  echo -e "${sampleID}\t${fwd_uri}\t${rev_uri}\t${RUN_VALUE}" >> "$OUTPUT_FILE"
done

rm -f "$TMP_FASTQ_LIST"

echo "Sample sheet written to: $OUTPUT_FILE"
echo "Fastq test data input folder: az://${CONTAINER}/${BLOB_PREFIX}/"
