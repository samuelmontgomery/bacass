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

To install the databases, first pull down the docker image for installation

```
docker pull samueltmontgomery/bacassdb
```

Then run the install.db wrapper script specifying the database location e.g.

```
install_db.sh -d /scratch/database
```
## Running the pipeline

To run the pipeline, first pull down or build the dockerfile

```
docker pull samueltmontgomery/bacass
```
then run the wrapper script

```
bac_assembly.sh -i INPUT -o OUTPUT [-p PLATFORM] -d DATABASE [-f FORMAT] -g LENGTH

Options:
  -i, --input       Specify the input directory path (required)
  -o, --output      Specify the output directory path (required)
  -f, --format      Specify the input format (default: fastq.gz, options: bam)
  -l, --length      Specify the expected genome length (required)
  -d, --database    Specify the directory of bakta database (required)
```

The pipeline requires an input file called "barcodes.txt" in the input folder with your barcoded BAM files, which is a tab separated file with your barcodes matching the actual bacteria IDs - there is an example in the test directory

Running the pipeline will move your BAM files into individual folders matching the bacterial IDs, and then write into matching folders in the output directory

This directory structure is required for the parallelisation of the pipeline to reduce runtime
It also assumes you have 16 CPUs, and 64GB of system RAM - the script will need editing if that is not the case.