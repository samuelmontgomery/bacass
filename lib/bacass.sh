#!/bin/bash

export input="/workdir/input"
export output="/workdir/output"
export database="/workdir/database"
export CHECKM_DATA_PATH="${database}/checkm"
export BAKTA_DB="${database}/bakta/db"

# Create subfolders for input if input data is in bam format
if [ "${format}" == "bam" ]; then
  while read -r barcode new_name; do
    new_name=$(echo "$new_name" | sed 's/[^a-zA-Z0-9_]//g')
    mkdir -p "${input}/${new_name}"
    for file in "${input}"/*_barcode"${barcode}".bam; do
        if [ -e "$file" ]; then
            mv "$file" "${input}/${new_name}/"
            echo "Moved $file to ${input}/${new_name}/"
        else
            echo "Error: $file not found."
        fi
    done
  done < "${input}/barcodes.txt"
  else
# Rename folders for input if input data is in fastq format
  while read -r barcode new_name; do
    old_name="barcode$barcode"
    new_name=$(echo "$new_name" | sed 's/[^a-zA-Z0-9_]//g')
    if [ -d "${input}/${old_name}" ]; then
        mv "${input}/${old_name}" "${input}/${new_name}"
        echo "Renamed $old_name to $new_name"
    else
        echo "Error: $old_name not found."
    fi
  done < "${input}/barcodes.txt"
fi

# Get a list of all immediate subfolders in the specified directory
folders=($(find "$input" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;))

# Process each folder for initial steps
process_prep() {
  folder="${1}"
  echo "Processing folder: ${folder}"

  # Create output dir variable
  mkdir -p "${output}/${folder}/reads_qc"

  # Skip if reads already exist
  if [[ -f "${output}/${folder}/reads_qc/${folder}.fastq" ]]; then
    echo "Reads already exist for ${folder}, skipping..."
    return 0
  fi

  # Check if the format is bam
  if [ "${format}" == "bam" ]; then
    # Use samtools to convert the file to fastq
    samtools fastq -T "*" "${input}/${folder}"/*.bam > "${output}/${folder}/reads_qc/${folder}.fastq"
  else
    # Concatenate all fastq files into a single file
    cat "${input}/${folder}"/*.fastq.gz | zstd -d -c > "${output}/${folder}/reads_qc/${folder}.fastq"
  fi 
}

# Trim to min q10, >1000bp, remove DNA CS from reads
process_trim() {
  folder="${1}"

  # Skip if chopper output already exists
  if [[ -f "${output}/${folder}/reads_qc/${folder}_trimmed.fastq" ]]; then
    echo "Read trimming already complete for ${folder}, skipping..."
    return 0
  fi

  chopper \
    -q 10 \
    -l 1000 \
    --contam "${database}/dna_cs.fasta" \
    -i "${output}/${folder}/reads_qc/${folder}.fastq" \
    2> >(tee "${output}/${folder}/reads_qc/${folder}_chopper.log" >&2) > "${output}/${folder}/reads_qc/${folder}_trimmed.fastq"
}

# Classify reads using kraken2 to identify species
process_kraken() {
  folder="${1}"
  echo "Running kraken2: ${folder}"
  mkdir -p "${output}/${folder}/kraken2"

  # Skip if Kraken2 output already exists
  if [[ -f "${output}/${folder}/kraken2/${folder}.report" ]]; then
    echo "Kraken2 report already exist for ${folder}, skipping..."
    return 0
  fi

  k2 \
  classify \
  --db "${database}/kraken2" \
  --threads 16 \
  --use-names \
  --output "${output}/${folder}/kraken2/${folder}.kraken" \
  --report "${output}/${folder}/kraken2/${folder}.report" \
  "${output}/${folder}/reads_qc/${folder}_trimmed.fastq"
}

# Generate QC stats using NanoPlot
process_nanoplot() {
  folder="${1}"
  echo "Running NanoPlot: ${folder}"

  # Skip if Nanoplot output already exists
  if [[ -f "${output}/${folder}/nanoplot/${folder}NanoStats.txt" ]]; then
    echo "Nanoplot statistics already exist for ${folder}, skipping..."
    return 0
  fi

  # Create NanoPlot QC plots for trimmed reads
  NanoPlot \
    -t 2 \
    --huge \
    -o "${output}/${folder}/nanoplot" \
    --N50 \
    --tsv_stats \
    --loglength \
    --info_in_report \
    --no_static \
    -p "${folder}" \
    --fastq "${output}/${folder}/reads_qc/${folder}_trimmed.fastq"
}

# Run de novo assembly using flye
process_assembly() {
  folder="${1}"
  echo "Running assembly: ${folder}"

  # Skip if assembly already complete
  if [[ -f "${output}/${folder}/flye/assembly.fasta" ]]; then
    echo "Assembly already exists for ${folder}, skipping..."
    return 0
  fi

  # Assemble using flye
  flye \
    --nano-hq "${output}/${folder}/reads_qc/${folder}_trimmed.fastq" \
    --genome-size "${length}" \
    --asm-coverage 50 \
    --scaffold \
    --out-dir "${output}/${folder}/flye" \
    --threads "${cpus}" 
}

# Reorient assemblies using dnaapler
process_dnaapler() {
  folder="${1}"

  # Skip if dnaapler output already exists
  if [[ -f "${output}/${folder}/flye/dnaapler/${folder}_reoriented.fasta" ]]; then
    echo "dnaapler output already exists for ${folder}, skipping..."
    return 0
  fi

  dnaapler \
    all \
    --input "${output}/${folder}/flye/assembly.fasta" \
    --output "${output}/${folder}/flye/dnaapler" \
    --prefix "${folder}" \
    --threads 4 \
    --force
}

# Annotate genomes using bakta
process_annotate() {
  folder="${1}"
  echo "Running bakta: ${folder}"

  # Skip if annotation already complete
  if [[ -f "${output}/${folder}/bakta/${folder}.fna" ]]; then
    echo "Assembly already exists for ${folder}, skipping..."
    return 0
  fi

  # Annotate with bakta
  bakta \
    "${output}/${folder}/flye/dnaapler/${folder}_reoriented.fasta" \
    --output "${output}/${folder}/bakta" \
    --verbose \
    --threads "${cpus}" \
    --prefix "${folder}" \
    -m 1000 \
    --force
}

# Find plasmids and proviruses using genomad
process_genomad() {
  folder="${1}"

  # Skip if genomad already complete
  if [[ -f "${output}/${folder}/genomad/${folder}_summary.log" ]]; then
    echo "Genomad already run for ${folder}, skipping..."
    return 0
  fi

  genomad \
  end-to-end \
  --cleanup \
  "${output}/${folder}/bakta/${folder}.fna" \
  "${output}/${folder}/genomad" \
  "${database}/genomad_db"
}

# Copy genomes for checkM
mkdir -p "${output}/QC/input"
process_qc_prep(){
  folder="${1}"
  cp "${output}/${folder}/bakta/${folder}.fna" "${output}/QC/input"
}

# Map reads back to assembly
process_map() {
  folder="${1}"
  echo "Running minimap: ${folder}"
  mkdir "${output}/${folder}/minimap"

  # Skip if annotation already complete
  if [[ -f "${output}/${folder}/qualimap/genome_results.txt" ]]; then
    echo "Mapping already exists for ${folder}, skipping..."
    return 0
  fi

  # Map reads back to the reference using minimap2
  minimap2 \
    -ax \
    lr:hqae \
    -y \
    -t "${cpus}" \
    "${output}/${folder}/bakta/${folder}.fna" \
    "${output}/${folder}/reads_qc/${folder}_trimmed.fastq" \
    | samtools sort -o "${output}/${folder}/minimap/${folder}.bam"

  # Run qualimap
  qualimap \
    bamqc \
    -bam "${output}/${folder}/minimap/${folder}.bam" \
    -outdir "${output}/${folder}/qualimap/" \
    -nt "${cpus}" \
    --java-mem-size=32G
}

process_compress() {
  folder="${1}"
  zstd \
    -T4 \
    --format=gzip \
    --rm \
    "${output}/${folder}/reads_qc/${folder}.fastq" \
    -o "${output}/${folder}/reads_qc/${folder}.fastq.gz"

  zstd \
    -T4 \
    --format=gzip \
    --rm \
    "${output}/${folder}/reads_qc/${folder}_trimmed.fastq" \
    -o "${output}/${folder}/reads_qc/${folder}_trimmed.fastq.gz"
}

# Export functions
export -f process_prep
export -f process_trim
export -f process_kraken
export -f process_nanoplot
export -f process_assembly
export -f process_dnaapler
export -f process_annotate
export -f process_genomad
export -f process_qc_prep
export -f process_map
export -f process_genomad
export -f process_compress

# Run functions
parallel -j "$cpus" process_prep ::: "${folders[@]}"
parallel -j "$cpus/4" process_trim ::: "${folders[@]}"
parallel -j "$cpus/16" process_kraken ::: "${folders[@]}"
parallel -j "$cpus/2" process_nanoplot ::: "${folders[@]}"
parallel -j 1 process_assembly ::: "${folders[@]}"
parallel -j "$cpus/4" process_dnaapler ::: "${folders[@]}"
parallel -j 1 process_annotate ::: "${folders[@]}"
parallel -j 1 process_genomad ::: "${folders[@]}"
parallel -j "$cpus" process_qc_prep ::: "${folders[@]}"
parallel -j 1 process_map ::: "${folders[@]}"
parallel -j 1 process_genomad ::: "${folders[@]}"

# Run checkM for completeness and contamination
checkm \
  lineage_wf \
  -t "${cpus}" \
  --file "${output}/QC/checkm/checkm_results.tsv" \
  --tab_table \
  "${output}/QC/input" \
  "${output}/QC/checkm"

checkm \
  qa \
  -o 2 \
  -t "${cpus}" \
  --file "${output}/QC/checkm/checkm_results.tsv" \
  --tab_table \
  "${output}/QC/checkm/lineage.ms" \
  "${output}/QC/checkm"

# Compress read files with zstd to save space
parallel -j "$cpus/4" process_compress ::: "${folders[@]}"