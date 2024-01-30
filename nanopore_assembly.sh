#!/bin/bash

# Initialize our own variables
directory=""
format="fastq.gz"
skip_annotation=false
skip_assembly=false
skip_qc=false

display_help() {
  echo "Usage: nanopore_assembly.sh [options...] " >&2
  echo
  echo "   -d, --directory     Specify the directory path - REQUIRED"
  echo "   -f, --format        Specify the input format (default: fastq.gz, options: bam)"
  echo "   --skip-annotation   Skip the annotation step - including this tag will skip annotation with bakta"
  echo "   --skip-assembly     Skip the assembly step - including this tag will skip the assembly with flye"
  echo "   --skip-qc           Skip the annotation step - including this tag will skip NanoPlot QC metrics"  
  echo "Note: the pipeline runs qc > assembly > annotation. Skipping an earlier step will break it!"
  echo
  exit 1
}

# Parse the command-line arguments
while getopts ":d:f:-:" opt; do
  case ${opt} in
    d)
      export directory="$OPTARG"
      ;;
    f)
      export format="$OPTARG"
      ;;
    -)
      case "${OPTARG}" in
        skip-annotation)
          export skip_annotation=true
          ;;
        skip-assembly)
          export skip_assembly=true
          ;;
        skip-qc)
          export skip_qc=true
          ;;
        *)
          echo "Invalid option: --${OPTARG}" >&2
          display_help
          ;;
      esac
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      display_help
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      display_help
      ;;
  esac
done

# Check if the directory path argument is provided
if [ -z "$directory" ]; then
  echo "Please provide the directory path with -d or --directory."
  display_help
fi

# Check if the specified directory exists
if [ ! -d "$directory" ]; then
  echo "Directory does not exist: $directory"
  display_help
fi

# Get a list of all immediate subfolders in the specified directory
folders=($(find "$directory" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;))

# Function to process each folder for initial steps (2 cores per job)
process_initial_steps() {
  folder="${1}"
  echo "Processing folder: ${folder}"

  # Create output dir variable
  mkdir "${directory}/${folder}/reads_qc"

  # Check if the format is bam
  if [ "${format}" == "bam" ]; then
    # Use samtools to convert the file to fastq
    #samtools sort -n ${directory}/${folder}/*.bam -o ${directory}/${folder}/${folder}.bam
    samtools fastq -T "*" ${directory}/${folder}/*.bam > "${directory}/${folder}/${folder}.fastq"

    # Filter reads using filtlong
    filtlong --min_length 4000 --keep_percent 95 --target_bases 700000000 "${directory}/${folder}/${folder}.fastq" | gzip > "${directory}/${folder}/reads_qc/${folder}_filtered.fastq.gz"
    rm "${directory}/${folder}/${folder}.fastq"
  else
    # Concatenate all fastq files into a single file
    cat "${directory}/${folder}"/*.fastq.gz > "${directory}/${folder}/${folder}.fastq.gz"

    # Filter reads using filtlong
    filtlong --min_length 4000 --keep_percent 95 --target_bases 700000000 "${directory}/${folder}/${folder}.fastq.gz" | gzip > "${directory}/${folder}/reads_qc/${folder}_filtered.fastq.gz"
  fi
}

# Function to process each folder for QC steps
process_qc() {
  folder="${1}"
  echo "Running NanoPlot: ${folder}"

  # Create NanoPlot QC plots
  NanoPlot -t 2 --huge -o "${directory}/${folder}/nanoplot" --N50 --tsv_stats --loglength --info_in_report --fastq "${directory}/${folder}/reads_qc/${folder}_filtered.fastq.gz"
}

# Function to process each folder for assembly steps
process_assembly() {
  folder="${1}"
  echo "Running assembly: ${folder}"

  # Assemble using flye and polish with mekada
  flye --nano-hq "${directory}/${folder}/reads_qc/${folder}_filtered.fastq.gz" --scaffold --meta --out-dir "${directory}/${folder}/flye" --threads 8
}

# Function to process each folder for annotation steps
process_annotate() {
  folder="${1}"
  echo "Running bakta: ${folder}"

  # Annotate with bakta
  bakta "${directory}/${folder}/flye/assembly.fasta" --output "${directory}/${folder}/bakta" --verbose --threads 4

  # Run amrfinder
  amrfinder -p "${directory}/${folder}/bakta/assembly.faa" -g "${directory}/${folder}/bakta/assembly.gff3" -n "${directory}/${folder}/bakta/assembly.fna" -a "${directory}/${folder}/bakta" --organism Pseudomonas_aeruginosa -d /home/ubuntu/scratch/references/bakta/db/amrfinderplus-db/latest --threads 4 --plus -o "${directory}/${folder}/bakta/amr.txt"
}

export -f process_initial_steps
export -f process_qc
export -f process_assembly
export -f process_annotate

parallel -j 8 --eta -k process_initial_steps ::: "${folders[@]}"

# Check if QC should be run
if [[ "${skip_qc}" == false ]]; then
  parallel -j 8 --eta -k process_qc ::: "${folders[@]}"
fi

# Check if assembly should be run
if [[ "${skip_assembly}" == false ]]; then
  parallel -j 2 --eta -k process_assembly ::: "${folders[@]}"
fi

# Check if annotation should be run
if [[ "${skip_annotation}" == false ]]; then
  parallel -j 4 --eta -k process_annotate ::: "${folders[@]}"
fi

# Run CheckM2
# Create checkm directory
mkdir ${directory}/checkm

# Function to copy largest circular assemblies to the checkm file
process_checkm() {
    folder="${1}"
    # Define the file paths
    info_file="${directory}/${folder}/flye/assembly_info.txt"
    fasta_file="${directory}/${folder}/flye/assembly.fasta"
    output_file="${directory}/checkm/${folder}_flye.fasta"

    echo "Processing $folder"

    # Identify the longest contig where circ. = Y
    contig=$(awk 'BEGIN {max_len=0; max_contig=""} NR>1 && $4=="Y" && int($2)>max_len {max_len=int($2); max_contig=$1} END {print max_contig}' ${info_file})

    # If no complete contig is found, select the longest incomplete contig
    if [ -z "$contig" ]; then
        contig=$(awk 'BEGIN {max_len=0; max_contig=""} NR>1 && int($2)>max_len {max_len=int($2); max_contig=$1} END {print max_contig}' ${info_file})
    fi

    echo "Selected contig: $contig"

    # Filter the .fasta file to extract just that contig into a new fasta file
    awk -v contig=">$contig" '/^>/ {if (p) {exit}; p=(index($0,contig)>0)} p' ${fasta_file} > ${output_file}
    echo "Output file size: $(wc -c < "${output_file}")"
}

export -f process_checkm
parallel -j 8 process_checkm ::: "${folders[@]}"

# Run CheckM2 on all genomes
#conda activate checkm

#checkm2 predict --threads 16 --input ${directory}/checkm --output-directory ${directory}/checkm/output --tmpdir /mnt/scratch/tmp

#conda activate nano

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
