#!/bin/bash

export input="/workdir/input"
export output="/workdir/output"
export database="/workdir/database"
export CHECKM_DATA_PATH="${database}/checkm"
export BAKTA_DB="${database}/bakta/db"

# Create subfolders for input if input data is in bam format
if [ "${format}" == "bam" ]; then
  while read -r barcode new_name; do
    new_name=$(echo "$new_name" | sed 's/[^a-zA-Z0-9]//g')
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
    new_name=$(echo "$new_name" | sed 's/[^a-zA-Z0-9]//g')
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

  # Check if the format is bam
  if [ "${format}" == "bam" ]; then
    # Use samtools to convert the file to fastq
    samtools fastq -T "*" "${input}/${folder}"/*.bam > "${output}/${folder}/reads_qc/${folder}.fastq"
  else
    # Concatenate all fastq files into a single file
    cat "${input}/${folder}"/*.fastq.gz | gunzip -c - > "${output}/${folder}/reads_qc/${folder}.fastq"
  fi 
}

# Trim to min q10, >1000bp, remove DNA CS from reads
process_trim() {
  folder="${1}"
  chopper \
    -q 10 \
    -l 1000 \
    --contam "${database}/dna_cs.fasta" \
    -i "${output}/${folder}/reads_qc/${folder}.fastq" \
    2> >(tee "${output}/${folder}/reads_qc/${folder}_chopper.log" >&2) > "${output}/${folder}/reads_qc/${folder}_trimmed.fastq"
}

# Filter reads using filtlong to either target 200x coverage, or keeping 90% of reads
process_filter() {
  folder="${1}"
  genomesize=$(( $length * 200 ))
  # Filter reads using filtlong
  filtlong \
    --min_length 1000 \
    --keep_percent 90 \
    --target_bases $genomesize \
    "${output}/${folder}/reads_qc/${folder}_trimmed.fastq" \
    2> >(tee "${output}/${folder}/reads_qc/${folder}_filtlong.log" >&2) > "${output}/${folder}/reads_qc/${folder}_filtered.fastq"
}

# Generate QC stats using NanoPlot
process_nanoplot() {
  folder="${1}"
  echo "Running NanoPlot: ${folder}"

  # Create NanoPlot QC plots
  NanoPlot \
    -t 2 \
    --huge \
    -o "${output}/${folder}/nanoplot" \
    --N50 \
    --tsv_stats \
    --loglength \
    --info_in_report \
    --fastq "${output}/${folder}/reads_qc/${folder}_filtered.fastq"
}

# Run de novo assembly using flye
process_assembly() {
  folder="${1}"
  echo "Running assembly: ${folder}"

  # Assemble using flye
  flye \
    --nano-hq "${output}/${folder}/reads_qc/${folder}_filtered.fastq" \
    --scaffold \
    --out-dir "${output}/${folder}/flye" \
    --threads 16
}

# Reorient assemblies using dnaapler
process_dnaapler() {
  folder="${1}"
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

  # Annotate with bakta
  bakta \
    "${output}/${folder}/flye/dnaapler/${folder}_reoriented.fasta" \
    --output "${output}/${folder}/bakta" \
    --verbose \
    --threads 16 \
    --prefix "${folder}" \
    -m 1000 \
    --force
}

# Find plasmids and proviruses using genomad
process_genomad() {
  folder="${1}"
  genomad \
  end-to-end \
  --cleanup \
  "${output}/${folder}/bakta/${folder}.fna" \
  "${output}/${folder}/genomad" \
  "${database}/genomad_db"
}

# Copy genomes for checkM
mkdir -p "${output}/QC"
process_qc_prep(){
  folder="${1}"
  cp "${output}/${folder}/bakta/${folder}.fna" "${output}/QC"
}

# Map reads back to assembly
process_map() {
  folder="${1}"
  echo "Running minimap: ${folder}"
  mkdir "${output}/${folder}/minimap"

  # Map reads back to the reference using minimap2
  minimap2 \
    -ax \
    lr:hq \
    -y \
    -t 16 \
    "${output}/${folder}/bakta/${folder}.fna" \
    "${output}/${folder}/reads_qc/${folder}.fastq" \
    | samtools sort -o "${output}/${folder}/minimap/${folder}.bam"

  # Run qualimap
  qualimap \
    bamqc \
    -bam "${output}/${folder}/minimap/${folder}.bam" \
    -outdir "${output}/${folder}/qualimap/" \
    -nt 16 \
    --java-mem-size=32G
}

process_compress() {
  folder="${1}"
  zstd \
    -1 \
    -T2 \
    --rm \
    "${output}/${folder}/reads_qc/${folder}.fastq" \
    -o "${output}/${folder}/reads_qc/${folder}.fastq.zst"

  zstd \
    -1 \
    -T2 \
    --rm \
    "${output}/${folder}/reads_qc/${folder}_filtered.fastq" \
    -o "${output}/${folder}/reads_qc/${folder}_filtered.fastq.zst"

  zstd \
    -1 \
    -T2 \
    --rm \
    "${output}/${folder}/reads_qc/${folder}_trimmed.fastq" \
    -o "${output}/${folder}/reads_qc/${folder}_trimmed.fastq.zst"
}

# Export functions
export -f process_prep
export -f process_trim
export -f process_filter
export -f process_nanoplot
export -f process_assembly
export -f process_dnaapler
export -f process_annotate
export -f process_qc_prep
export -f process_map
export -f process_genomad
export -f process_compress

# Run functions
parallel -j 16 process_prep ::: "${folders[@]}"
parallel -j 4 process_trim ::: "${folders[@]}"
parallel -j 8 process_filter ::: "${folders[@]}"
parallel -j 8 process_nanoplot ::: "${folders[@]}"
parallel -j 1 process_assembly ::: "${folders[@]}"
parallel -j 4 process_dnaapler ::: "${folders[@]}"
parallel -j 1 process_annotate ::: "${folders[@]}"
parallel -j 12 process_qc_prep ::: "${folders[@]}"
parallel -j 1 process_map ::: "${folders[@]}"
parallel -j 1 process_genomad ::: "${folders[@]}"

# Run checkM for completeness and contamination
checkm \
  lineage_wf \
  -t 16 \
  --file "${output}/QC/checkm/checkm_results.tsv" \
  "${output}/QC" \
  "${output}/QC/checkm"

# Run mlst for sequence typing
mlst "${output}"/QC/*.fna > "${output}"/QC/mlst.tsv

# Compress read files with zstd to save space
parallel -j 4  process_compress ::: "${folders[@]}"