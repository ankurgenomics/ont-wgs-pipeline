#!/usr/bin/env bash

# Reference genome (GATK hg38 bundle, same reference used across GATK/Sentieon-based
# short-read pipelines, so results stay comparable across platforms)
aws s3 sync --no-sign-request s3://ngi-igenomes/igenomes/Homo_sapiens/GATK/GRCh38/Sequence/WholeGenomeFasta/ .

# Clair3 models are versioned per basecaller chemistry/model. Pick the one matching the
# basecaller model actually used to generate your FASTQs (e.g. dna_r10.4.1_e8.2_400bps_sup).
# See: https://github.com/nanoporetech/rerio and the Clair3 releases page for current model names.
CLAIR3_MODEL="r1041_e82_400bps_sup_v500"
wget "https://github.com/nanoporetech/rerio/raw/master/clair3_models/${CLAIR3_MODEL}.tar.gz"
tar -zxvf "${CLAIR3_MODEL}.tar.gz"
rm -f "${CLAIR3_MODEL}.tar.gz"
