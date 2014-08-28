package Genome::Model::ClinSeq::Command::GenerateClonalityPlots::Readcounts;

use strict;
use warnings;

use Genome;
use Genome::Model::Tools::Vcf::Helpers qw/convertIub/;

class Genome::Model::ClinSeq::Command::GenerateClonalityPlots::Readcounts {
    is => 'Command::V2',
    has_input => [
        sites_file => {
            is => 'Text',
            doc => 'List of chromosome sites for which to get BAM readcounts (format: "1	16949959	16949959	G	R")',
        },
        bam_files => {
            is => 'Text',
            doc => 'The BAM files to interrogate, with labels (e.g. "Tumor:/path/to/tumor.bam")',
            is_many => 1,
        },
        reference_build => {
            is => 'Genome::Model::Build::ReferenceSequence',
            doc => 'The reference used to align the data in the BAMs',
        },
        output_file => {
            is => 'Text',
            is_output => 1,
            doc => 'Where to save the results',
        },
        bam_readcount_version => {
            is => 'Text',
            is_optional => 1,
            doc => 'The version of bam-readcounts to use',
        },
    ],
    doc => 'Get readcounts from a series of BAMs for the positions specified in the sites file',
};

sub execute {
    my $self = shift;

    my $reference_fasta = $self->reference_build->full_consensus_path('fa');
    my @bams = $self->bam_files;
    my @types;
    my $out_fh = Genome::Sys->open_file_for_writing($self->output_file);

    #headers
    print $out_fh join("\t", '#Chr', 'Start', 'Stop');
    for my $bam (@bams) {
        my ($type,$bam) = split /:/,$bam;
        push @types,$type;
        print $out_fh map { "\t${type}_$_" } qw(Ref Var Ref_Count Var_Count Var_Freq);
    }
    print $out_fh "\n";

    my ($site_list_for_readcount_fh, $site_list_for_readcount) = Genome::Sys->create_temp_file();
    my $sites_fh = Genome::Sys->open_file_for_reading($self->sites_file);

    #begin to load output hash
    my %output;
    while (my $line = $sites_fh->getline) {
        chomp $line;
        my ($chr,$start,$stop) = split /\t/,$line;
        $output{$chr}{$start} = {};

        $site_list_for_readcount_fh->say(join("\t", $chr, $start, $stop));
    }
    $sites_fh->close;

    #cycle through bams to get readcounts
    for my $bam (@bams) {
        my $temp_readcount_file = Genome::Sys->create_temp_file_path();
        my ($type,$bam) = split /:/,$bam;

        my $rv = Genome::Model::Tools::Sam::Readcount->execute(
            bam_file => $bam,
            minimum_mapping_quality => 1,
            output_file => $temp_readcount_file,
            reference_fasta => $reference_fasta,
            region_list => $site_list_for_readcount,
            use_version => $self->bam_readcount_version,
        );

        my $sites = $self->sites_file;
        $self->convert_readcounts_to_stats(
            \%output,
            $type,
            $self->sites_file,
            $temp_readcount_file
        );
    }

    #print output
    for my $chr (sort keys %output) {
        for my $pos (sort keys %{$output{$chr}}) {
            print $out_fh join("\t", $chr, $pos, $pos);
            for my $type (@types) {
                if (exists $output{$chr}{$pos}{$type}) {
                    print $out_fh "\t".$output{$chr}{$pos}{$type};
                } else {
                    print $out_fh ("\tNA" x 5);
                }
            }
            print $out_fh "\n";
        }
    }

    return 1;
}

sub convert_readcounts_to_stats {
    my $self = shift;

    my $stats = shift;
    my $type = shift;
    my $sites_file = shift;
    my $readcounts_file = shift;

    my %refHash;
    my %varHash;


    #read in all the snvs and hash both the ref and var allele by position
    my $sites_fh = Genome::Sys->open_file_for_reading( $sites_file );
    while( my $line = $sites_fh->getline )
    {
        chomp($line);
        my @fields = split("\t",$line);
        $refHash{$fields[0] . "|" . $fields[1]} = $fields[3];
        $varHash{$fields[0] . "|" . $fields[1]} = $fields[4]
    }
    $sites_fh->close();

    #read in the bam-readcount file
    my $readcounts_fh = Genome::Sys->open_file_for_reading( $readcounts_file );
    while( my $line = $readcounts_fh->getline )
    {
        chomp($line);
        my ($chr, $pos, $ref, $depth, @counts) = split("\t",$line);

        my $ref_count = 0;
        my $var_count = 0;
        my $knownRef;
        my $knownVar;

        #for each base at that pos
        foreach my $count_stats (@counts) {
            my ($allele, $count, $mq, $bq) = split /:/, $count_stats;

            # skip if it's not in our list of snvs
            next unless (exists($refHash{$chr . "|" . $pos}) && exists($varHash{$chr . "|" . $pos}));

            #look up the snv calls at this position
            $knownRef = $refHash{$chr . "|" . $pos};
            $knownVar = $varHash{$chr . "|" . $pos};

            # assume that the ref call is ACTG, not iub
            # (assumption looks valid in my files)
            if ($allele eq $knownRef){
                $ref_count += $count;
            }

            # if this base is included in the IUB code for
            # for the variant, (but doesn't match the ref)
            if (matchIub($allele,$knownRef,$knownVar)){
                $var_count += $count;
            }
        }

        my $var_freq = 0;
        if ($depth ne '0') {
            $var_freq = $var_count/$depth * 100;
        }

        #output
        $stats->{$chr}{$pos}{$type} = join("\t",
            $knownRef, $knownVar, $ref_count, $var_count, sprintf("%.2f", $var_freq)
        );
    }
    $readcounts_fh->close();
}

#
sub matchIub{
    my ($allele,$ref,$var) = @_;
    my @var_iubs = split(",",convertIub($var));
    my @ref_iubs = split(",",convertIub($ref));
    foreach my $i (@var_iubs){
        unless (grep {$_ eq $i} @ref_iubs) {
            if ($allele eq $i){
                return 1;
            }
        }
    }
    return 0;
}


1;
