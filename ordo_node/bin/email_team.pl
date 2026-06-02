#!/usr/bin/perl
use warnings;
use strict;
use JSON::PP;

my $message = shift @ARGV || "No message provided by job";
my $subject = shift @ARGV || "Ordo Job Notification";

print STDOUT "Email Team Script Started\n";
print STDOUT "Message: $message\n";
print STDOUT "Subject: $subject\n\n";

# Get and parse team emails
my @emails;

if ($ENV{ORDO_TEAM}) {
    print STDOUT "ORDO_TEAM found: $ENV{ORDO_TEAM}\n";
    
    eval {
        my $team_data = decode_json($ENV{ORDO_TEAM});
        
        if (ref($team_data) eq 'ARRAY') {
            foreach my $member (@$team_data) {
                if ($member && $member->{email}) {
                    push @emails, $member->{email};
                }
            }
        }
    };
    
    if ($@) {
        print STDERR "Warning: Failed to parse ORDO_TEAM JSON: $@\n";
        print STDERR "Raw ORDO_TEAM: $ENV{ORDO_TEAM}\n";
    }
}

# Fallback: add the job owner's email
if ($ENV{ORDO_EMAIL}) {
    push @emails, $ENV{ORDO_EMAIL};
}

# Remove duplicates
my %seen;
@emails = grep { !$seen{$_}++ } @emails;

if (!@emails) {
    print STDERR "Error: No email recipients found.\n";
    exit 1;
}

print STDOUT "Sending to: " . join(", ", @emails) . "\n";

my $recipients = join(" ", @emails);

# Send email using system mail command
my $cmd = qq{echo "$message" | mail -s "$subject" $recipients};

system($cmd);

if ($? == 0) {
    print STDOUT "Email sent successfully to @emails\n";
    exit 0;
} else {
    print STDERR "Failed to send email (exit code: $?)\n";
    exit 1;
}
