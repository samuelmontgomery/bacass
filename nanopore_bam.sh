#!/bin/bash

# Check if the rename list .txt file exists
if [ ! -f "barcodes.txt" ]; then
    echo "Error: barcodes.txt not found."
    exit 1
fi

# Read each line in the file and create folders, then move matching files
while read -r barcode new_name; do
    mkdir -p "${new_name}"
    for file in SQK-NBD114-96_barcode${barcode}.bam; do
        if [ -e "$file" ]; then
            mv "$file" "${new_name}/"
            echo "Moved $file to ${new_name}/"
        else
            echo "Error: $file not found."
        fi
    done
done < barcodes.txt
