#!/usr/bin/env genome-perl

BEGIN { 
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above "Genome";
use Test::More;
use Genome::Test::Factory::InstrumentData::Imported;
use Genome::Test::Factory::InstrumentData::MergedAlignmentResult;
use Genome::Test::Factory::Model::ImportedVariationList;
use Genome::Test::Factory::Model::SomaticValidation;
use Genome::Test::Factory::Build;
use Genome::Test::Factory::Sample;
use Genome::Utility::Test;

my $package = 'Genome::Model::SomaticValidation::Command::VerifyBam';

use_ok($package);
my $test_dir = Genome::Utility::Test->data_dir_ok($package, "v1");

my $validation_build = setup_objects();

for my $mode (qw(normal tumor)) {
    my $command = Genome::Model::SomaticValidation::Command::VerifyBam->create(build_id => $validation_build->id, mode => $mode);
    ok($command->isa($package), "Created command");
    ok($command->execute, "Executed command");
    my $directory = File::Spec->join($validation_build->data_directory, "verifyBamId", $mode);
    ok(-s File::Spec->join($directory, "output.selfSM"), ".selfSM file has size");
    test_metrics($validation_build, $mode);
}

done_testing;

sub test_metrics {
    my $build = shift;
    my $mode = shift;
    for my $metric(qw(freemix chipmix af_count)) {
        my $metric_name = "$metric-$mode";
        my $value = $build->get_metric($metric_name);
        ok(defined $value, "Metric $metric_name is defined: $value");
        ok($value ne "NA", "Metric $metric_name is not NA");
        ok($value > 0, "Metric $metric_name > 0")
    }
}

sub setup_objects {
    my $sample1 = Genome::Test::Factory::Sample->setup_object();
    my $sample2 = Genome::Test::Factory::Sample->setup_object(source_id => $sample1->source->id);
    my $lib1 = Genome::Test::Factory::Library->setup_object(sample_id => $sample1->id, name => $sample1->name."-microarraylib");
    my $lib2 = Genome::Test::Factory::Library->setup_object(sample_id => $sample2->id, name => $sample2->name."-microarraylib");

    my $id1 = Genome::Test::Factory::InstrumentData::Imported->setup_object(
        library_id => $lib1->id,
        import_source_name => "tgi",
        genotype_file => $test_dir.'/1.genotype',
    );
    ok(-s $id1->genotype_file, 'genotype file set');
    $sample1->default_genotype_data_id($id1->id);

    my $id2 = Genome::Test::Factory::InstrumentData::Imported->setup_object(
        library_id => $lib2->id,
        import_source_name => "tgi",
        genotype_file => $test_dir.'/1.genotype',
    );
    ok(-s $id2->genotype_file, 'genotype file set');
    $sample2->default_genotype_data_id($id2->id);

    my $tmp_dir = Genome::Sys->create_temp_directory;
    Genome::Sys->copy_file(File::Spec->join($test_dir, "1.vcf"),
                            File::Spec->join($tmp_dir, "snvs.hq.vcf"));
    my $dbsnp_result = Genome::Model::Tools::DetectVariants2::Result::Manual->__define__(output_dir => $tmp_dir);
    my $dbsnp_model = Genome::Test::Factory::Model::ImportedVariationList->setup_object();
    my $dbsnp_build = Genome::Test::Factory::Build->setup_object(model_id => $dbsnp_model->id, version => "fake",
                                                                snv_result => $dbsnp_result);
    $dbsnp_build->reference->allosome_names("X,Y,MT");

    my $merged_result1 = Genome::Test::Factory::InstrumentData::MergedAlignmentResult->setup_object(
        bam_path => File::Spec->join($test_dir, "1.bam"),
    );
    my $merged_result2 = Genome::Test::Factory::InstrumentData::MergedAlignmentResult->setup_object(
        bam_path => File::Spec->join($test_dir, "2.bam"),
    );

    my $pp = Genome::Test::Factory::ProcessingProfile::SomaticValidation->setup_object(
                                                            verify_bam_id_version => "20120620");
    my $model = Genome::Test::Factory::Model::SomaticValidation->setup_object(
                                                            tumor_sample => $sample1,
                                                            normal_sample => $sample2,
                                                            previously_discovered_variations_build => $dbsnp_build,
                                                            processing_profile_id => $pp->id,
                                                            );
    my $build = Genome::Test::Factory::Build->setup_object(model_id => $model->id);

    Genome::SoftwareResult::User->create(software_result => $merged_result1, user => $build, label => "merged_alignment");
    Genome::SoftwareResult::User->create(software_result => $merged_result2, user => $build, label => "control_merged_alignment");

    return $build;
}

