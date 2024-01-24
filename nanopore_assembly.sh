#!/bin/bash

# Check if the directory path argument is provided
if [[ $# -lt 1 ]]; then
  echo "Please provide the directory path as a command-line argument."
  exit 1
fi

# Get the directory path from the command-line argument
directory="${1}"

# Check if the specified directory exists
if [[ ! -d "${directory}" ]]; then
  echo "Directory does not exist: ${directory}"
  exit 1
fi

# Get a list of all immediate subfolders in the specified directory
folders=($(find "${directory}" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;))

# Check if --annotate is passed as an argument
annotate=false
if [[ $# -ge 2 ]]; then
  if [[ "${2}" == "--annotate" ]]; then
    annotate=true
  fi
fi

# Function to process each folder for initial steps (2 cores per job)
process_initial_steps() {
  folder="${1}"
  echo "Processing folder: ${folder}"

  # Concatenate all fastq files into a single file
  cat "${directory}/${folder}"/*.fastq.gz > "${directory}/${folder}/${folder}.fastq.gz"

  # Create output dir variable
  mkdir "${directory}/${folder}/reads_qc"
  
  # Filter reads using filtlong
  filtlong --minlength 4000 --keep_percent 95 --target_bases 700000000 --verbose "${directory}/${folder}/${folder}.fastq" | gzip > "${directory}/${folder}/reads_qc/${folder}_filtered.fastq.gz"
}

# Function to process each folder for QC steps
process_qc() {
  folder="${1}"
  echo "Running NanoPlot: ${folder}"

  # Create NanoPlot QC plots
  NanoPlot -t 2 --huge -o "${directory}/${folder}/nanoplot" --N50 --tsv_stats --loglength --info_in_report --fastq_rich "${directory}/${folder}/reads_qc/${folder}_filtered.fastq.gz"
}

# Function to process each folder for assembly steps
process_assembly() {
  folder="${1}"
  echo "Running assembly: ${folder}"

  # Assemble using flye and polish with mekada
  flye --nano-hq "${directory}/${folder}/reads_qc/${folder}_filtered.fastq.gz" --asm-coverage 50 --scaffold --meta --out-dir "${directory}/${folder}/flye" --threads 8
}

# Function to process each folder for annotation steps
process_annotate() {
  folder="${1}"
  echo "Running bakta: ${folder}"

  # Annotate with bakta
  bakta "${directory}/${folder}/flye/assembly.fasta" --output "${directory}/${folder}/bakta" --verbose --debug --complete --threads 4

  # Run amrfinder
  amrfinder -p "${directory}/${folder}/bakta/assembly.faa" -g "${directory}/${folder}/bakta/assembly.gff3" -n "${directory}/${folder}/bakta/assembly.fna" -a "${directory}/${folder}/bakta" --organism Pseudomonas_aeruginosa -d /home/ubuntu/scratch/references/bakta/db/amrfinderplus-db/latest --threads 4 --plus -o "${directory}/${folder}/bakta/amr.txt"
}

export -f process_initial_steps
export -f process_qc
export -f process_assembly
export -f process_annotate

parallel -j 8 --eta -k process_initial_steps ::: "${folders[@]}"
parallel -j 8 --eta -k process_qc ::: "${folders[@]}"
parallel -j 2 --eta -k process_assembly ::: "${folders[@]}"

# Check if annotation should be run
if [[ "${annotate}" == true ]]; then
  parallel -j 4 --eta -k process_annotate ::: "${folders[@]}"
fi

# Create checkm directory
mkdir ${directory}/checkm

# Copy assemblies to the checkm file
for folder in "${folders[@]}"
do
  if [[ "${folder}" != "checkm" ]]; then
    # Check if annotation was run
    if [[ "${annotate}" == true ]]; then
      # Move assembly to checkm folder, renaming the file with the folder name
      cp "${directory}/${folder}/bakta/assembly.fna" "${directory}/checkm/${folder}_assembly.fna"
    else
      cp "${directory}/${folder}/flye/assembly.fasta" "${directory}/checkm/${folder}_assembly.fasta"
    fi
  fi
done

# Run CheckM2 on all genomes
conda activate checkm

checkm2 predict --threads 16 --input ${directory}/checkm --output-directory ${directory}/checkm/output --tmpdir /home/ubuntu/scratch/tmp

conda activate nano

# Combined NanoPlot stats into a single csv file
# Initialize an associative array to hold the data and an array to hold the keys
declare -A data
keys=()

# Iterate over each subdirectory in the provided directory
for folder in "${folders[@]}"; do
    # Check if NanoStats.txt exists in the 'nanoplot' subdirectory
    if [[ -f "${directory}/${folder}/nanoplot/NanoStats.txt" ]]; then
        # Read the file line by line
        while IFS= read -r line; do
            # Split the line into key and value
            IFS=$'\t' read -r -a parts <<< "$line"
            key="${parts[0]}"
            value="${parts[1]}"

            # Append the value to the existing data for the key
            data["$key"]="${data["$key"]},$value"

            # Add the key to the keys array if it's not already there
            if ! [[ " ${keys[*]} " =~ " ${key} " ]]; then
                keys+=("$key")
            fi
        done < "${directory}/${folder}/nanoplot/NanoStats.txt"
    fi
done

# Write the data to the output file
{
    echo -e "Metrics,${folders[*]// /,}"
    for key in "${keys[@]}"; do
        echo -e "$key${data[$key]}"
    done
} > combined_nanostats.csv

# Read the first line of the file
first_line=$(head -n 1 combined_nanostats.csv)

# Replace spaces with commas
first_line=${first_line// /,}

# Write the modified first line back to the file
echo "$first_line" | cat - <(tail -n +2 combined_nanostats.csv) > temp && mv temp combined_nanostats.csv

echo "complete!"
