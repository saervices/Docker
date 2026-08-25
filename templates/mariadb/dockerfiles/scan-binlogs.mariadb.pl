#!/usr/bin/perl
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
use strict;
use warnings;

use Fcntl qw(F_SETFD FD_CLOEXEC O_DIRECTORY O_NOFOLLOW O_NONBLOCK O_RDONLY S_ISDIR S_ISREG);

my $DATA_ROOT = '/var/lib/mysql';
my @SECRET_PATHS = (
    '/run/secrets/MARIADB_PASSWORD',
    '/run/secrets/MARIADB_ROOT_PASSWORD',
);
my $MAX_SECRET_BYTES = 4096;
my $MAX_BINLOG_FILES = 512;
my $MAX_BINLOG_BYTES = 1_100_000_000;
my $MAX_TOTAL_BINLOG_BYTES = 68_719_476_736;
my $READ_CHUNK_BYTES = 1_048_576;

sub fatal {
    my ($message) = @_;
    print STDERR "[FATAL] MariaDB startup blocked because $message.\n";
    exit 78;
}

sub stable_identity {
    my (@stat) = @_;
    return join(':', @stat[0, 1, 2, 3, 7, 9, 10]);
}

sub mark_close_on_exec {
    my ($handle, $description) = @_;
    my $result = fcntl($handle, F_SETFD, FD_CLOEXEC);
    fatal("$description cannot be marked close-on-exec") unless defined($result);
}

sub read_secret {
    my ($path) = @_;
    my @before = lstat($path);
    fatal('a required database secret is missing or unsafe')
        unless @before && S_ISREG($before[2]) && $before[3] == 1
        && $before[7] > 0 && $before[7] <= $MAX_SECRET_BYTES;

    sysopen(my $handle, $path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        or fatal('a required database secret cannot be opened safely');
    mark_close_on_exec($handle, 'a required database secret');
    my @opened = stat($handle);
    fatal('a required database secret changed while it was opened')
        unless @opened && stable_identity(@before) eq stable_identity(@opened);

    my $value = '';
    while (1) {
        my $chunk = '';
        my $read = sysread($handle, $chunk, $MAX_SECRET_BYTES + 1 - length($value));
        if (!defined($read)) {
            next if $!{'EINTR'};
            fatal('a required database secret cannot be read safely');
        }
        last if $read == 0;
        $value .= $chunk;
        fatal('a required database secret exceeds the bounded size')
            if length($value) > $MAX_SECRET_BYTES;
    }

    my @after = stat($handle);
    my @path_after = lstat($path);
    fatal('a required database secret changed while it was read')
        unless @after && @path_after
        && stable_identity(@opened) eq stable_identity(@after)
        && stable_identity(@opened) eq stable_identity(@path_after)
        && length($value) == $opened[7];
    close($handle) or fatal('a required database secret cannot be closed safely');
    fatal('a required database secret contains unsupported control bytes')
        if $value =~ /[\x00-\x1f\x7f]/;
    fatal('a required database secret is still a placeholder')
        if $value eq 'CHANGE_ME';
    return $value;
}

sub scan_binlog {
    my ($directory_fd, $name, $secrets_ref, $maximum_overlap) = @_;
    my $path = "/proc/self/fd/$directory_fd/$name";
    my @before = lstat($path);
    fatal('a binary-log candidate is not a single-link regular file')
        unless @before && S_ISREG($before[2]) && $before[3] == 1;
    fatal('a binary-log candidate exceeds the per-file audit bound')
        if $before[7] > $MAX_BINLOG_BYTES;

    sysopen(my $handle, $path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        or fatal('a binary-log candidate cannot be opened safely');
    mark_close_on_exec($handle, 'a binary-log candidate');
    my @opened = stat($handle);
    fatal('a binary-log candidate changed while it was opened')
        unless @opened && stable_identity(@before) eq stable_identity(@opened);

    my $bytes_read = 0;
    my $carry = '';
    while (1) {
        my $chunk = '';
        my $read = sysread($handle, $chunk, $READ_CHUNK_BYTES);
        if (!defined($read)) {
            next if $!{'EINTR'};
            fatal('a binary-log candidate cannot be read safely');
        }
        last if $read == 0;
        $bytes_read += $read;
        fatal('a binary-log candidate grew beyond its reviewed size')
            if $bytes_read > $opened[7];
        my $window = $carry . $chunk;
        for my $secret (@{$secrets_ref}) {
            fatal('an active binary log contains a current database secret')
                if index($window, $secret) >= 0;
        }
        if ($maximum_overlap > 0) {
            my $keep = length($window) < $maximum_overlap
                ? length($window)
                : $maximum_overlap;
            $carry = substr($window, length($window) - $keep, $keep);
        } else {
            $carry = '';
        }
    }

    my @after = stat($handle);
    my @path_after = lstat($path);
    fatal('a binary-log candidate changed while it was scanned')
        unless @after && @path_after
        && stable_identity(@opened) eq stable_identity(@after)
        && stable_identity(@opened) eq stable_identity(@path_after)
        && $bytes_read == $opened[7];
    close($handle) or fatal('a binary-log candidate cannot be closed safely');
    return $bytes_read;
}

my @secrets = map { read_secret($_) } @SECRET_PATHS;
my $maximum_secret_bytes = 0;
for my $secret (@secrets) {
    $maximum_secret_bytes = length($secret)
        if length($secret) > $maximum_secret_bytes;
}
my $maximum_overlap = $maximum_secret_bytes > 0 ? $maximum_secret_bytes - 1 : 0;

sysopen(my $data_root_handle, $DATA_ROOT,
    O_RDONLY | O_NOFOLLOW | O_DIRECTORY)
    or fatal('the canonical database root cannot be opened safely');
mark_close_on_exec($data_root_handle, 'the canonical database root');
my @data_root_before = stat($data_root_handle);
fatal('the canonical database root is not a directory')
    unless @data_root_before && S_ISDIR($data_root_before[2]);
my $data_root_fd = fileno($data_root_handle);
opendir(my $inventory_handle, "/proc/self/fd/$data_root_fd")
    or fatal('the binary-log inventory cannot be opened safely');

my @binlogs = ();
while (defined(my $name = readdir($inventory_handle))) {
    next unless $name =~ /\Abinlog\.[0-9]/;
    fatal('an unexpected binary-log candidate name was found')
        unless $name =~ /\Abinlog\.[0-9]+(?:\.idx)?\z/;
    push @binlogs, $name;
    fatal('the binary-log inventory exceeds the reviewed file-count bound')
        if @binlogs > $MAX_BINLOG_FILES;
}
closedir($inventory_handle) or fatal('the binary-log inventory cannot be closed safely');

my $total_bytes = 0;
for my $name (sort @binlogs) {
    $total_bytes += scan_binlog($data_root_fd, $name, \@secrets, $maximum_overlap);
    fatal('the binary-log inventory exceeds the reviewed total-size bound')
        if $total_bytes > $MAX_TOTAL_BINLOG_BYTES;
}

my @data_root_after = stat($data_root_handle);
fatal('the database root changed during the binary-log inventory')
    unless @data_root_after
    && stable_identity(@data_root_before) eq stable_identity(@data_root_after);
close($data_root_handle) or fatal('the canonical database root cannot be closed safely');

exit 0;
