FROM perl:5.38-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    libssl-dev \
    libsqlite3-dev \
    build-essential \
    pkg-config \
    libev-dev \
    libnet-ssleay-perl \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

COPY . .

RUN cpanm Mojolicious Mojo::SQLite Net::OpenSSH EV Cron::Toolkit UUID::Tiny Email::Valid Mojo::JWT Email::MIME Email::Sender::Simple Minion JSON Digest::SHA DateTime MIME::Base64 IO::Socket::INET Encode Mojolicious::Plugin::JSONConfig Minion::Backend::SQLite IO::Pty Filter::Crypto

EXPOSE 3000

CMD ["perl", "script/ordo", "prefork", "-l", "http://*:3000"]
