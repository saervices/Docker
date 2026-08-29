#!/usr/bin/env perl
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

use strict;
use warnings;
use Encode qw(decode FB_CROAK);
use Fcntl qw(O_RDONLY O_NONBLOCK O_NOFOLLOW SEEK_SET S_ISREG F_GETFD F_SETFD FD_CLOEXEC);
use Time::HiRes qw(stat lstat);

sub fail {
    my ($message) = @_;
    print STDERR "[espocrm] ERROR: $message\n";
    exit 1;
}

@ARGV == 2 or fail('Secret reader requires one path and one minimum byte length.');
my ($path, $minimum_size) = @ARGV;

$path =~ m{^/[^\x00\r\n]{0,4095}$}
    or fail('Secret path must be an absolute bounded path.');
$minimum_size =~ /\A[1-9][0-9]{0,3}\z/ && $minimum_size <= 4096
    or fail('Secret minimum byte length is invalid.');

my @before_path = lstat($path);
@before_path or fail('Required secret is missing or cannot be inspected.');
S_ISREG($before_path[2]) or fail('Required secret is not a regular file.');
$before_path[3] == 1 or fail('Required secret must have exactly one hard link.');

sysopen(my $secret, $path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
    or fail('Required secret cannot be opened safely.');
my $descriptor_flags = fcntl($secret, F_GETFD, 0);
defined($descriptor_flags) or fail('Required secret descriptor flags cannot be inspected.');
fcntl($secret, F_SETFD, $descriptor_flags | FD_CLOEXEC)
    or fail('Required secret descriptor cannot be protected across exec.');
my @before_fd = stat($secret);
@before_fd or fail('Required secret descriptor cannot be inspected.');
S_ISREG($before_fd[2]) or fail('Required secret descriptor is not regular.');
$before_fd[3] == 1 or fail('Required secret descriptor has an unsafe link count.');
($before_path[0] == $before_fd[0] && $before_path[1] == $before_fd[1])
    or fail('Required secret changed while it was opened.');

sub read_bounded {
    my ($handle) = @_;
    my $value = '';

    while (length($value) <= 4096) {
        my $remaining = 4097 - length($value);
        my $count = sysread($handle, my $chunk, $remaining);
        defined($count) or fail('Required secret could not be read.');
        last if $count == 0;
        $value .= $chunk;
    }

    return $value;
}

my $value = read_bounded($secret);
my @after_fd = stat($secret);
@after_fd or fail('Required secret descriptor changed while reading.');
my @after_path = lstat($path);
@after_path or fail('Required secret path disappeared while reading.');

for my $index (0, 1, 2, 3, 4, 5, 7, 9, 10) {
    $before_fd[$index] == $after_fd[$index]
        or fail('Required secret metadata changed while reading.');
    $before_path[$index] == $after_path[$index]
        or fail('Required secret path metadata changed while reading.');
}
($after_path[0] == $after_fd[0] && $after_path[1] == $after_fd[1])
    or fail('Required secret path changed while reading.');

my $seek_result = sysseek($secret, 0, SEEK_SET);
defined($seek_result) && $seek_result == 0
    or fail('Required secret cannot be re-read safely.');
my $confirmation = read_bounded($secret);
$confirmation eq $value or fail('Required secret changed while reading.');
close($secret) or fail('Required secret descriptor could not be closed.');

my $length = length($value);
($length >= $minimum_size && $length <= 4096)
    or fail('Required secret has an invalid length.');
$value ne 'CHANGE_ME' or fail('Required secret still contains the placeholder value.');

my $encoded_value = $value;
my $decoded = eval { decode('UTF-8', $encoded_value, FB_CROAK) };
defined($decoded) or fail('Required secret is not valid UTF-8.');
$decoded !~ /[^\x20-\x7e]/
    or fail('Required secret contains non-printable or non-ASCII characters.');

binmode(STDOUT, ':raw') or fail('Secret output stream cannot be prepared.');
print STDOUT $value or fail('Required secret could not be emitted.');
