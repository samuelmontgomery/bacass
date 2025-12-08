#!/bin/bash

# Initialise values
input=""
output=""
format="fastq.gz"
length=""
cpus=""

#help menu function
help() {
    cat << EOF
Usage: $(basename "$0") -i INPUT -o OUTPUT [-p PLATFORM] -d DATABASE [-f FORMAT] -g LENGTH -t CPUs

Options:
  -i, --input       Specify the input directory path (required)
  -o, --output      Specify the output directory path (required)
  -f, --format      Specify the input format (default: fastq.gz, options: bam)
  -l, --length      Specify the expected genome length (required)
  -d, --database    Specify the directory of bakta database (required)
  -t, --cpus        Specify the number of CPUs/threads to use for the pipeline (default: 16)
EOF
    exit 1
}

#command line options
while getopts ":i:o:p:d:l:f:t:h:" option; do
    case $option in
        i|--input) input=$OPTARG ;;
        o|--out) output=$OPTARG ;;
        f|--format) format=$OPTARG ;;
        l|--length) length=$OPTARG ;;
        d|--database) database=$OPTARG ;;
        t|--cpus) cpus=$OPTARG ;;
        h|--help) help ;;
        *) echo "Unknown option ${OPTARG}"; help ;;
    esac
done


# Check if required options are provided
if [ -z "${input}" ] || [ -z "${output}" ] || [ -z "${database}" ] || [ -z "${length}" ]; then
    echo "Error: Input/output/database paths and predicted chromosome length are required"
    help
fi

# Print options supplied to terminal
cat << EOF
    Input directory: $input
    Output directory: $output
    Format of input files: $format
    Genome length: $length
    Number of CPUs: $cpus
EOF

# Create env file for Docker
cat << EOF > "${output}"/env.list
    format=${format}
    length=${length}
    cpus=${cpus}
EOF

# Run filtering steps via docker image 
docker run \
    --env-file "${output}"/env.list \
    -v "${input}":/workdir/input \
    -v "${output}":/workdir/output \
    -v "${database}":/workdir/database \
    -u `id -u $USER`:`id -g $USER` \
    samueltmontgomery/bacass:latest \
    /workdir/bin/bacass.sh