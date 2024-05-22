#!/bin/bash

#help menu function
help() {
    cat << EOF
Usage: $(basename "$0") -d DATABASE -c [docker|singularity]

Options:
  -d, --database    Specify the directory for database installation (required)
EOF
    exit 1
}

#command line options
while getopts ":d:h:" option; do
    case $option in
        d|--database) database=$OPTARG ;;
        h|--help) help ;;
        *) echo "Unknown option ${OPTARG}"; help ;;
    esac
done

# Create necessary database directories
mkdir -p "${database}/bakta" \
    && mkdir "${database}/kraken2" \
    && mkdir "${database}/checkm"

# Run filtering steps via docker image 
docker run \
    -v "${database}":/workdir/database \
    -u `id -u $USER`:`id -g $USER` \
    samueltmontgomery/bacassdb \
    /workdir/bin/db_install.sh