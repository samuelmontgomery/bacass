#!/bin/bash

export database="/workdir/database"

cd "${database}"

# Install CheckM2 database
checkm2 database --download --path "${database}/checkm2"
