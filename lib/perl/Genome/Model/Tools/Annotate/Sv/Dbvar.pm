package Genome::Model::Tools::Annotate::Sv::Dbvar;

use strict;
use warnings;
use Genome;

class Genome::Model::Tools::Annotate::Sv::Dbvar {
    is => "Genome::Model::Tools::Annotate::Sv::Base",
    doc => "Annotate overlaps with dbvar SVs",
    has_input => [
        annotation_file => {
            is => 'Text',
            doc => 'File containing UCSC table',
            example_values => [map {$_->data_directory."/dbvar.tsv"} Genome::Db->get(source_name => 'dbvar')],
        },
        overlap_fraction => {
            is => 'Number',
            doc => 'Fraction of overlap (reciprocal) required to hit',
            default => 0.5,
        },
        wiggle_room => {
            is => 'Number',
            doc => 'Window in which the breakpoint can match',
            default => 200,
        },
    ],
};

sub help_detail {
    return "Determines whether the SV breakpoints match a dbVar SV within some distance.  It also checks to see that the SV and the dbVar SV reciprocally overlap each other by a given fraction.";
}

sub process_breakpoint_list {
    my ($self, $breakpoints_list) = @_;
    my %output;
    my $dbvar_annotation = $self->read_dbvar_annotation($self->annotation_file);
    $self->annotate_interval_overlaps($breakpoints_list, $dbvar_annotation, "dbvar_annotation", $self->wiggle_room);
    foreach my $chr (keys %{$breakpoints_list}) {
        foreach my $item (@{$breakpoints_list->{$chr}}) {
            my $key = $self->get_key_from_item($item);
            my $a = $item->{dbvar_annotation}->{bpA};
            my $b = $item->{dbvar_annotation}->{bpB};
            $output{$key} = [$self->get_var_annotation($item, $a, $b, $self->overlap_fraction)];
        }
    }
    return \%output;
}

sub column_names {
    return ('dbvar');
}

sub read_dbvar_annotation {
    my $self = shift;
    my $file = shift;

    my %annotation;
    my $in = Genome::Sys->open_file_for_reading($file) || die "Unable to open annotation: $file\n";

    while (my $line = <$in>) {
       chomp $line;
       next if ($line =~ /^\#/);
       my $p;
       my @fields = split /\t+/, $line;
       $p->{chrom} = $fields[0];
       $p->{bpA} = $fields[3];
       $p->{bpB} = $fields[4];
       $p->{name} = $fields[8];
       $p->{chrom} =~ s/chr//;
       push @{$annotation{$p->{chrom}}}, $p;
    }
    return \%annotation;
}

1;

