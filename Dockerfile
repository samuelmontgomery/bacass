# Get base ubuntu docker image
FROM condaforge/miniforge3:24.3.0-0

# Install and update packages
RUN mamba install \
    -c conda-forge \
    -c bioconda \
    --yes \
    samtools=1.20.0 \
    filtlong=0.2.1 \
    nanoplot=1.42.0 \
    parallel=20240722 \
    dnaapler=0.8.0 \
    flye=2.9.5 \
    bakta=1.9.4 \
    minimap2=2.28 \
    qualimap=2.3 \
    checkm-genome=1.2.3 \
    kraken2=2.1.3 \
    mlst=2.23.0 \
    chopper=0.9.0 \
    genomad=1.8.0 \
    && mamba clean -afy \
    && mkdir -p workdir/input \
    && mkdir workdir/output \
    && mkdir workdir/bin \
    && mkdir workdir/database

# Copy in running script with correct permissions
COPY --chmod=0755 lib/bacass.sh /workdir/bin

# Add bin directory to path
ENV PATH="$PATH:/workdir/bin"
