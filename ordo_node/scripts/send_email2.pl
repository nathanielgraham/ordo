#!/usr/bin/perl
use strict;
use warnings;
use Email::Sender::Simple qw(sendmail);
use Email::Sender::Transport::SMTP;
use Email::Simple;
use Email::Simple::Creator;

# Define email parameters
my $to      = 'recipient@example.com';
my $from    = 'sender@example.com';
my $subject = 'Test Email from Perl';
my $body    = 'This is a test email sent from a Perl script.';

# Create the email
my $email = Email::Simple->create(
    header => [
        To      => $to,
        From    => $from,
        Subject => $subject,
    ],
    body => $body,
);

# Set up the SMTP transport
my $transport = Email::Sender::Transport::SMTP->new(
    host => 'smtp.example.com',  # Replace with your SMTP server
    port => 587,                  # Common SMTP port
    sasl_username => 'your_username',  # Your SMTP username
    sasl_password => 'your_password',  # Your SMTP password
    ssl => 1,                     # Use SSL if required
);

# Send the email
sendmail($email, { transport => $transport });

print "Email sent successfully!\n";

