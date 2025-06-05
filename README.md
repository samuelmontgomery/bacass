# Bacass - a pipeline for bacterial genome assembly from long-read sequences


## About
Bacass is a workflow for filtering reads, *de novo* genome assembly, and genome annotation for bacterial isolates. 

## Installation

This workflow utilises docker for downloading the required databases and running the pipeline, and requires a working docker installation

To install, clone this repository into a local environment

```
git clone https://github.com/samuelmontgomery/bacass
```

### Database installation

To install the databases, first pull down the docker images for installation

```
docker pull samueltmontgomery/bacass
docker pull samueltmontgomery/bacassqc
```

Then run the install_db wrapper script specifying the database location e.g.

```
install_db.sh -d /scratch/database
```
## Running the pipeline

To run the pipeline, first pull down or build the dockerfile then run the wrapper script

```
bac_assembly.sh -i INPUT -o OUTPUT [-p PLATFORM] -d DATABASE [-f FORMAT] -g LENGTH [-t CPUs]

Options:
  -i, --input       Specify the input directory path (required)
  -o, --output      Specify the output directory path (required)
  -f, --format      Specify the input format (default: fastq.gz, options: bam)
  -l, --length      Specify the expected genome length (required)
  -d, --database    Specify the directory of bakta database (required)
  -t, --cpus        Specify the number of CPUs/threads to use for the pipeline (default: 16)
```

The input for this pipeline should be run on the output from MinKNOW basecalling or dorado basecalling, as either folders of fastq.gz files split by barcode or as unmapped bam files respectively.

The pipeline requires an input file called "barcodes.txt" in the input folder, which is a tab separated file with your barcodes matching the actual bacteria IDs - there is an example in the test directory. Running the pipeline will either rename the folders containing fastq.gz files to match the isolate name in the barcodes.txt file, or create folders with the isolate name and move the bam files into the folders in the input directory

The results will be written into matching folders in the output directory

This directory structure is required for the parallelisation of the pipeline to reduce runtime