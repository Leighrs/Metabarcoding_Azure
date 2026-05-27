#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="$(tr -d '\r\n' < "$HOME/Metabarcoding_Azure/current_project_name.txt")"

source "$HOME/azure_blob_info.sh"

STORAGE_ACCOUNT="$(printf '%s' "$STORAGE_ACCOUNT" | tr -d '\r\n')"
CONTAINER="$(printf '%s' "$CONTAINER" | tr -d '\r\n')"
BLOB_PREFIX="$(printf '%s' "$BLOB_PREFIX" | tr -d '\r\n')"
SAS_TOKEN="$(printf '%s' "$AZURE_STORAGE_SAS_TOKEN" | tr -d '\r\n')"
SAS_TOKEN="${SAS_TOKEN#\?}"
BLOB_PREFIX="${BLOB_PREFIX%/}"

OUTPUT_DIR="$HOME/Metabarcoding_Azure/$PROJECT_NAME/samplesheet"
OUTPUT_FILE="$OUTPUT_DIR/${PROJECT_NAME}_samplesheet.txt"
mkdir -p "$OUTPUT_DIR"

echo "Did you sequence samples using multiple sequencing runs? [yes/no]"
read -r multi_runs

case "$multi_runs" in
  no|No|NO|n|N) RUN_VALUE="A" ;;
  yes|Yes|YES|y|Y) RUN_VALUE="" ;;
  *) echo "Invalid response"; exit 1 ;;
esac

TMP_LIST="$(mktemp)"

az storage blob list \
  --account-name "$STORAGE_ACCOUNT" \
  --container-name "$CONTAINER" \
  --prefix "${BLOB_PREFIX}/" \
  --sas-token "$SAS_TOKEN" \
  --query "[].name" \
  -o tsv \
  | tr -d '\r' > "$TMP_LIST"

echo "R1 files found:"
grep '_R1_' "$TMP_LIST" || true

echo "R2 files found:"
grep '_R2_' "$TMP_LIST" || true

echo -e "sampleID\tforwardReads\treverseReads\trun" > "$OUTPUT_FILE"

grep '_R1_001.fastq.gz$' "$TMP_LIST" | while IFS= read -r fwd_blob; do
  fname="$(basename "$fwd_blob")"

  sampleID="$(echo "$fname" | sed 's/_R1_001.fastq.gz//' | awk -F'_' '{print $1"_"$2}')"

  rev_blob="$(echo "$fwd_blob" | sed 's/_R1_001.fastq.gz$/_R2_001.fastq.gz/')"

  fwd_uri="az://${CONTAINER}/${fwd_blob}"
  rev_uri="az://${CONTAINER}/${rev_blob}"

  echo -e "${sampleID}\t${fwd_uri}\t${rev_uri}\t${RUN_VALUE}" >> "$OUTPUT_FILE"
done

rm -f "$TMP_LIST"

echo "Sample sheet written to: $OUTPUT_FILE"
