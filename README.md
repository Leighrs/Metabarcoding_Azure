# Metabarcoding Directory Setup & Pipeline

![GitHub Repo Size](https://img.shields.io/github/repo-size/Leighrs/Metabarcoding_Azure)
![License](https://img.shields.io/github/license/Leighrs/Metabarcoding_Azure)
![Last Commit](https://img.shields.io/github/last-commit/Leighrs/Metabarcoding_Azure)

Welcome to the **Metabarcoding** repository for use on **Azure**!  
This repository helps to set up and run metabarcoding analyses using the **nf-core/ampliseq pipeline**.

---
<details>
<summary><h2>Table of Contents</h2></summary>
  
<br>

- [Repository Overview](#repository-overview)
- [Current Repository Files](#current-repository-files)
- [Running Test Data](#running-test-data)
  
</details>

---

<details>
<summary><h2>Repository Overview</h2></summary>
  
<br>

This repository contains scripts and configuration files to:

1. Set up your project directory.
2. Provide example files (samplesheets, metadata, and RSD sequences) for testing and reference.
3. Run the nf-core/ampliseq pipeline on your data.
</details>

---

<details>
<summary><h2>Current Repository Files</h2></summary>
  
<br>

| File | Description |
|------|-------------|
| `nf-params_no_RSD.json` | Contents of this parameter file for the nf-core/ampliseq pipeline will be uploaded to project directory if user specifies no RSD. Customize for your project. |
| `nf-params_with_RSD.json` | Contents of this arameter file for the nf-core/ampliseq pipeline will be uploaded to project directory if user specifies the use of an RSD. Customize for your project. |
| `setup_metabarcoding_directory.sh` | Shell script to create your project directory with example samplesheets, metadata, and RSD files. |
| `generate_samplesheet_table.sh` | Shell script to generate a samplesheet for your project that will work with the nf-core/ampliseq pipeline. |
| `run_ampliseq_azure.sh` | This script is for running nf-core/ampliseq using DWR's Azure Batch resources. |
</details>

---

<details>
<summary><h2>Running Test Data</h2></summary>
  
<br>

1. **Clone the Repository**

Ensure you are in your home directory and clonee in the Metabarcoding repository from Github.

```
cd ~
git clone https://github.com/Leighrs/Metabarcoding_Azure.git
```

2. **Set Up Your Project Directory**

Ensure you are in your home directory and execute a shell script that will set up a project directory for you.

```
cd ~
./Metabarcoding_Azure/scripts_do_not_alter/setup_metabarcoding_directory.sh
```
- **When prompted:**
  - *Enter project name:* ${\color{green}test}$
  - *Reference database choice:* ${\color{green}2}$

3. **Import fastq files, metadata, and custom reference sequence database.**

This was already done for you. Test data files can be found on Azure Blob in *reference/metabarcoding/ampliseq_test* folder.

4. **Generate a samplesheet file.**

Ensure you are in your home directory and run the following shell script.

*This script will autopopulate the PATHs for each of your fastq files, extrapolate sample names from those files, and prompt you to specify how many metabarcoding runs these samples were sequenced in.*

```
cd ~
PROJECT_NAME=$(cat "$HOME/Metabarcoding_Azure/current_project_name.txt")
"$HOME/Metabarcoding_Azure/$PROJECT_NAME/scripts/${PROJECT_NAME}_generate_samplesheet_table.sh" 
```

- **When prompted:**
  - *Did you sequence samples using multiple sequencing runs?:* ${\color{red}no}$

5. **Edit Run Parameters.**

Open the parameter file for the nf-core/ampliseq pipeline:

- The `${PROJECT_NAME}_nf-params.json` file contains all the parameters needed to run the nf-core/ampliseq workflow for your specific project.
- Edit this file so that the input paths, primer sequences, and filtering settings match your dataset.

```
PROJECT_NAME=$(cat "$HOME/Metabarcoding_Azure/current_project_name.txt")
nano $HOME/Metabarcoding_Azure/$PROJECT_NAME/scripts/${PROJECT_NAME}_nf-params.json
```
**Replace these parameters for the test data using the following information:**

Nano files are little tricky to work with. Here are some tips:

- First, highlight the entire script:
  - Go to the top of the script using `Ctrl` + `_`, then type 1, press **Enter**.
  - Then, start selecting text using `Ctrl` + `^`.
  - Highlight the rest of the script using `Ctrl` + `_`, then type 100, press **Enter**.
  - Everything should now be selected.
- Delete all the text in the scriptusing `Ctrl` + `K`.
- Copy the new text below, and paste into the empty script using a right-click to paste. Some terminals may require `Ctrl` + `Shift` + `V`.
- Exit the script using `Ctrl` + `X`. Then `Y` to save. Press **Enter**.

```
{
    "input": "$HOME/Metabarcoding_Azure/$PROJECT_NAME/samplesheet/${PROJECT_NAME}_samplesheet.txt",
    "FW_primer": "GTCGGTAAAACTCGTGCCAGC",
    "RV_primer": "CATAGTGGGGTATCTAATCCCAGTTTG",

    "metadata": "az:// path to metadata",
    "outdir": "az:// path to metadata",

    "seed": 13,

    "ignore_failed_trimming": true,
    "ignore_failed_filtering": true,

    "trunclenf": 120,
    "trunclenr": 120,

    "dada_ref_taxonomy": false,
    "skip_dada_addspecies": true,
    "dada_ref_tax_custom": "az:// path to RSD",
    "dada_min_boot": 80,
    "dada_assign_taxlevels": "Kingdom,Phylum,Class,Order,Family,Genus,Species,Common",

    "exclude_taxa": "none",

    "skip_qiime": true,
    "skip_barrnap": true,
    "skip_dada_addspecies": true,
    "skip_tse": true
}

```

JSON files can't expand environment variables, like `$HOME` or `$PROJECT_NAME`. Create a file with an expanded variable unique to your system.
```
export PROJECT_NAME=$(cat "$HOME/Metabarcoding_Azure/current_project_name.txt")
envsubst '$HOME $PROJECT_NAME' \
  < "$HOME/Metabarcoding_Azure/$PROJECT_NAME/scripts/${PROJECT_NAME}_nf-params.json" \
  > "$HOME/Metabarcoding_Azure/$PROJECT_NAME/scripts/${PROJECT_NAME}_nf-params_expanded.json"
```
6. Create `config` files.

First, create and open a new file called  `azure_esm_ampliseq.config` and `config`:
```
nano $HOME/azure_esm_ampliseq.config
```
Paste in the following:
```
process.executor = 'azurebatch'
docker.enabled = true
workDir = '<REDACTED>'


azure {
    batch {
        autoPoolMode = false
        deletePoolsOnCompletion = false
    }
}

process {
  queue = '<REDACTED>'
}
```
```
nano $HOME/config
```
*This file will need Azure Storage and Batch resource keys/tokens.*

For each file, you will need to request the required resource information from DWR.

7. **Run the nf-core/ampliseq Pipeline:** 

Ensure you are in your home directory and run the following shell script.

```
cd ~
PROJECT_NAME=$(cat "$HOME/Metabarcoding_Azure/current_project_name.txt")
$HOME/Metabarcoding_Azure/$PROJECT_NAME/scripts/${PROJECT_NAME}_run_ampliseq_azure.sh
```

</details>
