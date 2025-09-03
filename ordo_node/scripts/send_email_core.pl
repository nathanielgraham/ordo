use strict;
use warnings;
use Net::SMTP;

# Email configuration
my $smtp_server = 'smtp.gmail.com';
my $smtp_port = 587; # Use 465 for SSL, 587 for TLS
my $username = 'your_email@gmail.com'; # Replace with your email
my $password = 'your_app_password'; # Replace with your app-specific password
my $from = 'your_email@gmail.com';
my $to = 'recipient@example.com';
my $subject = 'Test Email from Perl';
my $body = 'This is a test email sent from a Perl script using core modules.';

# Create the email message
my $message = << "END_MESSAGE";
From: $from
To: $to
Subject: $subject
Content-Type: text/plain; charset=UTF-8

$body
END_MESSAGE

# Send the email
eval {
    my $smtp = Net::SMTP->new(
        $smtp_server,
        Port    => $smtp_port,
        SSL     => 0, # Set to 1 for SSL (port 465)
        Timeout => 30,
        Debug   => 0, # Set to 1 for debugging output
    ) or die "Could not connect to SMTP server: $!";

    # Start TLS if using port 587
    if ($smtp_port == 587) {
        $smtp->starttls() or die "Could not start TLS: $!";
    }

    # Authenticate
    $smtp->auth($username, $password) or die "Authentication failed: $!";

    # Send the email
    $smtp->mail($from);
    $smtp->to($to);
    $smtp->data();
    $smtp->datasend($message);
    $smtp->dataend();
    $smtp->quit();

    print "Email sent successfully!\n";
};
if ($@) {
    warn "Failed to send email: $@";
}
