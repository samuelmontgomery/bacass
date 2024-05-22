# Bacass - a pipeline for bacterial genome assembly from long-read sequences


## About
Bacass is a workflow for filtering reads, *de novo* genome assembly, and genome annotation for bacterial isolates. 

## Installation

This workflow utilises docker for downloading the required databases and running the pipeline, and requires a working docker or singularity/apptainer installation

To install, clone this repository into a local environment

```
git clone https://github.com/samuelmontgomery/bacass
```

### Database installation

To install the databases, first pull down the docker image for installation

```
docker pull samueltmontgomery/bacassdb
singularity pull docker://samueltmontgomery/bacassdb
```

Then run the install.db wrapper script specifying the database location e.g.

```
install_db.sh -d /scratch/database -c [docker|singularity]
```
## Running the pipeline

To run the pipeline, first pull down or build the dockerfile

```
docker pull samueltmontgomery/bacass
singularity pull docker://samueltmontgomery/bacass
```
then run the wrapper script

```
bac_assembly.sh -i INPUT -o OUTPUT [-p PLATFORM] -d DATABASE [-f FORMAT] -g LENGTH -c [docker|singularity]

Options:
  -i, --input       Specify the input directory path (required)
  -o, --output      Specify the output directory path (required)
  -f, --format      Specify the input format (default: fastq.gz, options: bam)
  -l, --length      Specify the expected genome length (required)
  -d, --database    Specify the directory of bakta database (required)
  -c, --container   Specify either docker or singularity for running the pipeline (required)
```
