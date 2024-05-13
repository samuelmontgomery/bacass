# Bacass - a pipeline for bacterial genome assembly from long-read sequences


## About
Bacass is a workflow for filtering reads, *de novo* genome assembly, and genome annotation for bacterial isolates. 

## Installation

This workflow utilises docker for downloading the required databases and running the pipeline.

To install, clone this repository into a local environment

```
git clone https://github.com/samuelmontgomery/nanopore_bacass
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
