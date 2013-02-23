#!/usr/bin/env genome-perl
use strict;
use warnings;

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
};

use above 'Genome';
use Test::More;
use Genome::Model::RnaSeq::DetectFusionsResult::ChimerascanVrlResult;
use lib File::Basename::dirname(File::Spec->rel2abs(__FILE__));
use chimerascan_test_setup "setup";

my $chimerascan_version = '0.4.6';
my $picard_version = 1.82;
my ($alignment_result, $annotation_build) = setup(test_data_version => 3,
        picard_version => $picard_version,
        chimerascan_version => $chimerascan_version);


my $r = Genome::Model::RnaSeq::DetectFusionsResult::ChimerascanVrlResult->get_or_create(
    alignment_result => $alignment_result,
    version => $chimerascan_version,
    detector_params => "--bowtie-version=0.12.7 --reuse-bam 1",
    annotation_build => $annotation_build,
    picard_version => $picard_version,
);
isa_ok($r, "Genome::Model::RnaSeq::DetectFusionsResult::ChimerascanVrlResult");

done_testing();

1;
