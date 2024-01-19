#!/bin/bash

# Check if the directory path argument is provided
if [ $# -ne 1 ]; then
  echo "Please provide the directory path as a command-line argument."
  exit 1
fi

# Get the directory path from the command-line argument
export directory="$1"

# Check if the specified directory exists
if [ ! -d "$directory" ]; then
  echo "Directory does not exist: $directory"
  exit 1
fi

# Get a list of all immediate subfolders in the specified directory
folders=($(find "$directory" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;))

# Function to process each folder for initial steps (2 cores per job)
process_initial_steps() {
  folder="$1"
  echo "Processing folder: $folder"

  # Navigate to the folder
  cd "$directory/$folder"

  # Concatenate all fastq files into a single file
  cat *.fastq.gz > "$folder.fastq.gz"

  # Create output dir variable
  mkdir reads_qc

  # Remove DNA CS from data
  gunzip -c "$folder.fastq.gz" | chopper -l 4000 --contam /home/ubuntu/scratch/references/dna_cs.fasta | gzip > "$folder"_cs.fastq.gz

  # Filter reads using filtlong
  filtlong --keep_percent 95 "$folder"_cs.fastq.gz | gzip > reads_qc/"$folder"_filtered.fastq.gz
  
  # Return to the original directory
  cd -
}

process_qc() {
  folder="$1"
  echo "Running NanoPlot: $folder"

  # Navigate to the folder
  cd "$directory/$folder"

  # Create NanoPlot QC plots
  NanoPlot -t 2 --huge -o ./nanoplot --N50 --tsv_stats --loglength --info_in_report --fastq_rich reads_qc/"$folder"_filtered.fastq.gz

  # Return to the original directory
  cd -
}

process_assembly() {
  folder="$1"
  echo "Running NanoPlot: $folder"

  # Navigate to the folder
  cd "$directory/$folder"
  
  # Assemble using flye and polish with mekada
  flye --nano-hq reads_qc/"$folder"_filtered.fastq.gz --scaffold --out-dir flye --threads 8

  # Return to the original directory
  cd -
}

process_annotate() {
  folder="$1"
  echo "Running bakta: $folder"

  # Navigate to the folder
  cd "$directory/$folder"
  
  # Annotate with bakta
  bakta flye/assembly.fasta --output bakta --verbose --debug --complete --threads 4

  # Run amrfinder
  amrfinder -p bakta/assembly.faa -g bakta/assembly.gff3 -n bakta/assembly.fna -a bakta --organism Pseudomonas_aeruginosa -d /home/ubuntu/scratch/references/bakta/db/amrfinderplus-db/latest --threads 4 --plus -o amr.txt

  # Return to the original directory
  cd -
}

export -f process_initial_steps
export -f process_qc
export -f process_assembly
export -f process_annotate

parallel -j 8 --eta -k process_initial_steps ::: "${folders[@]}"
parallel -j 8 --eta -k process_qc ::: "${folders[@]}"
parallel -j 2 --eta -k process_assembly ::: "${folders[@]}"
parallel -j 4 --eta -k process_annotate ::: "${folders[@]}"

mkdir $directory/checkm

for folder in "${folders[@]}"
do
  if [ "$folder" != "checkm" ]; then
    # Navigate to the folder
    cd "$directory/$folder"
  
    # Assemble using flye and polish with mekada
    cp bakta/assembly.fna "$directory/checkm"
    mv "$directory/checkm/assembly.fna" "$directory/checkm/${folder}_assembly.fna"
  
    # Return to the original directory
    cd -
  fi
done

# Run CheckM2 on all genomes
conda activate checkm

checkm2 predict --threads 16 --input $directory/checkm --output-directory $directory/checkm/checkm --tmpdir /home/ubuntu/scratch/tmp

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
