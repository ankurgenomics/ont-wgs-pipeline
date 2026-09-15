#!/usr/bin/env nextflow

/*
* SETUP PARAMETERS IN CONFIG FILE
*/

process ALN {
    tag "minimap2 ALN $sample"
    label "xl"
    container '<your-registry>/minimap2_samtools:latest'

    input:
    tuple val(sample), path(reads)
    path ref

    output:
    tuple val(sample), path("${sample}.sorted.{bam,bam.bai}"), emit: srt_bam

    script:
    """
    minimap2 -ax map-ont -t ${task.cpus} \
	-R "@RG\\tID:${sample}\\tSM:${sample}\\tPL:ONT" \
	${ref[0]} ${reads} \
	| samtools sort -@ ${task.cpus} -o ${sample}.sorted.bam -
    samtools index -@ ${task.cpus} ${sample}.sorted.bam
    """
}

process COVERAGE_QC {
    tag "mosdepth QC $sample"
    label "med"
    container '<your-registry>/mosdepth:latest'

    publishDir "${params.outdir}/${sample}/stats", pattern: "*.{txt,gz,csi}", mode: "copy"

    input:
    tuple val(sample), path(bam)

    output:
    path("${sample}.mosdepth.*"), emit: stats

    script:
    """
    mosdepth -t ${task.cpus} --no-per-base ${sample} ${bam[0]}
    samtools flagstat -@ ${task.cpus} ${bam[0]} > ${sample}.flagstat.txt
    """
}

process CLAIR3_CALL {
    tag "Clair3 SNV/indel calling $sample"
    label "xl"
    container '<your-registry>/clair3:latest'

    publishDir "${params.outdir}/${sample}/bam_vcf", pattern: "*.vcf.gz*", mode: "copy"

    input:
    tuple val(sample), path(bam)
    path ref
    path clair3_model

    output:
    tuple val(sample), path("${sample}.clair3.vcf.gz{,.tbi}"), emit: vcf

    script:
    """
    run_clair3.sh \
	--bam_fn=${bam[0]} \
	--ref_fn=${ref[0]} \
	--threads=${task.cpus} \
	--platform="ont" \
	--model_path=${clair3_model} \
	--output=clair3_out \
	--sample_name=${sample}

    mv clair3_out/merge_output.vcf.gz ${sample}.clair3.vcf.gz
    mv clair3_out/merge_output.vcf.gz.tbi ${sample}.clair3.vcf.gz.tbi
    """
}

process SNIFFLES_SV {
    tag "Sniffles2 SV calling $sample"
    label "lg"
    container '<your-registry>/sniffles:latest'

    publishDir "${params.outdir}/${sample}/bam_vcf", pattern: "*.sv.vcf.gz", mode: "copy"

    input:
    tuple val(sample), path(bam)
    path ref

    output:
    path("${sample}.sv.vcf.gz"), emit: sv_vcf

    script:
    """
    sniffles --input ${bam[0]} \
	--reference ${ref[0]} \
	--threads ${task.cpus} \
	--sample-id ${sample} \
	--vcf ${sample}.sv.vcf.gz
    """
}

process METH_CALL {
    tag "modkit 5mC calling $sample"
    label "med"
    container '<your-registry>/modkit:latest'

    publishDir "${params.outdir}/${sample}/methyl", pattern: "*.bedmethyl.gz", mode: "copy"

    input:
    tuple val(sample), path(bam)

    output:
    path("${sample}.bedmethyl.gz"), emit: bedmethyl

    script:
    """
    modkit pileup ${bam[0]} ${sample}.bedmethyl --threads ${task.cpus}
    gzip ${sample}.bedmethyl
    mv ${sample}.bedmethyl.gz ${sample}.bedmethyl.gz
    """
}

workflow {
    ch_reads = Channel
        .fromPath( params.reads, checkIfExists: true )
        .splitCsv( header: true )
        .map{ row -> [row.sample_id, file(row.fastq)] }
    ch_ref = Channel.fromPath( [params.ref, params.fai], checkIfExists: true )
    ch_clair3_model = Channel.fromPath( params.clair3_model, checkIfExists: true )

    ALN( ch_reads, ch_ref.toList() )
    COVERAGE_QC( ALN.out.srt_bam )
    CLAIR3_CALL( ALN.out.srt_bam, ch_ref.toList(), ch_clair3_model )
    SNIFFLES_SV( ALN.out.srt_bam, ch_ref.toList() )

    if ( params.call_methylation ) {
        METH_CALL( ALN.out.srt_bam )
    }
}
