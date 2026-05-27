#!/bin/bash

set -o pipefail

#################################
# READ PROJECT NAME
#################################

PROJECT_FILE="$HOME/Metabarcoding_Azure/current_project_name.txt"

if [[ ! -f "$PROJECT_FILE" ]]; then
  echo "ERROR: Missing $PROJECT_FILE"
  exit 1
fi

PROJECT_NAME="$(cat "$PROJECT_FILE" | tr -d '\r\n')"

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

# Remove hidden Windows carriage returns from settings
STORAGE_ACCOUNT="${STORAGE_ACCOUNT//$'\r'/}"
CONTAINER="${CONTAINER//$'\r'/}"
BLOB_PREFIX="${BLOB_PREFIX//$'\r'/}"
AZURE_STORAGE_SAS_TOKEN="${AZURE_STORAGE_SAS_TOKEN//$'\r'/}"

# Remove trailing slash from BLOB_PREFIX if present
BLOB_PREFIX="${BLOB_PREFIX%/}"

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
  echo "ERROR: Azure CLI az not found in this environment."
  exit 1
fi

SAS_TOKEN="${AZURE_STORAGE_SAS_TOKEN:-}"

if [[ -z "$SAS_TOKEN" ]]; then
  echo "ERROR: AZURE_STORAGE_SAS_TOKEN is not set from $AZ_INFO."
  exit 1
fi

# Remove leading ? if present and remove hidden line endings
SAS_TOKEN="${SAS_TOKEN#\?}"
SAS_TOKEN="$(printf '%s' "$SAS_TOKEN" | tr -d '\r\n')"

echo "Using container: $CONTAINER"
echo "Using prefix: ${BLOB_PREFIX}/"
echo "SAS token present: yes"

#################################
# ASK USER ABOUT MULTIPLE RUNS
#################################

echo "Did you sequence samples using multiple sequencing runs? [yes/no]"
read -r multi_runs
multi_runs="$(printf '%s' "$multi_runs" | tr -d '\r\n')"

if [[ "$multi_runs" =~ ^([Nn][Oo]|[Nn])$ ]]; then
  RUN_VALUE="A"
  echo "All samples will be assigned to run 'A'."
elif [[ "$multi_runs" =~ ^([Yy][Ee][Ss]|[Yy])$ ]]; then
  RUN_VALUE=""
  echo "NOTE: You will need to manually edit the 'run' column in the samplesheet."
  echo "Use letters, e.g. A, B, etc., to distinguish sequencing runs."
else
  echo "Invalid response. Please answer yes or no."
  exit 1
fi

#################################
# SAMPLE NAME PARSING FUNCTION
#################################

extract_sample_id() {
  local filename="$1"

  filename="$(printf '%s' "$filename" | tr -d '\r\n')"

  # Remove R1 suffix
  local base="${filename%_R1_001.fastq.gz}"

  # Extract first two underscore-separated fields
  echo "$base" | awk -F'_' '{print $1"_"$2}'
}

#################################
# LIST R1 BLOBS
#################################

echo "Listing R1 FASTQ files..."

mapfile -t FWD_BLOBS < <(
  az storage blob list \
    --account-name "$STORAGE_ACCOUNT" \
    --container-name "$CONTAINER" \
    --prefix "${BLOB_PREFIX}/" \
    --sas-token "$SAS_TOKEN" \
    --query "[?ends_with(name, '_R1_001.fastq.gz')].name" \
    -o tsv | tr -d '\r'
)

if [[ "${#FWD_BLOBS[@]}" -eq 0 ]]; then
  echo "ERROR: No R1 FASTQs found under: az://${CONTAINER}/${BLOB_PREFIX}/"
  echo "If you saw an SSL or Azure error above, fix that first."
  exit 1
fi

echo "Found ${#FWD_BLOBS[@]} R1 FASTQ files."

#################################
# LIST R2 BLOBS
#################################

echo "Listing R2 FASTQ files..."

mapfile -t REV_BLOBS < <(
  az storage blob list \
    --account-name "$STORAGE_ACCOUNT" \
    --container-name "$CONTAINER" \
    --prefix "${BLOB_PREFIX}/" \
    --sas-token "$SAS_TOKEN" \
    --query "[?ends_with(name, '_R2_001.fastq.gz')].name" \
    -o tsv | tr -d '\r'
)

echo "Found ${#REV_BLOBS[@]} R2 FASTQ files."

#################################
# WRITE SAMPLE SHEET HEADER
#################################

echo -e "sampleID\tforwardReads\treverseReads\trun" > "$OUTPUT_FILE"

#################################
# PROCESS BLOBS
#################################

for fwd_blob in "${FWD_BLOBS[@]}"; do
  # Remove hidden line endings
  fwd_blob="$(printf '%s' "$fwd_blob" | tr -d '\r\n')"

  fname="$(basename "$fwd_blob")"
  sampleID="$(extract_sample_id "$fname")"

  # Build expected R2 blob by replacing R1 with R2
  rev_blob="${fwd_blob/_R1_001.fastq.gz/_R2_001.fastq.gz}"
  rev_blob="$(printf '%s' "$rev_blob" | tr -d '\r\n')"

  fwd_uri="az://${CONTAINER}/${fwd_blob}"

  if printf '%s\n' "${REV_BLOBS[@]}" | tr -d '\r' | grep -Fxq "$rev_blob"; then
    rev_uri="az://${CONTAINER}/${rev_blob}"
  else
    echo "WARNING: No matching R2 found."
    printf '  Forward:     %q\n' "$fwd_blob"
    printf '  Expected R2: %q\n' "$rev_blob"
    rev_uri=""
  fi

  echo -e "${sampleID}\t${fwd_uri}\t${rev_uri}\t${RUN_VALUE}" >> "$OUTPUT_FILE"
done

#################################
# DONE
#################################

echo "Sample sheet written to: $OUTPUT_FILE"
echo "Fastq test data input folder: az://${CONTAINER}/${BLOB_PREFIX}/"
