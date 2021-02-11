#!/bin/bash
set -euo pipefail

# Remove exec from original entrypoint so we can continue here
sed -i -e 's/exec/\# exec/g' /usr/local/bin/docker-entrypoint.sh

# Normal setup
/bin/bash /usr/local/bin/docker-entrypoint.sh "$1"

# Generate vars for wp-config.php injection
echo "Generating PHP Defines from ENV..."
DEFINES=$(awk -v pat="$CONFIG_VAR_FLAG" 'END {
  print "// Generated by docker-entrypoint.sh:";

  for (name in ENVIRON) {
    if ( name ~ pat ) {
      print "define(\"" substr(name, length(pat)+1) "\", \"" ENVIRON[name] "\");"
    }
  }

  print " "
}' < /dev/null)
echo "$DEFINES"
echo "Debug"
echo "Adding Defines to wp-config.php..."

# Remove previously-injected vars
sed '/\/\/ENTRYPOINT_START/,/\/\/ENTRYPOINT_END/d' wp-config.php > wp-config.tmp

# Add current vars
awk '/^\/\*.*stop editing.*\*\/$/ && c == 0 { c = 1; system("cat") } { print }' wp-config.tmp > wp-config.php <<EOF
//ENTRYPOINT_START

$DEFINES

if (isset(\$_SERVER['HTTP_X_FORWARDED_PROTO']) && \$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
  \$_SERVER['HTTPS'] = 'on';
}

//ENTRYPOINT_END

EOF

rm wp-config.tmp

# First-run configuration
if [ ! -f /var/www/firstrun ]; then
  echo "Executing first-run setup..."

  # Install $WP_PLUGINS
  echo "Installing WordPress Plugins: $WP_PLUGINS"

  for PLUGIN in $WP_PLUGINS; do
    echo "## Installing $PLUGIN"
    if [ ! -e "wp-content/plugins/$PLUGIN" ]; then
      if ( wget "https://downloads.wordpress.org/plugin/$PLUGIN.zip" ); then
        unzip "$PLUGIN.zip" -q -d /var/www/html/wp-content/plugins/
        rm "$PLUGIN.zip"
      else
        echo "## WARN: wget failed for https://downloads.wordpress.org/plugin/$PLUGIN.zip"
      fi
    else
      echo "### $PLUGIN already installed, skipping."
    fi
  done

  CRON_CMD="${CRON_CMD:-}"
  if [ -n "$CRON_CMD" ]; then
    echo "Installing Cron command: $CRON_CMD"

    #write out current crontab
    crontab -l > /tmp/mycron
    echo "$CRON_CMD" >> /tmp/mycron

    #install new cron file
    crontab /tmp/mycron
    echo "Cron CMD installed."

    rm /tmp/mycron
  fi

  # Print firstrun date/time to file
  date > /var/www/firstrun
else
  echo "First run already completed, skipping configuration."
fi

# Set up Nginx Helper log directory
mkdir -p wp-content/uploads/nginx-helper

# Set usergroup for all modified files
chown -R www-data:www-data /var/www/html/

if [ "$ENABLE_CRON" == "true" ]; then
  echo "Starting Cron daemon..."

  if pgrep -x "crond" > /dev/null; then
      echo "Running"
  else
      /usr/sbin/crond
  fi
fi

exec "$@"