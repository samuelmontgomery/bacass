#!/bin/bash

# Initialize our own variables
directory=""
format="fastq.gz"
genome_size=""
skip_filt=false
skip_annotation=false
skip_assembly=false
skip_nanoplot_qc=false
skip_qc=false
skip_mapping=false

display_help() {
  echo "Usage: nanopore_assembly.sh [options...] " >&2
  echo
  echo "   -d, --directory     Specify the directory path - REQUIRED"
  echo "   -f, --format        Specify the input format (default: fastq.gz, options: bam)"
  echo "   -g, --genome        Specify the expected genome size (make ~90% of the expected genome size to include variations)"
  echo "   --skip-filt         Skip the filtering steps - including this tag will skip the filtering steps"
  echo "   --skip-annotation   Skip the annotation step - including this tag will skip annotation with bakta"
  echo "   --skip-assembly     Skip the assembly step - including this tag will skip the assembly with flye"
  echo "   --skip-nanoplot-qc  Skip the annotation step - including this tag will skip NanoPlot QC metrics"  
  echo "   --skip-mapping      Skip the mapping step - including this tag will skip mapping the reads back to the de novo assembly"
  echo "   --skip-qc           Skip downstream QC steps (BUSCO, QUAST, CheckM)"
  echo "Note: the pipeline runs filtering > nanoplot > assembly > annotation > mapping > qc. Skipping an earlier step that has not already been completed will break it!"
  echo
  exit 1
}

# Parse the command-line arguments
while getopts ":d:f:g:-:" opt; do
  case ${opt} in
    d)
      export directory="$OPTARG"
      ;;
    f)
      export format="$OPTARG"
      ;;
    g)
      export genome_size="$OPTARG"
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
        skip-mapping)
          export skip_mapping=true
          ;;
        skip-nanoplot-qc)
          export skip_nanoplot_qc=true
          ;;
        skip-filt)
          export skip_filt=true
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
    samtools fastq -T "*" ${directory}/${folder}/*.bam > "${directory}/${folder}/reads_qc/${folder}.fastq"

    # Filter reads using filtlong
    filtlong \
      --min_length 4000 \
      --keep_percent 95 \
      --target_bases 800000000 \
      "${directory}/${folder}/reads_qc/${folder}.fastq" \
      2> >(tee "${directory}/${folder}/reads_qc/${folder}.log" >&2) \
      | gzip > "${directory}/${folder}/reads_qc/${folder}_filtered.fastq.gz"
    
  else
    # Concatenate all fastq files into a single file
    cat "${directory}/${folder}"/*.fastq.gz > "${directory}/${folder}/reads_qc/${folder}.fastq.gz"

    # Filter reads using filtlong
    filtlong \
    --min_length 4000 \
    --keep_percent 95 \
    --target_bases 800000000 \
    "${directory}/${folder}/reads_qc/${folder}.fastq.gz" \
    2> >(tee "${directory}/${folder}/reads_qc/${folder}.log" >&2) \
    | gzip > "${directory}/${folder}/reads_qc/${folder}_filtered.fastq.gz"
  fi 
}

# Function to process each folder for QC steps
process_nanoplot() {
  folder="${1}"
  echo "Running NanoPlot: ${folder}"

  # Create NanoPlot QC plots
  NanoPlot \
    -t 2 \
    --huge \
    -o "${directory}/${folder}/nanoplot" \
    --N50 \
    --tsv_stats \
    --loglength \
    --info_in_report \
    --fastq "${directory}/${folder}/reads_qc/${folder}_filtered.fastq.gz"
}

# Function to process each folder for assembly steps
process_assembly() {
  folder="${1}"
  echo "Running assembly: ${folder}"

  # Assemble using flye and polish with mekada
  flye \
    --nano-hq "${directory}/${folder}/reads_qc/${folder}_filtered.fastq.gz" \
    --scaffold \
    --meta \
    --out-dir "${directory}/${folder}/flye" \
    --threads 8
}

process_dnaapler() {
  folder="${1}"
  # Filter flye assembly for only circular contig with appropriate genome size
  filter_contigs.py \
    "${genome_size}" \
    "${directory}/${folder}/flye/assembly_info.txt" \
    "${directory}/${folder}/flye/assembly.fasta" \
    "${directory}/${folder}/flye/${folder}.fasta"

  dnaapler \
    all \
    --input "${directory}/${folder}/flye/assembly.fasta" \
    --output "${directory}/${folder}/flye/dnaapler" \
    --prefix "${folder}" \
    --threads 4 \
    --force
}

# Function to process each folder for annotation steps
process_annotate() {
  folder="${1}"
  echo "Running bakta: ${folder}"

  # Annotate with bakta
  bakta \
    "${directory}/${folder}/flye/dnaapler/${folder}_reoriented.fasta" \
    --output "${directory}/${folder}/bakta" \
    --verbose \
    --threads 4 \
    --force

  # Run amrfinder
  amrfinder \
    -p "${directory}/${folder}/bakta/${folder}_reoriented.faa" \
    -g "${directory}/${folder}/bakta/${folder}_reoriented.gff3" \
    -n "${directory}/${folder}/bakta/${folder}_reoriented.fna" \
    -a bakta \
    --organism Pseudomonas_aeruginosa \
    -d "/home/ubuntu/scratch/references/bakta/db/amrfinderplus-db/latest" \
    --threads 4 \
    --plus \
    -o "${directory}/${folder}/bakta/${folder}_amr.txt"
}

process_map() {
  folder="${1}"
  echo "Running minimap: ${folder}"

  mkdir "${directory}/${folder}/minimap"

  # Map reads back to the reference using minimap2
  minimap2 \
    -ax \
    lr:hq \
    -y \
    -t 16 \
    "${directory}/${folder}/bakta/${folder}_reoriented.fna" \
    "${directory}/${folder}/reads_qc/${folder}.fastq" \
    | samtools sort -o "${directory}/${folder}/minimap/${folder}.bam"

  # Run qualimap
  qualimap \
    bamqc \
    -bam "${directory}/${folder}/minimap/${folder}.bam" \
    -outdir "${directory}/${folder}/minimap/" \
    -nt 16 \
    --java-mem-size=58G
}

process_QC_prep() {
    folder="${1}"
    # Define the file paths
    info_file="${directory}/${folder}/flye/assembly_info.txt"
    fasta_file="${directory}/${folder}/flye/dnaapler/${folder}_reoriented.fasta"
    output_file="${directory}/QC/input/${folder}_flye.fasta"

    echo "Processing $folder"

    # Identify the longest contig where circ. = Y
    contig=$(awk 'BEGIN {max_len=0; max_contig=""} NR>1 && $4=="Y" && int($2)>max_len {max_len=int($2); max_contig=$1} END {print max_contig}' ${info_file})

    # If no complete contig is found, copy the whole assembly file (contamination will be higher)
    if [ -z "$contig" ]; then
        contig=$(awk 'BEGIN {max_len=0; max_contig=""} NR>1 && int($2)>max_len {max_len=int($2); max_contig=$1} END {print max_contig}' ${info_file})
    fi

    echo "Selected contig: $contig"

    # Filter the .fasta file to extract just that contig into a new fasta file
    awk -v contig=">$contig" '/^>/ {if (p) {exit}; p=(index($0,contig)>0)} p' ${fasta_file} > ${output_file}
    echo "Output file size: $(wc -c < "${output_file}")"
}

process_quast() {
  folder="${1}"
  echo "Running QUAST: ${folder}"
  # Run QUAST
  quast -o "${directory}/${folder}/quast" \
    -r /home/ubuntu/scratch/references/pa01.fasta \
    -m 1000000 \
    --threads 4 \
    --circos \
    --nanopore "${directory}/${folder}/reads_qc/${folder}.fastq" \
    -g "${directory}/${folder}/bakta/${folder}_reoriented.gff3" \
    -l "${folder}" \
    "${directory}/${folder}/bakta/${folder}_reoriented.fna"
}

process_blast() {
  folder="${1}"
  echo "Running BLASTN: ${folder}"
  blastn \
    -task megablast \
    -db nt_prok \
    -taxids 287 \
    -query "${directory}/${folder}/bakta/${folder}_reoriented.fna" \
    -out "${directory}/${folder}/blast_result.tsv" \
    -num_threads 4 \
    -outfmt "7 std pident nident mismatch positive gaps qcovs qcovus staxids qseqid"
}

export -f process_initial_steps
export -f process_nanoplot
export -f process_assembly
export -f process_dnaapler
export -f process_annotate
export -f process_map
export -f process_QC_prep
export -f process_quast
export -f process_blast

# Check if filtering should be run
if [[ "${skip_filt}" == false ]]; then
  parallel -j 8 --eta -k process_initial_steps ::: "${folders[@]}"
fi

# Check if QC should be run
if [[ "${skip_nanoplot_qc}" == false ]]; then
  parallel -j 8 --eta -k process_nanoplot ::: "${folders[@]}"
fi

# Check if assembly should be run
if [[ "${skip_assembly}" == false ]]; then
  parallel -j 2 --eta -k process_assembly ::: "${folders[@]}"
  parallel -j 4 --eta -k process_dnaapler ::: "${folders[@]}"
fi

# Check if annotation should be run
if [[ "${skip_annotation}" == false ]]; then
  parallel -j 4 --eta -k process_annotate ::: "${folders[@]}"
fi

# Check if mapping should be run
if [[ "${skip_mapping}" == false ]]; then
  parallel -j 1 --eta -k process_map ::: "${folders[@]}"
fi

# Check if QC should be run
if [[ "${skip_qc}" == false ]]; then
  mkdir "${directory}/QC"
  mkdir "${directory}/QC/input"
  cd "${directory}"
  # Run BLASTn
  parallel -j 4 --eta -k process_blast ::: "${folders[@]}"
  # Run QC prep
  parallel -j 8 --eta -k process_QC_prep ::: "${folders[@]}"
  # Run QUAST
  conda activate quast
  parallel -j 4 --eta -k process_quast ::: "${folders[@]}"
  # Run BUSCO
  conda activate busco
  busco \
    -i "${directory}/QC/input" \
    -m genome \
    -l pseudomonadales_odb10 \
    --download_path "/home/ubuntu/scratch/references/busco/busco_downloads" \
    -c 16 \
    -o "./QC/busco"
  # Run CheckM
  conda activate nano
  checkm \
    lineage_wf \
    -t 16 \
    -x fasta \
    "${directory}/QC/input" \
    "${directory}/QC/checkm_results"
  conda activate checkm
  checkm2 \
    predict \
    --threads 16 \
    --input "${directory}/QC/input" \
    -x fasta \
    --output-directory "${directory}/QC/checkm2_results" \
    --tmpdir "/home/ubuntu/scratch/tmp"
fi

# Generate NanoPlot stats
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