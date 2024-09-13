#!/bin/bash

export database="/workdir/database"

# Install checkM database
wget https://data.ace.uq.edu.au/public/CheckM_databases/checkm_data_2015_01_16.tar.gz
tar -xzvf checkm_data_2015_01_16.tar.gz -C "${database}"/checkm
rm checkm_data_2015_01_16.tar.gz

# Install Bakta database - full
bakta_db download --output "${database}/bakta" --type full

# Install genomad database
genomad download-database "${database}"

# Copy DNA control strand fasta for chopper
wget https://raw.githubusercontent.com/samuelmontgomery/bacass/main/dna_cs.fasta -O "${database}/dna_cs.fasta"