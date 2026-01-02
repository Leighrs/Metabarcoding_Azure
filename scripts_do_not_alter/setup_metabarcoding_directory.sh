#!/usr/bin/env bash

# ---------------------------
#  COLOR DEFINITIONS
# ---------------------------
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
BLUE="\e[36m"
RESET="\e[0m"

# ---------------------------
#  ASK FOR PROJECT NAME
# ---------------------------
read -p "Enter project name: " PROJECT

# ---------------------------
#  PROMPT: STANDARD / CUSTOM / NEITHER
# ---------------------------
while true; do
    echo
    echo "Reference database choice:"
    echo "  1) Standardized/curated database"
    echo "  2) Custom sequence database"
    read -rp "Enter 1 or 2: " RSD_CHOICE

    case "$RSD_CHOICE" in
        1) DB_MODE="standard"; break ;;
        2) DB_MODE="custom";   break ;;
        *) echo -e "${RED}Invalid input. Please enter 1 or 3.${RESET}" ;;
    esac
done

# ---------------------------
#  CREATE DIRECTORIES
# ---------------------------
mkdir -p "Metabarcoding_Azure/$PROJECT"
mkdir -p "Metabarcoding_Azure/Logs_archive"
mkdir -p "Metabarcoding_Azure/$PROJECT/scripts"
mkdir -p "Metabarcoding_Azure/$PROJECT/samplesheet"
mkdir -p "Metabarcoding_Azure/$PROJECT/example_input_files"
mkdir -p "Metabarcoding_Azure/$PROJECT/output"

# ---------------------------
#  CREATE EXAMPLE FILES
# ---------------------------
cat <<EOT > "Metabarcoding_Azure/$PROJECT/example_input_files/Example_samplesheet.txt"
sampleID	forwardReads	reverseReads	run
B12A1_02	/path/to/R1.fastq.gz	/path/to/R2.fastq.gz	A
B12A2_02	/path/to/R1.fastq.gz	/path/to/R2.fastq.gz	A
B12A3_02	/path/to/R1.fastq.gz	/path/to/R2.fastq.gz	A
EOT

cat <<EOT > "Metabarcoding_Azure/$PROJECT/example_input_files/Example_metadata.txt"
ID	Replicate	Control_Assign	Sample_or_Control	Site	Month	Year
B12A1_02	A1	1,2,4	Sample	Browns_Island	February	2023
B12A2_02	A2	1,2,4	Sample	Browns_Island	February	2023
B12A3_02	A3	1,2,4	Sample	Browns_Island	February	2023
EOT

if [[ "$USE_RSD" == "yes" ]]; then
cat <<EOT > "Metabarcoding_Azure/$PROJECT/example_input_files/Example_RSD.txt"
>Animalia;Chordata;Actinopterygii;Cypriniformes;Catostomidae;Catostomus;Catostomus occidentalis;
CACCGCGGTTATACGAGAGGCCCTAGTTGATA...
EOT

chmod +x "Metabarcoding_Azure/$PROJECT/example_input_files/Example_RSD.txt"
echo -e "${GREEN}Example RSD file created.${RESET}"
fi

chmod +x "Metabarcoding_Azure/$PROJECT/example_input_files/"*.txt

echo -e "${GREEN}Example input files created.${RESET}"

# ---------------------------
#  COPY CORRECT nf-params.json (ALWAYS re-named to nf-params.json)
# ---------------------------
SRC_STANDARD="$HOME/Metabarcoding_Azure/scripts_do_not_alter/nf-params_with_standard_RSD.json"
SRC_CUSTOM="$HOME/Metabarcoding_Azure/scripts_do_not_alter/nf-params_with_custom_RSD.json"
DEST_JSON="$HOME/Metabarcoding_Azure/$PROJECT/scripts/${PROJECT}_nf-params.json"

case "$DB_MODE" in
  standard)
    SRC="$SRC_STANDARD"
    MSG="Standardized/curated DB → nf-params_with_standard_RSD.json copied as ${PROJECT}_nf-params.json"
    ;;
  custom)
    SRC="$SRC_CUSTOM"
    MSG="Custom sequence DB → nf-params_with_custom_RSD.json copied as ${PROJECT}_nf-params.json"
    ;;
esac

if [[ -f "$SRC" ]]; then
    cp "$SRC" "$DEST_JSON"
    echo -e "${GREEN}${MSG}.${RESET}"
else
    echo -e "${RED}WARNING: Missing template: $SRC${RESET}"
fi

# ---------------------------
#  COPY OTHER PIPELINE SCRIPTS
# ---------------------------
declare -A FILES=(
    ["generate_samplesheet_table.sh"]="${PROJECT}_generate_samplesheet_table.sh"
    ["run_ampliseq_azure.sh"]="${PROJECT}_run_ampliseq_azure.sh"
)

for SRCFILE in "${!FILES[@]}"; do
    SRC="$HOME/Metabarcoding_Azure/scripts_do_not_alter/$SRCFILE"
    DEST="$HOME/Metabarcoding_Azure/$PROJECT/scripts/${FILES[$SRCFILE]}"

    if [[ -f "$SRC" ]]; then
        cp "$SRC" "$DEST"
        echo -e "${GREEN}Copied $SRCFILE${RESET}"
    else
        echo -e "${YELLOW}WARNING: $SRCFILE missing.${RESET}"
    fi
done

# ---------------------------
#  SAVE CURRENT PROJECT NAME
# ---------------------------
echo "$PROJECT" > "$HOME/Metabarcoding_Azure/current_project_name.txt"

# ---------------------------
#  PRINT COLORIZED DIRECTORY TREE
# ---------------------------
echo -e "${BLUE}"
echo "======================================"
echo " Metabarcoding_Azure PROJECT SETUP COMPLETE "
echo "======================================"
echo -e "${RESET}"

if command -v tree >/dev/null 2>&1; then
  tree -C "Metabarcoding_Azure/$PROJECT"
else
  echo -e "${YELLOW}NOTE: 'tree' not found; showing directories via find.${RESET}"
  find "Metabarcoding_Azure/$PROJECT" -maxdepth 4 -type d | sed "s|^Metabarcoding_Azure/||"
fi

# ---------------------------
#  SUMMARY
# ---------------------------
echo -e "${BLUE}Summary of copied files:${RESET}"
echo -e "${GREEN}Setup finished successfully.${RESET}"
