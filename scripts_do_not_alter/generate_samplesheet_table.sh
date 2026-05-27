#!/bin/bash

set -o pipefail

# Read project name
PROJECT_NAME=$(cat "$HOME/Metabarcoding_Azure/current_project_name.txt")

# Load Azure blob settings
AZ_INFO="$HOME/azure_blob_info.sh"
if [[ ! -f "$AZ_INFO" ]]; then
  echo "ERROR: Missing $AZ_INFO"
  exit 1
fi

# shellcheck disable=SC1090
source "$AZ_INFO"

# Output file
OUTPUT_FILE="$HOME/Metabarcoding_Azure/$PROJECT_NAME/samplesheet/${PROJECT_NAME}_samplesheet.txt"

#################################
# AZURE SETTINGS
#################################

if ! command -v az >/dev/null 2>&1; then
  echo "ERROR: Azure CLI (az) not found in this environment."
  exit 1
fi

SAS_TOKEN="${AZURE_STORAGE_SAS_TOKEN:-}"
if [[ -z "$SAS_TOKEN" ]]; then
  echo "ERROR: AZURE_STORAGE_SAS_TOKEN is not set from $AZ_INFO."
  exit 1
fi
SAS_TOKEN="${SAS_TOKEN#\?}"

echo "Using container: $CONTAINER"
echo "Using prefix: ${BLOB_PREFIX}/"
echo "SAS token present: $([[ -n "$SAS_TOKEN" ]] && echo yes || echo no)"

#################################
# ASK USER ABOUT MULTIPLE RUNS
#################################

echo "Did you sequence samples using multiple sequencing runs? [yes/no]"
read multi_runs

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
# HEADER
#################################

echo -e "sampleID\tforwardReads\treverseReads\trun" > "$OUTPUT_FILE"

##############################################
# SAMPLE NAME PARSING FUNCTION
##############################################

extract_sample_id() {
    local filename="$1"

    # Remove possible hidden carriage returns
    filename="$(printf '%s' "$filename" | tr -d '\r')"

    local base="${filename%_R1_001.fastq.gz}"

    # Extract first two underscore-separated fields
    echo "$base" | awk -F'_' '{print $1"_"$2}'
}

#################################
# LIST FORWARD READ BLOBS R1
#################################

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
  echo "If you saw an SSL or Azure error above, fix that first; this may not mean the files are missing."
  exit 1
fi

#################################
# LIST REVERSE READ BLOBS R2
#################################

mapfile -t REV_BLOBS < <(
  az storage blob list \
    --account-name "$STORAGE_ACCOUNT" \
    --container-name "$CONTAINER" \
    --prefix "${BLOB_PREFIX}/" \
    --sas-token "$SAS_TOKEN" \
    --query "[?ends_with(name, '_R2_001.fastq.gz')].name" \
    -o tsv | tr -d '\r'
)

if [[ "${#REV_BLOBS[@]}" -eq 0 ]]; then
  echo "WARNING: No R2 FASTQs found under: az://${CONTAINER}/${BLOB_PREFIX}/"
fi

#################################
# PROCESS BLOBS -> WRITE az:// URIS
#################################

for fwd_blob in "${FWD_BLOBS[@]}"; do
    fwd_blob="$(printf '%s' "$fwd_blob" | tr -d '\r')"

    fname="$(basename "$fwd_blob")"
    sampleID="$(extract_sample_id "$fname")"

    sample_prefix="${fwd_blob%_R1_001.fastq.gz}"
    rev_blob="${sample_prefix}_R2_001.fastq.gz"

    fwd_uri="az://${CONTAINER}/${fwd_blob}"

    if printf '%s\n' "${REV_BLOBS[@]}" | grep -Fxq "$rev_blob"; then
        rev_uri="az://${CONTAINER}/${rev_blob}"
    else
        echo "WARNING: No matching R2 found for: $fwd_blob"
        echo "Expected: $rev_blob"
        rev_uri=""
    fi

    echo -e "${sampleID}\t${fwd_uri}\t${rev_uri}\t${RUN_VALUE}" >> "$OUTPUT_FILE"
done

echo "Sample sheet written to: $OUTPUT_FILE"
echo "Fastq test data input folder: az://${CONTAINER}/${BLOB_PREFIX}/"
