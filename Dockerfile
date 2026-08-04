FROM perl:5.38-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl-dev \
    libsqlite3-dev \
    build-essential \
    pkg-config \
    libev-dev \
    openssh-client \
    sshpass \
    sqlite3 \
    postfix \
    gnupg \
    && rm -rf /var/lib/apt/lists/*

# Install Perl dependencies
RUN cpanm --notest \
    Mojolicious \
    Mojo::SQLite \
    Net::OpenSSH \
    EV \
    Cron::Toolkit \
    UUID::Tiny \
    Email::Valid \
    Mojo::JWT \
    Email::MIME \
    Email::Sender::Simple \
    Minion \
    Minion::Backend::SQLite \
    JSON \
    Digest::SHA \
    DateTime \
    MIME::Base64 \
    IO::Socket::INET \
    Encode \
    Mojolicious::Plugin::JSONConfig \
    IO::Pty \
    Crypt::JWT \
    Email::Sender \
    Authen::SASL 

# App dirs + non-root user
RUN useradd --create-home --shell /bin/bash --uid 1000 ordo \
 && mkdir -p /app/config /app/data /app/db /app/schemas /app/config.default \
             /home/ordo/.ssh \
 && chown -R ordo:ordo /home/ordo

# Copy application code
COPY lib/ /app/lib/
COPY script/ /app/script/
COPY public/ /app/public/
COPY templates/ /app/templates/
COPY ordo_node/ /app/ordo_node/
COPY schemas/*.schema /app/schemas/
COPY config/ordo.json /app/config.default/ordo.json

# Entrypoint
COPY script/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
 && chown -R ordo:ordo /app

ENV HOME=/home/ordo

USER ordo

EXPOSE 3000

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["perl", "script/ordo", "prefork", "-w", "1", "-l", "http://*:3000"]
