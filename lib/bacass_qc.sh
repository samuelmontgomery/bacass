#!/bin/bash

export input="/workdir/input"
export output="/workdir/output"
export database="/workdir/database"
export CHECKM2DB="${database}/checkm"

# Get a list of all immediate subfolders in the specified directory
folders=($(find "$input" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;))

# Run MLST for sequence typing
mlst "${output}"/QC/input/*.fna > "${output}"/QC/mlst.tsv

# Run CheckM2 for genome completeness
checkm2 predict --threads "${cpus}" --input "${output}"/QC/input/" --output-directory ${output}"/QC/checkm2"