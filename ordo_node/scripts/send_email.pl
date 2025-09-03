use strict;
use warnings;
use Email::Sender::Simple qw(sendmail);
use Email::MIME;
use Try::Tiny;

# Email configuration
my $smtp_server = 'smtp.gmail.com';
my $smtp_port = 587; # Use 465 for SSL, 587 for TLS
my $username = 'your_email@gmail.com'; # Replace with your email
my $password = 'your_app_password'; # Replace with your app-specific password
my $from = 'your_email@gmail.com';
my $to = 'recipient@example.com';
my $subject = 'Test Email from Perl';
my $body = 'This is a test email sent from a Perl script.';

# Create the email
my $email = Email::MIME->create(
    header_str => [
        From    => $from,
        To      => $to,
        Subject => $subject,
    ],
    attributes => {
        encoding => 'quoted-printable',
        content_type => 'text/plain',
        charset  => 'UTF-8',
    },
    body => $body,
);

# Send the email
try {
    sendmail(
        $email,
        {
            transport => Email::Sender::Transport::SMTP->new({
                host => $smtp_server,
                port => $smtp_port,
                ssl  => 'starttls', # Use 'ssl' for port 465
                sasl_username => $username,
                sasl_password => $password,
            })
        }
    );
    print "Email sent successfully!\n";
} catch {
    warn "Failed to send email: $_";
};
