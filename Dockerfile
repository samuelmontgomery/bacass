# Get base ubuntu docker image
FROM condaforge/miniforge3:25.11.0-0

# Install and update packages
RUN mamba install \
    -c conda-forge \
    -c bioconda \
    --yes \
    python=3.11  \
    kraken2=2.17.1 \
    samtools=1.22.0 \
    nanoplot=1.46.2 \
    parallel=20250422 \
    dnaapler=1.3.0 \
    flye=2.9.6 \
    bakta=1.11.4 \
    minimap2=2.30 \
    qualimap=2.3 \
    checkm-genome=1.2.4 \
    chopper=0.12.0 \
    genomad=1.11.2 \
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
