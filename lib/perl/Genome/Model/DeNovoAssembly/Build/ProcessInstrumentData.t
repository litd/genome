#!/usr/bin/env genome-perl

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
    $ENV{UR_COMMAND_DUMP_STATUS_MESSAGES} = 1;
};

use strict;
use warnings;

use above 'Genome';

use Genome::Utility::Test 'compare_ok';
use Test::More;

use_ok('Genome::Model::DeNovoAssembly::Build::ProcessInstrumentData') or die;
use_ok('Genome::Model::DeNovoAssembly::Build::Test') or die;

my $build = Genome::Model::DeNovoAssembly::Build::Test->build_for_assembler('soap de-novo-assemble');
ok($build, 'build for testing');
my $example_build = Genome::Model::DeNovoAssembly::Build::Test->build_for_assembler('soap de-novo-assemble');
ok($example_build, 'example build');

my $process = Genome::Model::DeNovoAssembly::Build::ProcessInstrumentData->create(
    build => $build,
    instrument_data => $build->instrument_data,
);
ok($process, 'create process instrument data');

ok(!$process->shortcut, 'failed to shortcut');
ok($process->execute, 'execute succeeded');
ok($process->sx_result, 'set sx result on process inst data');
ok($process->shortcut, 'shortcut succeeded');

for (1..2) {
    compare_ok($process->sx_result->output_dir.'/-7777.'.$_.'.fastq', $ENV{GENOME_TEST_INPUTS}.'/Genome-Model/DeNovoAssembly/Build-ProcessInstrumentData-v1/-7777.'.$_.'.fastq', "fastq $_ matches");
}

#print $process->sx_result->output_dir."\n";<STDIN>;
done_testing();
