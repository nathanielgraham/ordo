#!/usr/bin/env perl
use strict;
use warnings;
use Archive::Tar;
use File::Spec;
use File::Path qw(make_path);
use File::Copy;
use Cwd;

# Check for downloader (LWP::Simple preferred, curl as fallback)
my $downloader = 'none';
eval { require LWP::Simple; require HTTP::Status; 1; };
if (!$@) {
    $downloader = 'lwp';
} elsif (system('curl', '--version') == 0) {
    $downloader = 'curl';
} else {
    die "Error: Neither LWP::Simple nor curl is available. Install with: cpan LWP::Simple HTTP::Status\nor install curl (e.g., sudo apt-get install curl).\n";
}

# Check for Archive::Tar
eval { require Archive::Tar; };
if ($@) {
    die "Missing Archive::Tar. Install it with: cpan Archive::Tar\n";
}

# Configuration: Modules and their dependencies
my %modules = (
    'File::Which' => {
        version => '1.27',
        url => 'https://cpan.metacpan.org/authors/id/P/PL/PLICEASE/File-Which-1.27.tar.gz',
        pure_perl => 1,
    },
    'local::lib' => {
        version => '2.000029',
        url => 'https://cpan.metacpan.org/authors/id/H/HA/HAARG/local-lib-2.000029.tar.gz',
        pure_perl => 1,
    },
    'File::HomeDir' => {
        version => '1.006',
        url => 'https://cpan.metacpan.org/authors/id/R/RE/REHSACK/File-HomeDir-1.006.tar.gz',
        pure_perl => 1,
    },
    'Sys::Hostname' => {
        version => '1.24',
        url => 'https://cpan.metacpan.org/authors/id/D/DA/DAVECROSS/Sys-Hostname-1.24.tar.gz',
        pure_perl => 1,
    },
    'Proc::ProcessTable' => {
        version => '0.636',
        url => 'https://cpan.metacpan.org/authors/id/J/JW/JWB/Proc-ProcessTable-0.636.tar.gz',
        pure_perl => 0,  # Requires make and compiler
    },
);
my @install_order = qw(File::Which local::lib File::HomeDir Sys::Hostname Proc::ProcessTable);  # Dependencies first
my $install_dir = File::Spec->catdir($ENV{HOME}, 'perl5', 'lib', 'perl5');  # Linux: ~/perl5/lib/perl5
my $work_dir = File::Spec->catdir($ENV{HOME}, 'tmp_local_lib');  # Temporary working directory
my $rc_file = File::Spec->catfile($ENV{HOME}, '.bashrc');  # Shell configuration file
my @installed_modules;  # Track successfully installed modules

# Step 1: Ensure working directory exists
make_path($work_dir) unless -d $work_dir;
chdir $work_dir or die "Cannot change to $work_dir: $!\n";

# Step 2: Check if Sys::Hostname is in core
my $skip_sys_hostname = 0;
eval { require Sys::Hostname; 1; };
if (!$@) {
    print "Sys::Hostname is already available in core Perl, skipping installation.\n";
    $skip_sys_hostname = 1;
    push @installed_modules, 'Sys::Hostname';
}

# Step 3: Install each module in dependency order
foreach my $module (@install_order) {
    # Skip Sys::Hostname if in core
    next if $module eq 'Sys::Hostname' && $skip_sys_hostname;

    my $version = $modules{$module}{version};
    my $url = $modules{$module}{url};
    my $pure_perl = $modules{$module}{pure_perl};
    my $tarball = "$module-$version.tar.gz";
    $tarball =~ s/::/-/g;  # Replace :: with - for tarball name

    # Download the tarball
    print "Downloading $url for $module...\n";
    my $download_success = 0;
    if ($downloader eq 'lwp') {
        my $status = LWP::Simple::getstore($url, $tarball);
        if (HTTP::Status::is_success($status)) {
            $download_success = 1;
        } else {
            warn "Failed to download $tarball: HTTP status $status. Skipping $module.\n";
            next;
        }
    } else {
        if (system('curl', '-s', '-L', $url, '-o', $tarball) == 0) {
            $download_success = 1;
        } else {
            warn "Failed to download $tarball: $!. Skipping $module.\n";
            next;
        }
    }

    # Extract the tarball
    print "Extracting $tarball...\n";
    my $tar = Archive::Tar->new;
    $tar->read($tarball) or do {
        warn "Cannot read $tarball: $!. Skipping $module.\n";
        next;
    };
    $tar->extract or do {
        warn "Cannot extract $tarball: $!. Skipping $module.\n";
        next;
    };
    my $extracted_dir = "$module-$version";
    $extracted_dir =~ s/::/-/g;

    # Install module
    if ($pure_perl) {
        # Pure-Perl: Copy files manually
        print "Installing $module (pure-Perl) to $install_dir...\n";
        make_path($install_dir) unless -d $install_dir;
        my $module_dir = File::Spec->catdir($extracted_dir, 'lib');
        opendir my $dh, $module_dir or do {
            warn "Cannot open $module_dir: $!. Skipping $module.\n";
            next;
        };
        while (my $item = readdir $dh) {
            next if $item =~ /^\./;
            my $src = File::Spec->catfile($module_dir, $item);
            my $dest = File::Spec->catfile($install_dir, $item);
            if (-d $src) {
                copy_dir($src, $dest) or do {
                    warn "Cannot copy directory $src to $dest: $!. Skipping $module.\n";
                    next;
                };
            } else {
                copy($src, $dest) or do {
                    warn "Cannot copy $src to $dest: $!. Skipping $module.\n";
                    next;
                };
            }
            print "Copied $src to $dest\n";
        }
        closedir $dh;
    } else {
        # Non-pure-Perl: Requires make
        print "Checking for make to install $module...\n";
        if (system('make', '--version') != 0) {
            warn "Cannot install $module: 'make' is not available. Install with: sudo apt-get install build-essential\nand rerun.\n";
            next;
        }
        print "Installing $module (requires make) to $install_dir...\n";
        chdir $extracted_dir or do {
            warn "Cannot change to $extracted_dir: $!. Skipping $module.\n";
            next;
        };
        $ENV{PERL_MM_USE_DEFAULT} = 1;  # Suppress prompts
        system($^X, 'Makefile.PL', "INSTALL_BASE=$install_dir") == 0
            or do {
                warn "Failed to run Makefile.PL for $module: $!. Skipping $module.\n";
                chdir $work_dir;
                next;
            };
        system('make') == 0 or do {
            warn "Failed to build $module: $!. Skipping $module.\n";
            chdir $work_dir;
            next;
        };
        system('make', 'install') == 0 or do {
            warn "Failed to install $module: $!. Skipping $module.\n";
            chdir $work_dir;
            next;
        };
        chdir $work_dir or die "Cannot change back to $work_dir: $!\n";
    }

    # Verify module installation
    my $module_file = $module;
    $module_file =~ s/::/\//g;
    $module_file .= '.pm';
    my $module_path = File::Spec->catfile($install_dir, $module_file);
    if (-f $module_path) {
        print "Verified: $module_path exists\n";
        push @installed_modules, $module;  # Track successful installation
    } else {
        warn "Warning: $module_path not found after installation\n";
    }
}

# Step 4: Set up environment variables
print "Configuring environment variables in $rc_file...\n";
my $perl5lib = $install_dir;
my $perl_cmd = qq($^X -I$perl5lib -Mlocal::lib=$install_dir);
$perl_cmd = qq(eval "\$($perl_cmd)");
open my $fh, '>>', $rc_file or die "Cannot open $rc_file: $!\n";
my $rc_content = do { local $/; open my $f, '<', $rc_file; <$f> if -e $rc_file } || '';
unless ($rc_content =~ /\Q$perl_cmd\E/) {
    print $fh "$perl_cmd\n";
}
close $fh;

# Step 5: Verify installation of installed modules
print "Verifying installation...\n";
$ENV{PERL5LIB} = $perl5lib;  # Set PERL5LIB for verification
foreach my $module (@installed_modules) {
    my $cmd = qq($^X -I$perl5lib -M$module -e "print qq($module OK\\n)");
    system($cmd) == 0 or warn "Verification failed for $module: not found in \@INC. Check installation and source $rc_file (e.g., '. ~/.bashrc').\n";
}

print "Installation complete in $install_dir\n";
print "Source $rc_file to set environment variables (e.g., '. ~/.bashrc').\n";
print "If Proc::ProcessTable failed, install build-essential (sudo apt-get install build-essential) and rerun.\n";
print "If Sys::Hostname failed to download, it may be in core Perl. Verify with: perl -MSys::Hostname -e \"print qq(Sys::Hostname OK\\n)\"\n";

# Helper subroutine to copy directories recursively
sub copy_dir {
    my ($src, $dest) = @_;
    make_path($dest) unless -d $dest;
    opendir my $dh, $src or return;
    while (my $item = readdir $dh) {
        next if $item =~ /^\./;
        my $src_path = File::Spec->catfile($src, $item);
        my $dest_path = File::Spec->catfile($dest, $item);
        if (-d $src_path) {
            copy_dir($src_path, $dest_path);
        } else {
            copy($src_path, $dest_path) or return;
        }
    }
    closedir $dh;
    return 1;
}
