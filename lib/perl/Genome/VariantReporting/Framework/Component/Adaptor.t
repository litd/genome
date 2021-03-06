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
use Genome::VariantReporting::Framework::Plan::MasterPlan;
use Sub::Override;

my $pkg = 'Genome::VariantReporting::Framework::Component::Adaptor';
use_ok($pkg);

my $test_data_dir = __FILE__ . '.d';

my $plan_file = File::Spec->join($test_data_dir, 'plan.yaml');
my $adaptor = Genome::VariantReporting::Framework::Test::Adaptor->create(
    plan_json => Genome::VariantReporting::Framework::Plan::MasterPlan->create_from_file($plan_file)->as_json,
);

lives_ok { $adaptor->resolve_plan_attributes } 'resolve_plan_attributes execute successfully';
is($adaptor->__planned__, 'foo', 'Value of __planned__ is as expected');

done_testing;
