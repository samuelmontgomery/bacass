# Get base ubuntu docker image
FROM condaforge/miniforge3:25.3.0-3

# Install and update packages
RUN mamba install \
    -c conda-forge \
    -c bioconda \
    --yes \
    python=3.11  \
    kraken2=2.1.5 \
    samtools=1.22.0 \
    nanoplot=1.44.1 \
    parallel=20250422 \
    dnaapler=1.2.0 \
    flye=2.9.6 \
    bakta=1.11.0 \
    minimap2=2.29 \
    qualimap=2.3 \
    checkm-genome=1.2.3 \
    chopper=0.10.0 \
    genomad=1.11.0 \
    && mamba clean -afy \
    && mkdir -p workdir/input \
    && mkdir workdir/output \
    && mkdir workdir/bin \
    && mkdir workdir/database

# Copy in running script with correct permissions
COPY --chmod=0755 lib/bacass.sh /workdir/bin
COPY --chmod=0755 lib/db_install.sh /workdir/bin

# Add bin directory to path
ENV PATH="$PATH:/workdir/bin"
