#!/usr/bin/perl
use strict;
use warnings;
use LWP::Simple;
use File::Spec;

# Detect operating system
my $is_windows = ($^O =~ /MSWin32/i);

# Configuration
my $home_dir = $ENV{HOME} || $ENV{USERPROFILE} || die "Cannot determine home directory\n";
my $locallib_dir = File::Spec->catdir($home_dir, 'perl5');
my $bin_dir = File::Spec->catdir($home_dir, 'bin');
my $cpanm_url = "https://cpanmin.us";
my $cpanm_path = File::Spec->catfile($bin_dir, 'cpanm');

# Ensure perl is available
system("perl -v") == 0 or die "perl is required but not found\n";

# Create necessary directories
unless (-d $bin_dir) {
    mkdir $bin_dir or die "Cannot create $bin_dir: $!\n";
}
unless (-d $locallib_dir) {
    mkdir $locallib_dir or die "Cannot create $locallib_dir: $!\n";
}

# Download cpanm using LWP::Simple
print "Downloading cpanm...\n";
my $content = get($cpanm_url) or die "Failed to download cpanm\n";
open my $fh, '>', $cpanm_path or die "Cannot write to $cpanm_path: $!\n";
print $fh $content;
close $fh;

# Make cpanm executable (skip on Windows)
unless ($is_windows) {
    chmod 0755, $cpanm_path or die "Cannot chmod cpanm: $!\n";
}

# Install local::lib
print "Installing local::lib...\n";
system("$^X $cpanm_path --notest --local-lib=$locallib_dir local::lib") == 0 or die "Failed to install local::lib\n";

# Install platform-specific process module
my $process_module = $is_windows ? 'Win32::Process::List' : 'Proc::ProcessTable';
print "Installing $process_module...\n";
system("$^X $cpanm_path --notest --local-lib=$locallib_dir $process_module") == 0 or die "Failed to install $process_module\n";

# Set up environment variables
print "Configuring environment...\n";
my $perl5lib = File::Spec->catdir($locallib_dir, 'lib', 'perl5');
my $path_sep = $is_windows ? ';' : ':';
my $env_setup;

if ($is_windows) {
    $perl5lib =~ s/\\/\\\\/g; # Escape backslashes for PowerShell
    $bin_dir =~ s/\\/\\\\/g;
    $locallib_dir =~ s/\\/\\\\/g;
    $env_setup = << "END";
# Added for local::lib
\$Env:PERL5LIB = "$perl5lib" + "$path_sep" + \$Env:PERL5LIB
\$Env:PERL_LOCAL_LIB_ROOT = "$locallib_dir" + "$path_sep" + \$Env:PERL_LOCAL_LIB_ROOT
\$Env:PERL_MM_OPT = "INSTALL_BASE=$locallib_dir"
\$Env:PERL_MB_OPT = "--install_base=$locallib_dir"
\$Env:PATH = "$bin_dir" + "$path_sep" + \$Env:PATH
END
} else {
    $env_setup = << 'END';
# Added for local::lib
export PERL5LIB="$perl5lib:$PERL5LIB"
export PERL_LOCAL_LIB_ROOT="$locallib_dir:$PERL_LOCAL_LIB_ROOT"
export PERL_MM_OPT="INSTALL_BASE=$locallib_dir"
export PERL_MB_OPT="--install_base=$locallib_dir"
export PATH="$bin_dir:$PATH"
END
}

# Determine shell configuration file
my $config_file;
if ($is_windows) {
    # PowerShell profile
    $config_file = File::Spec->catfile($home_dir, 'Documents', 'WindowsPowerShell', 'profile.ps1');
    # Create parent directory if it doesn't exist
    my $ps_dir = File::Spec->catdir($home_dir, 'Documents', 'WindowsPowerShell');
    mkdir $ps_dir unless -d $ps_dir;
} else {
    $config_file = File::Spec->catfile($home_dir, '.bashrc');
}

# Append to configuration file
open my $fh_config, '>>', $config_file or die "Cannot open $config_file: $!\n";
print $fh_config "\n$env_setup";
close $fh_config;

print "local::lib and $process_module installed successfully!\n";
if ($is_windows) {
    print "Please run '. \$PROFILE' in PowerShell to update your environment.\n";
} else {
    print "Please run 'source ~/.bashrc' to update your environment.\n";
}
