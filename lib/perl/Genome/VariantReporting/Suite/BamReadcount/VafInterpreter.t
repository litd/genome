#!/usr/bin/env genome-perl

BEGIN { 
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above "Genome";
use Test::More;
use Test::Exception;
use Genome::File::Vcf::Entry;
use Genome::VariantReporting::Suite::BamReadcount::TestHelper qw(
    bam_readcount_line create_entry bam_readcount_line_deletion create_deletion_entry);

my $pkg = 'Genome::VariantReporting::Suite::BamReadcount::VafInterpreter';
use_ok($pkg);
my $factory = Genome::VariantReporting::Framework::Factory->create();
isa_ok($factory->get_class('interpreters', $pkg->name), $pkg);

subtest "one alt allele" => sub {
    my $interpreter = $pkg->create(sample_name => "S1");
    lives_ok(sub {$interpreter->validate}, "Interpreter validates");

    my %expected = (
        G => {
            S1_vaf => 99.1279069767442,
            S1_ref_count => 3,
            S1_var_count => 341,
            'Solexa-135852_var_count' => '155',
            'Solexa-135853_var_count' => '186',
            'Solexa-135852_ref_count' => '2',
            'Solexa-135853_ref_count' => '1',
            'Solexa-135852_vaf' => '87.0786516853933',
            'Solexa-135853_vaf' => '99.4652406417112',
        }
    );

    my $entry = create_entry(bam_readcount_line);
    my %result = $interpreter->interpret_entry($entry, ['G']);
    is_deeply(\%result, \%expected, "Values are as expected");
};

subtest "insertion" => sub {
    my $interpreter = $pkg->create(sample_name => "S4");
    lives_ok(sub {$interpreter->validate}, "Interpreter validates");

    my %expected = (
        AA => {
            S4_vaf => 5.81395348837209,
            S4_ref_count => 3,
            S4_var_count => 20,
            'Solexa-135852_var_count' => '20',
            'Solexa-135853_var_count' => '0',
            'Solexa-135852_ref_count' => '2',
            'Solexa-135853_ref_count' => '1',
            'Solexa-135852_vaf' => '11.2359550561798',
            'Solexa-135853_vaf' => '0',
        }
    );

    my $entry = create_entry(bam_readcount_line);
    my %result = $interpreter->interpret_entry($entry, ['AA']);
    is_deeply(\%result, \%expected, "Values are as expected");
};

subtest "deletion" => sub {
    my $interpreter = $pkg->create(sample_name => "S1");
    lives_ok(sub {$interpreter->validate}, "Interpreter validates");

    my %expected = (
        A => {
            S1_vaf => 5.81395348837209,
            S1_ref_count => 5,
            S1_var_count => 20,
            'Solexa-135852_var_count' => '20',
            'Solexa-135853_var_count' => '0',
            'Solexa-135852_ref_count' => '3',
            'Solexa-135853_ref_count' => '2',
            'Solexa-135852_vaf' => '11.0497237569061',
            'Solexa-135853_vaf' => '0',
        }
    );

    my $entry = create_deletion_entry(bam_readcount_line_deletion);
    my %result = $interpreter->interpret_entry($entry, ['A']);
    is_deeply(\%result, \%expected, "Values are as expected");
};
done_testing;

