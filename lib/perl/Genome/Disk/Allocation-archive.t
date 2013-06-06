#!/usr/bin/env genome-perl

BEGIN { 
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above "Genome";
use Test::More;
use File::Temp 'tempdir';
use File::Basename;
use File::Find;
use Filesys::Df qw();

use_ok('Genome::Disk::Allocation') or die;
use_ok('Genome::Disk::Volume') or die;

use Genome::Disk::Allocation;
#$Genome::Disk::Allocation::TESTING_DISK_ALLOCATION = 1;

my @volumes = create_test_volumes();

# Make test allocation
my $allocation = Genome::Disk::Allocation->create(
    disk_group_name => $volumes[0]->disk_group_names,
    allocation_path => 'testing123',
    owner_class_name => 'UR::Value',
    owner_id => 'foo',
    kilobytes_requested => 1,
);
ok($allocation, 'created test allocation on non-archive disk');
is($allocation->mount_path, $volumes[0]->mount_path, 'allocation on expected volume');

my $original_absolute_path = $allocation->absolute_path;

# Make a few testing files in the allocation directory
my @files = qw( a.out b.out c.out .hidden.out test/d.out test/.hidden.out);
my @dirs = qw/ test /;
for my $dir (@dirs) {
    my $path = $allocation->absolute_path . "/$dir";
    system("mkdir $path");
    ok(-d $path, "created test dir $path");
}
for my $file (@files) {
    my $path = $allocation->absolute_path . "/$file";
    system("touch $path");
    ok(-e $path, "created test file $path");
}

# Before archiving, set the owner_class_name to a class that doesn't exist to make
# sure this is handled without fault, since some allocations exist in this kind of state.
$allocation->owner_class_name('Foo::Bar');
my $rv = $allocation->archive();
ok($rv, 'archive successfully executed');

is($allocation->mount_path, $volumes[1]->mount_path, 'allocation moved to archive volume');

my $tar_path = $allocation->tar_path;
my $output = `tar -tf $tar_path`;
my @tar_files = map { chomp $_; s/\/$//; basename($_) } split("\n", $output);
my $total_tar_files = scalar @tar_files;
my $total_expected_files = (scalar @files) + (scalar @dirs);
is($total_tar_files, $total_expected_files, 'found expected number of files/dirs in tarball');
for my $file (@files, @dirs) {
    ok((grep { $file =~ /$_/ } @tar_files), "found $file in tarball");
}

# Remove the original files
Genome::Sys->remove_directory_tree($original_absolute_path);

# Now unarchive
$rv = $allocation->unarchive();
ok($rv, 'unarchive successfully executed');
is($allocation->mount_path, $volumes[0]->mount_path, 'allocation moved back to expected active volume');

my @allocation_files;
sub wanted {
    return if $File::Find::name eq $allocation->absolute_path;
    push @allocation_files, $File::Find::name;
}
find(\&wanted, $allocation->absolute_path);

is((scalar @allocation_files), ((scalar @files) + (scalar @dirs)), 'expected number of files in allocation directory');
for my $file (@allocation_files) {
    my $filename = basename($file);
    ok((grep { $_ =~ /$filename/ } (@files, @dirs)), "found $file in allocation directory");
}

done_testing();

sub create_test_volumes {
    my $test_dir = tempdir(
        'allocation_testing_XXXXXX',
        TMPDIR => 1,
        UNLINK => 1,
        CLEANUP => 1,
    );

    $Genome::Disk::Allocation::CREATE_DUMMY_VOLUMES_FOR_TESTING = 0;
    no warnings 'redefine';
    *Genome::Sys::current_user_is_admin = sub { return 1 };
    use warnings;

    # Make two dummy volumes, one to create allocation on and one to archive it to
    my @volumes;
    for (1..2) {
        my $volume_path = tempdir(
            "test_volume_" . $_ . "_XXXXXXX",
            DIR => $test_dir,
            CLEANUP => 1,
            UNLINK => 1,
        );
        my $volume = Genome::Disk::Volume->create(
            id => $_,
            hostname => 'foo',
            physical_path => 'foo/bar',
            mount_path => $volume_path,
            total_kb => Filesys::Df::df($volume_path)->{blocks},
            disk_status => 'active',
            can_allocate => '1',
        );
        ok($volume, 'made testing volume') or die;
        push @volumes, $volume;
    }

    # Make dummy groups
    my $group = Genome::Disk::Group->create(
        disk_group_name => 'testing_group',
        permissions => '755',
        setgid => '1',
        subdirectory => 'testing',
        unix_uid => 0,
        unix_gid => 0,
    );
    ok($group, 'successfully made testing group') or die;

    my $archive_group = Genome::Disk::Group->create(
        disk_group_name => 'archive',
        permissions => '755',
        setgid => '1',
        subdirectory => 'testing',
        unix_uid => 0,
        unix_gid => 0,
    );
    ok($archive_group, 'created archive group');
    push @Genome::Disk::Allocation::APIPE_DISK_GROUPS, $group->disk_group_name, $archive_group->disk_group_name;

    # Assign volumes to groups
    my $assignment = Genome::Disk::Assignment->create(
        dg_id => $group->id,
        dv_id => $volumes[0]->id,
    );
    ok($assignment, 'assigned one volume to testing group');
    system("mkdir -p " . join('/', $volumes[0]->mount_path, $volumes[0]->groups->subdirectory));

    my $archive_assignment = Genome::Disk::Assignment->create(
        dg_id => $archive_group->id,
        dv_id => $volumes[1]->id,
    );
    ok($archive_assignment, 'created one volume in archive group');
    system("mkdir -p " . join('/', $volumes[1]->mount_path, $volumes[1]->groups->subdirectory));

    # Redefine archive and active volume prefix, make sure this make is_archive return expected values
    no warnings 'redefine';
    *Genome::Disk::Volume::active_volume_prefix = sub { return $volumes[0]->mount_path };
    *Genome::Disk::Volume::archive_volume_prefix = sub { return $volumes[1]->mount_path };
    use warnings;
    is($volumes[0]->is_archive, 0, 'first volume is not archive');
    is($volumes[1]->is_archive, 1, 'second volume is archive');
    is($volumes[0]->archive_mount_path, $volumes[1]->mount_path, 'first volume correctly identifies its archive volume');

    return @volumes;
}
