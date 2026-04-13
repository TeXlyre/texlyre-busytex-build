#!/usr/bin/env perl
use strict;
use warnings;

my ($texmf_root, $repo) = @ARGV;
die "Usage: $0 <texmf-root> <repo>\n" unless $texmf_root && $repo;

unshift @INC, "$repo/tlpkg";
require TeXLive::TLPDB;
require TeXLive::TLPOBJ;
require TeXLive::TLUtils;

my $tlpobj_dir = "$texmf_root/tlpkg/tlpobj";
my $tlpdb_file = "$texmf_root/tlpkg/texlive.tlpdb";

die "Cannot find tlpobj dir: $tlpobj_dir\n" unless -d $tlpobj_dir;

open my $fh, '>', $tlpdb_file or die "Cannot write $tlpdb_file: $!";
opendir my $dh, $tlpobj_dir or die "Cannot open $tlpobj_dir: $!";
while (my $f = readdir $dh) {
    next unless $f =~ /\.tlpobj$/;
    open my $in, '<', "$tlpobj_dir/$f" or next;
    print $fh $_ while <$in>;
    print $fh "\n";
    close $in;
}
closedir $dh;
close $fh;

my $db = TeXLive::TLPDB->new(root => $texmf_root);
die "Failed to load TLPDB\n" unless $db;

my $dat     = "$texmf_root/texmf-dist/texmf-var/tex/generic/config/language.dat";
my $dat_lua = "$texmf_root/texmf-dist/texmf-var/tex/generic/config/language.dat.lua";
my $def     = "$texmf_root/texmf-dist/texmf-var/tex/generic/config/language.def";

TeXLive::TLUtils::create_language_dat($db, $dat, undef);
TeXLive::TLUtils::create_language_def($db, $def, undef);
TeXLive::TLUtils::create_language_lua($db, $dat_lua, undef);

unlink $tlpdb_file;

print "Generated $dat\n";
print "Generated $dat_lua\n";
print "Generated $def\n";