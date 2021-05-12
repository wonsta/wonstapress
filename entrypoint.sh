#!/bin/bash

# terminate on errors
set -e

echo 'About to change directories'

# Remove lost+found directory
if [ -d /var/www/wp-content/lost+found ]; then
    echo 'Removing dir'
    rmdir /var/www/wp-content/lost+found 2>/dev/null
fi

# Check if volume is empty
if [ ! "$(ls -A "/var/www/wp-content" 2>/dev/null)" ]; then
    echo 'Setting up wp-content volume'
    # Copy wp-content from Wordpress src to volume
    cp -a /usr/src/wordpress/wp-content/. /var/www/wp-content/
    chown -R nobody.nobody /var/www

    # Generate secrets
    curl -f https://api.wordpress.org/secret-key/1.1/salt/ >> /usr/src/wordpress/wp-secrets.php
fi

echo 'Set up database'
# Setup database
wp --path=/usr/src/wordpress core install \
    --url=$WORDPRESS_URL \
    --admin_user=$WORDPRESS_USER \
    --admin_password=$WORDPRESS_PASSWORD \
    --admin_email=$WORDPRESS_EMAIL \
    --title=$WORDPRESS_TITLE \
    --skip-plugins

echo 'Set up blog description'
# Setup blog description
wp --path=/usr/src/wordpress option update blogdescription $WORDPRESS_DESCRIPTION

echo 'Set up adminuser on first load'
# Setup admin user
wp --path=/usr/src/wordpress user create \
    $WORDPRESS_USERNAME $WORDPRESS_EMAIL \
    --user_pass=$WORDPRESS_PASSWORD \
    --role=administrator \
    --send-email

echo 'Update WP'
# Update WordPress
wp --path=/usr/src/wordpress core update

# Update WordPress database
wp --path=/usr/src/wordpress core update-db

# Setup correct ownership
chown -R nginx.nginx /var/www/wp-content

exec "$@"
