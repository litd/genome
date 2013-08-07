package Genome::File::Vcf::Entry;

use Data::Dumper;
use Carp qw/confess/;
use Genome;

use strict;
use warnings;

# column offsets in a vcf file
use constant {
    CHROM => 0,
    POS => 1,
    ID => 2,
    REF => 3,
    ALT => 4,
    QUAL => 5,
    FILTER => 6,
    INFO => 7,
    FORMAT => 8,
    FIRST_SAMPLE => 9,
};

=head1 NAME

Genome::File::Vcf::Entry

=head1 SYNOPSIS

    use Genome::File::Vcf::Entry;

    my $header = ...; # A Genome::File::Vcf::Header object;
    my $line = "$chrom\t$pos\t...";
    my $entry = new Genome::File::Vcf::Entry($header, $line);

    printf "CHROM:   %s\n", $entry->{chrom};
    printf "POS:     %s\n", $entry->{position};
    printf "IDENT:   %s\n", join(",", $entry->{identifiers});
    printf "REF:     %s\n", $entry->{reference_allele};
    printf "ALT:     %s\n", join(",", $entry->{alternate_alleles});
    printf "QUAL:    %s\n", $entry->{quality};
    # note that the following involve method calls rather than properties
    printf "FILTERS: %s\n" . join(";", $entry->filters);
    ...

    my $gmaf = $entry->info("GMAF");
    if (defined $gmaf) {
        ...
    }

    # REF: A, ALT: AC, ACT
    # Get all info fields for allele AC, paying attention to per-alt fields.
    my $ac_info_all = $entry->info_for_allele("AC");

    # or just get one field
    my $ac_info_gmaf = $entry->info_for_allele("AC", "GMAF");


    # Assume the format fields for the entry ar GT:DP:FT
    my @format_names = $entry->format;
    # @format_names = ("GT", "DP", "FT")

    my $idx = $entry->format_field_index("DP"); # $idx = 1
    my $idx = $entry->format_field_index("GL"); # $idx = undef

    my $cache = $entry->format_field_index;
    # $cache = {"GT" => 0, "DP" => 1, "FT" => 2}

=cut

sub new {
    my ($class, $header, $line) = @_;
    my $self = {
        header => $header,
        _line => $line,
    };
    bless $self, $class;
    $self->_parse;
    return $self;
}

sub _parse {
    my ($self) = @_;
    confess "Attempted to parse null VCF entry" unless $self->{_line};

    my @fields = split("\t", $self->{_line});
    $self->{_fields} = \@fields;

    # set mandatory fields
    $self->{chrom} = $fields[CHROM];
    $self->{position} = $fields[POS];

    my @identifiers = _parse_list($fields[ID], ',');
    $self->{identifiers} = \@identifiers;

    $self->{info_fields} = undef; # we parse them lazily later

    $self->{reference_allele} = $fields[REF];
    $self->{alternate_alleles} = [split(',', $fields[ALT])];
    $self->{quality} = $fields[QUAL] eq '.' ? undef : $fields[QUAL];
    $self->{_filter} = [_parse_list($fields[FILTER], ',')];
    $self->{_format} = [_parse_list($fields[FORMAT], ':')];
}

# This is to avoid warnings about splitting undef values and to translate
# '.' back to undef.
sub _parse_list {
    my ($identifiers, $delim) = @_;
    return if !$identifiers || $identifiers eq '.';
    return split($delim, $identifiers);
}

# transform a string A=B;C=D;... into a hashref { A=>B, C=>D, ...}
# take care about the string being . (_parse_list does this for us)
sub _parse_info {
    my $info_str = shift;
    my @info_list = _parse_list($info_str, ';');
    my %info_hash;
    my @info_order;
    for my $i (@info_list) {
        my ($k, $v) = split('=', $i, 2);
        # we do this rather than just split to handle Flag types (they have undef values)
        $info_hash{$k} = $v;
        push(@info_order, $k);
    }
    return { hash => \%info_hash, order => \@info_order };
}

# this assumes $self->{_format} is set
sub _parse_samples {
    my ($self) = @_; # arrayref of all vcf fields

    my $fields = $self->{_fields};

    # it is an error to have sample data with no format specification
    confess "VCF entry has sample data but no format specification: " . $self->{_line}
        if $#$fields >= FIRST_SAMPLE && !defined $self->{_format};

    my $n_fields = $#{$self->{_format}} + 1;

    my @samples;

    for my $i (FIRST_SAMPLE..$#$fields) {
        my $sample_idx = $i - FIRST_SAMPLE + 1;

        my @data = _parse_list($fields->[$i], ':');
        confess "Too many entries in sample $sample_idx:\n"
            ."sample string: $fields->[$i]\n"
            ."format string: " . join(":", $self->{_format})
            if (@data > $n_fields);

        push(@samples, \@data);
    }
    return \@samples;
}

sub alleles {
    my $self = shift;
    return ($self->{reference_allele}, @{$self->{alternate_alleles}});
}

sub has_indel {
    my $self = shift;
    for my $alt (@{$self->{alternate_alleles}}) {
        if (length($alt) != length($self->{reference_allele})) {
            return 1;
        }
    }
    return 0;
}

# return the index of the given allele, or undef if not found
# note that 0 => reference, 1 => first alt, ...
sub allele_index {
    my ($self, $allele) = @_;
    my @a = $self->alleles;
    my @idx = grep {$a[$_] eq $allele} 0..$#a;
    return unless @idx;
    return $idx[0]
}

# Examines GT fields in sample data and returns (#total alleles, counts)
# where counts is a hash mapping allele index -> frequency.
sub allelic_distribution {
    my ($self, @sample_indices) = @_;

    my $format = $self->format_field_index;
    my $gtidx = $format->{GT};
    my $sample_data = $self->sample_data;
    return unless defined $gtidx && defined $sample_data;

    # If @sample_indices was not passed, default to all samples
    @sample_indices = 0..$#{$sample_data} unless @sample_indices;

    # Find all samples that passed filters
    if (exists $format->{FT}) {
        my $ftidx = $format->{FT};
        @sample_indices = grep {
            my $ft = $sample_data->[$_]->[$ftidx];
            !defined $ft || $ft eq "PASS" || $ft eq "."
            } @sample_indices;
    }

    # Get all defined genotypes
    my @gts =
        grep {defined $_}
        map {$sample_data->[$_]->[$gtidx]}
        @sample_indices;

    # Split gts on |/ and flatten into one list
    my @allele_indices =
        grep {defined $_ && $_ ne '.'}
        map {split("[/|]", $_)}
        @gts;

    # Get list of all alleles (ref, alt1, ..., altn)
    my %counts;
    my $total = 0;
    for my $a (@allele_indices) {
        ++$counts{$a};
        ++$total;
    }
    return ($total, %counts);
}

sub info {
    my ($self, $key) = @_;

    if (!$self->{info_fields}) {
        $self->{info_fields} = _parse_info($self->{_fields}->[INFO]);
    }

    my $hash = $self->{info_fields}{hash};
    return $hash unless $key;

    return unless $hash && exists $hash->{$key};

    # The 2nd condition is to deal with flags, they may exist but not have a value
    return $hash->{$key} || exists $hash->{$key};
}

sub info_for_allele {
    my ($self, $allele, $key) = @_;

    # nothing to return
    my $hash = $self->info;
    return unless defined $hash;

    # we don't have that allele, or it is the reference (idx 0)
    my $idx = $self->allele_index($allele);
    return unless defined $idx && $idx > 0;
    --$idx; # we don't care about the reference allele

    # no header! what are you doing?
    confess "info_for_allele called on entry with no vcf header!" unless $self->{header};

    my @keys = defined $key ? $key : keys %$hash;

    my %result;
    for my $k (@keys) {
        my $type = $self->{header}->info_types->{$k};
        warn "Unknown info type $k encountered!" if !defined $type;
        if (defined $type && $type->{number} eq 'A') { # per alt field

            my @values = split(',', $hash->{$k});
            next if $idx > $#values;
            $result{$k} = $values[$idx];
        } else {
            $result{$k} = $hash->{$k}
        }
    }
    my $rv = $key ? $result{$key} : \%result;
    return $rv;
}

# remove PASS if the entry is filtered
sub _check_filters {
    my $self = shift;
    if ($self->is_filtered) {
        @{$self->{_filter}} = grep {!/^PASS$/} @{$self->{_filter}};
    }
}

# Get or set filters
sub filters {
    my ($self, @args) = @_;
    if (@args) {
        @{$self->{_filter}} = @args;
        $self->_check_filters;
    }

    return @{$self->{_filter}};
}

sub clear_filters {
    my $self = shift;
    $self->{_filter} = [];
}

# Add a filter
sub add_filter {
    my ($self, $filter) = @_;
    push @{$self->{_filter}}, $filter;
    $self->_check_filters;
}

sub is_filtered {
    my $self = shift;
    return grep { $_ && $_ ne "PASS" && $_ ne "."} @{$self->{_filter}};
}

sub _prepend_format_field {
    my ($self, $field) = @_;

    return 0;
}

sub add_format_field {
    my ($self, $field) = @_;
    if (!exists $self->{header}->format_types->{$field}) {
        confess "Format field '$field' does not exist in header";
    }

    if (exists $self->{_format_key_to_idx}{$field}) {
        return $self->{_format_key_to_idx}{$field};
    }
    elsif ($field eq "GT") {
        # GT is a special case in the Vcf spec. If present, it must be the first field

        # Increment all indexes by one since we are prepending something
        my $fmtidx = $self->{_format_key_to_idx};
        %$fmtidx = map {$_ => $fmtidx->{$_} + 1} keys %$fmtidx;

        # Prepend undef to all the existing sample entries
        unshift @{$self->{_format}}, $field;
        my $sample_data = $self->sample_data;
        for my $i (0..$#$sample_data) {
            unshift @{$sample_data->[$i]}, undef;
        }

        $self->{_format_key_to_idx}{$field} = 0;
        return 0;
    }
    else {
        my $idx = scalar @{$self->{_format}};
        push @{$self->{_format}}, $field;
        $self->{_format_key_to_idx}{$field} = $idx;
        return $idx;
    }
}

sub format {
    my $self = shift;
    return @{$self->{_format}};
}

# Returns a hash of format field names to their indices in per-sample
# lists.
sub format_field_index {
    my ($self, $key) = @_;
    if (!exists $self->{_format_key_to_idx}) {
        my @format = @{$self->{_format}};
        return unless @format;

        my %h;
        @h{@format} = 0..$#format;
        $self->{_format_key_to_idx} = \%h;
    }

    return $self->{_format_key_to_idx}{$key} if $key;
    return $self->{_format_key_to_idx};
}

sub sample_data {
    my $self = shift;
    if (!exists $self->{_sample_data}) {
        $self->{_sample_data} = $self->_parse_samples;
    }
    return $self->{_sample_data};
}

sub sample_field {
    my ($self, $sample_idx, $field_name) = @_;
    my $n_samples = scalar $self->{header}->sample_names;
    confess "Invalid sample index $sample_idx (have $n_samples samples): "
        unless ($sample_idx >= 0 && $sample_idx <= $n_samples);

    my $sample_data = $self->sample_data;
    return unless $sample_idx <= $#$sample_data;

    my $cache = $self->format_field_index;
    return unless exists $cache->{$field_name};
    my $field_idx = $cache->{$field_name};
    return $sample_data->[$sample_idx]->[$field_idx];
}

sub _extend_sample_data {
    my ($self, $idx) = @_;

    my $sample_data = $self->sample_data;
    return if $idx <= $#$sample_data;

    # We might have some undefined entries between here and the target sample
    # index. We should fill those with . (or ./. for GT).
    my $n_fields = scalar @{$self->{_format}};

    my @empty_data = (undef) x $n_fields;
    for my $i ($#$sample_data+1..$idx) {
        push @$sample_data, [@empty_data];
    }
}

sub set_sample_field {
    my ($self, $sample_idx, $field_name, $value) = @_;

    my $sample_data = $self->sample_data;
    my $n_samples = scalar $self->{header}->sample_names;
    confess "Invalid sample index $sample_idx (have $n_samples samples): "
        unless ($sample_idx >= 0 && $sample_idx <= $n_samples);

    my $cache = $self->format_field_index;
    if (!exists $cache->{$field_name}) {
        confess "Unknown format field $field_name";
    }

    $self->_extend_sample_data($sample_idx);
    my $field_idx = $cache->{$field_name};
    $sample_data->[$sample_idx]->[$field_idx] = $value;
}

sub to_string {
    my ($self) = @_;

    my %info = %{$self->info};
    my %info_keys = map {$_ => undef} keys %info;

    my @info_order;
    for my $info_key (@{$self->{info_fields}{order}}) {
        push(@info_order, $info_key) if exists $info{$info_key};
        delete $info_keys{$info_key};
    }

    push(@info_order, keys %info_keys);

    # We want to display ./. when the GT format field is undefined,
    # but . otherwise. To this end, we build an array containing the
    # proper string to represent undef for each info field present.
    my @format_undef = ('.') x scalar @{$self->{_format}};
    my $gtidx = $self->format_field_index("GT");
    if (defined $gtidx) {
        $format_undef[$gtidx] = './.';
    }

    return join("\t",
        $self->{chrom},
        $self->{position},
        join(",", @{$self->{identifiers}}) || '.',

        $self->{reference_allele} || '.',
        join(",", @{$self->{alternate_alleles}}) || '.',
        $self->{quality} || '.',
        join(";", @{$self->{_filter}}) || '.',
        join(";",
            map {
                defined $info{$_} ?
                    join("=", $_, $info{$_})
                    : $_
            } @info_order) || '.',
        join(":", @{$self->{_format}}) || '.',
        map {
            # Join values for an individual sample
            my $values = $_;
            join(":", map {
                defined $values->[$_] ? $values->[$_] : $format_undef[$_]
                } 0..$#$values) || '.'
            } @{$self->sample_data}, # for each sample
        );
}

1;
