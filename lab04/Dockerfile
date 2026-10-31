FROM jenkins/ssh-agent

# install PHP-CLI, the PHP extensions that PHPUnit needs and Composer
RUN apt-get update \
    && apt-get install -y php-cli php-xml php-mbstring composer \
    && rm -rf /var/lib/apt/lists/*
