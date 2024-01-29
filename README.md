# Bacterial genome assembly using Oxford Nanopore long-read sequencing
**About**

This script is a pipeline for the filtering, QC, assembly and annotation of bacterial genomes. 

**Usage**

This pipeline can be used with data sequenced using R10.4.1 Nanopore flow cells with a <5% read error rate. It allows for the use of fastq.gz files output by basecalling using MinKNOW, or using bam files output by basecalling in Dorado.
To run, create a conda/mamba environment using nano_env.yml (conda env create -f nano_env.yml), and install checkm2 in a conda environment called checkm
Then simply download this script and run!

It has a few options:
- -d, --directory: pass the directory containing folders of reads for each bacteria on the command line (REQUIRED)
- -f, --format: specify the input format of the reads as either fastq.gz or bam. default: fastq.gz
- --skip-qc: whether to skip QC metrics via nanoplot. default: false
- --skip-assembly: whether to run the assembly steps using flye. default: false
- --skip-annotation: whether to run the annotation steps after assembly (adds quite a bit of time to run). default: false

Note: the script runs qc > assembly > annotation. If you skip assembly but not annotation, it will break!

Example:
nanopore_assembly.sh -d /home/ubuntu/bacteria -f bam --annotate

This script assumes you have your data in a folder structure as output when demultiplexing in MinKNOW, e.g. specifying --directory as /home/ubuntu/bacteria/lib/fastq_pass

  -- barcode01
  -- barcode02
  -- barcode03

etc

it also works best if you rename each the barcode folders with a unique identifier as output files will use folder name to rename - nanopore_bam.sh will rename the folders (barcode01, barcode02) to the corresponding name in a file called barcodes.txt
