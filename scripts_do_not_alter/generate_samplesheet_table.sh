#!/bin/bash

# Read project name
PROJECT_NAME=$(cat "$HOME/Metabarcoding_Azure/current_project_name.txt")

# Load Azure blob settings (exports STORAGE_ACCOUNT, CONTAINER, BLOB_PREFIX, AZURE_STORAGE_SAS_TOKEN)
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
# AZURE SETTINGS (EDIT THESE)
#################################

# Check Azure CLI
if ! command -v az >/dev/null 2>&1; then
  echo "ERROR: Azure CLI (az) not found in this environment."
  exit 1
fi

# Put your SAS token in an environment variable before running:
# export AZURE_STORAGE_SAS_TOKEN='sv=...&...&sig=...'
SAS_TOKEN="${AZURE_STORAGE_SAS_TOKEN:-}"

SAS_TOKEN="${AZURE_STORAGE_SAS_TOKEN:-}"
if [[ -z "$SAS_TOKEN" ]]; then
  echo "ERROR: AZURE_STORAGE_SAS_TOKEN is not set (from $AZ_INFO)."
  exit 1
fi
SAS_TOKEN="${SAS_TOKEN#\?}"


echo "Using container: $CONTAINER"
echo "Using prefix: ${BLOB_PREFIX}/"
echo "SAS token present: $([[ -n "$SAS_TOKEN" ]] && echo yes || echo no)"


#################################
#  ASK USER ABOUT MULTIPLE RUNS
#################################
echo "Did you sequence samples using multiple sequencing runs? [yes/no]"
read multi_runs

if [[ "$multi_runs" =~ ^([Nn][Oo])$ ]]; then
    RUN_VALUE="A"
    echo "All samples will be assigned to run 'A'."
elif [[ "$multi_runs" =~ ^([Yy][Ee][Ss]|[Yy])$ ]]; then
    RUN_VALUE=""
    echo "NOTE: You will need to manually edit the 'run' column in the samplesheet."
    echo "Use letters (e.g., A, B, etc.) to distinguish sequencing runs."
else
    echo "Invalid response. Please answer yes or no."
    exit 1
fi

#################################
#  HEADER
#################################
echo -e "sampleID\tforwardReads\treverseReads\trun" > "$OUTPUT_FILE"

##############################################
# USER-EDITABLE SAMPLE NAME PARSING FUNCTION #
##############################################
# This function receives the forward read filename WITHOUT the path.
#
# YOU MAY EDIT THE LOGIC TO MATCH YOUR NAMING SCHEME.
# For your example:
#   B12A1_02_4_S14_L001_R1_001.fastq.gz  ?  B12A1_02
#
# Default behavior:
#   Take the first 2 fields separated by underscores (_)
#
extract_sample_id() {
    local filename="$1"
    
    # Remove R1/R2 etc. suffix from filename
    local base="${filename%_R1_001.fastq.gz}"

    # --- DEFAULT RULE ---
    # Extract the first TWO underscore-separated fields
    # e.g. B12A1_02_4_S14 ? B12A1_02
    echo "$base" | awk -F'_' '{print $1"_"$2}'
}


#################################
# LIST FORWARD READ BLOBS (R1)
#################################
# Gets full blob names:
mapfile -t FWD_BLOBS < <(
  az storage blob list \
    --account-name "$STORAGE_ACCOUNT" \
    --container-name "$CONTAINER" \
    --prefix "${BLOB_PREFIX}/" \
    --sas-token "$SAS_TOKEN" \
    --query "[?ends_with(name, '_R1_001.fastq.gz')].name" \
    -o tsv
)

if [[ "${#FWD_BLOBS[@]}" -eq 0 ]]; then
  echo "No R1 FASTQs found under: az://${CONTAINER}/${BLOB_PREFIX}/"
  exit 1
fi

#################################
# PROCESS BLOBS -> WRITE az:// URIs
#################################
for fwd_blob in "${FWD_BLOBS[@]}"; do
    fname="$(basename "$fwd_blob")"
    sampleID="$(extract_sample_id "$fname")"

    sample_prefix="${fwd_blob%_R1_001.fastq.gz}"
    rev_blob="${sample_prefix}_R2_001.fastq.gz"

    fwd_uri="az://${CONTAINER}/${fwd_blob}"

    # Only include R2 if it exists
    if az storage blob exists \
        --account-name "$STORAGE_ACCOUNT" \
        --container-name "$CONTAINER" \
        --name "$rev_blob" \
        --sas-token "$SAS_TOKEN" \
        --query "exists" -o tsv | grep -qi "true"; then
        rev_uri="az://${CONTAINER}/${rev_blob}"
    else
        rev_uri=""
    fi

        echo -e "${sampleID}\t${fwd_uri}\t${rev_uri}\t${RUN_VALUE}" >> "$OUTPUT_FILE"
done

echo "Sample sheet written to: $OUTPUT_FILE"
echo "Example input folder (for reference): az://${CONTAINER}/${BLOB_PREFIX}/"