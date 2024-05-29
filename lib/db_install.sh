#!/bin/bash

export database="/workdir/database"

# Install checkM database
wget https://data.ace.uq.edu.au/public/CheckM_databases/checkm_data_2015_01_16.tar.gz
tar -xzvf checkm_data_2015_01_16.tar.gz -C "${database}"/checkm
rm checkm_data_2015_01_16.tar.gz

# Install Kraken2 database - standard 16GB
wget https://genome-idx.s3.amazonaws.com/kraken/k2_standard_16gb_20240112.tar.gz
tar -xzvf k2_standard_16gb_20240112.tar.gz -C "${database}"/kraken2
rm k2_standard_16gb_20240112.tar.gz

# Install Bakta database - full
bakta_db download --output "${database}/bakta" --type full

# Install genomad database
genomad download-database "${database}"

# Install padloc database
wget https://github.com/padlocbio/padloc-db/archive/refs/tags/v2.0.0.tar.gz
tar -xzvf v2.0.0.tar.gz -C "${database}/padloc"
rm v2.0.0.tar.gz

# Copy DNA control strand fasta for chopper
wget https://raw.githubusercontent.com/samuelmontgomery/bacass/main/dna_cs.fasta -O "${database}/dna_cs.fasta"