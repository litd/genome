package Genome::Model::GenotypeMicroarray::GenotypeFile::ReaderFactory;

use strict;
use warnings;

use Genome;

use Genome::Model::GenotypeMicroarray::GenotypeFile::ReadTsv;
use Genome::Model::GenotypeMicroarray::GenotypeFile::ReadTsvAndAnnotate;

class Genome::Model::GenotypeMicroarray::GenotypeFile::ReaderFactory { 
    is => 'UR::Singleton',
};

sub build_reader {
    my ($class, $for, $variation_list_build) = @_;

    Carp::confess('Nothing given to build reader!') if not $for;

    my $genotype_reader;
    if ( $for->isa('Genome::InstrumentData') ) {
        Carp::confess('No variation list build given to build reader!') if not $variation_list_build;
        $genotype_reader = $class->_build_reader_for_instrument_data($for, $variation_list_build);
    }
    elsif ( $for->isa('Genome::Model::Build::GenotypeMicroarray') ) {
        $genotype_reader = $class->_build_reader_for_build($for);
    }
    else {
        Carp::confess('Do not know how to build genotype file reader for source! '.$for->__display_name__);
    }

    my $reader = Genome::Model::GenotypeMicroarray::GenotypeFile::Reader->create(
        reader => $genotype_reader,
    );

    return $reader;
}

sub _build_reader_for_instrument_data {
    my ($class, $instrument_data, $variation_list_build) = @_;

    my $genotype_file = eval{ $instrument_data->attributes(attribute_label => 'genotype_file')->attribute_value; };
    if ( not $genotype_file or not -s $genotype_file ) {
        $class->error_message('No genotype file for instrument data! '.$instrument_data->id);
        return;
    }

    my $snp_id_mapping = Genome::InstrumentData::Microarray->get_snpid_hash_for_variant_list(
        $instrument_data, $variation_list_build
    );

    my $reader = Genome::Model::GenotypeMicroarray::GenotypeFile::ReadTsvAndAnnotate->create(
        input => $genotype_file,
        variation_list_build => $variation_list_build,
        snp_id_mapping => $snp_id_mapping,
    );

    return $reader;
}

sub _build_reader_for_build {
    my ($class, $build) = @_;

    # TODO add vcf!
    my $genotype_file = $build->original_genotype_file_path;
    my $reader = Genome::Model::GenotypeMicroarray::GenotypeFile::ReadTsv->create(
        input => $genotype_file,
    );

    return $reader;
}

1;

