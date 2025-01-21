#!/bin/bash

# BUILD SCRIPT FOR LOCAL WORDPRESS DEVELOPMENT
# Author: Josh Mckibbin
# Version: 1.0.0
# Date: 2025-01-21
#
# This script creates a new WordPress site in the ${DEV_PATH} directory:
# 	- Creates the necessary directory structure (e.g., ${DEV_PATH}/${SLUG}/wordpress)
#	- Downloads the latest version of WordPress
# 	- Creates the wp-config.php file
# 	- Creates the database as '${SLUG}'
# 	- Installs WordPress
# 	- Checks for an existing database dump (${SLUG}-dev.sql, ${SLUG}.sql, ${SLUG}-prod.sql) in ${DB_DUMP_DIR} and imports it if found
#	- Installs and activates the Simple SMTP Mailer plugin
#
# Requirements:
#	- Local linux development environment (WSL2 running Ubuntu in this case):
#		- Apache with mod_rewrite enabled
#		- PHP 8.2+ with the following modules: curl, dom, gd, json, mbstring, mysqli, openssl, xml, zip
#		- MariaDB 10.6+ with root access
#		- wp-cli: The script will attempt to install it if it's not found
#	- .env file in the same directory as this script with the necessary variables:
#		- DEV_PATH (e.g., /path/to/your/dev/directory)
#		- AVAILABLE_SITES_DIR (e.g., /path/to/your/apache/sites-available)
#		- ADMIN
#		- ADMIN_EMAIL
#		- ADMIN_PASS
#		- DB_ROOT_PASS
#		- DB_USER
#		- DB_PASS
#		- DB_DUMP_DIR The directory where the database dump files are stored
#		- SMTP_USER (optional) For the Simple SMTP Mailer plugin
#		- SMTP_PASS (optional) For the Simple SMTP Mailer plugin
#
# DO NOT RUN THIS SCRIPT IN A PRODUCTION ENVIRONMENT !!!

source .env

# Prompt for the site slug
read -p "Enter the site slug (Default: wordpress): " SLUG
if [ -z "${SLUG}" ]; then
	SLUG="wordpress"
else
	SLUG=$(echo ${SLUG} | tr '[:upper:]' '[:lower:]')
fi

# Prompt for the site title
read -p "Enter the site title (Default: ${SLUG^}): " TITLE
if [ -z "${TITLE}" ]; then
	TITLE=${SLUG^}
fi

# Set the local site domain
LOCAL_DOMAIN="${SLUG}.local"

# Check if WP-CLI is installed
if ! command -v wp &> /dev/null; then
	echo "WP-CLI is not installed. Attempting to install..."
	curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
	chmod +x wp-cli.phar
	sudo mv wp-cli.phar /usr/local/bin/wp

	if ! command -v wp &> /dev/null; then
		echo "WP-CLI could not be installed. Exiting..."
		exit 1
	fi
fi

INSTALL_DIR="${DEV_PATH}/${SLUG}/wordpress"

# Attempt to create the installation directory and if it fails, exit
echo -e "\nCreating the installation directory..."
mkdir -vp ${INSTALL_DIR} || echo "The installation directory could not be created. Exiting..." && exit 1

# Move to the web directory
cd ${INSTALL_DIR}

# Check if there is already a WordPress installation
if [ -f wp-config.php ]; then
	echo "WordPress is already installed in this directory. Exiting..."
	exit 1
else

# Download the latest version of WordPress
echo -e "\nDownloading WordPress..."
wp core download --skip-content

# Create the wp-config.php file
DB_PREFIX="wp_${SLUG}_"
SSMTP_MAILER=""
if [ -n "${SMTP_USER}" ] && [ -n "${SMTP_PASS}" ]; then
	SSMTP_MAILER=$(cat <<SSMTP
	// Local Development Overrides.
	if ( WP_ENVIRONMENT_TYPE === 'local' ) {
		define(
			'SSMTP_MAILER',
			array(
				'username' => '${SMTP_USER}',
				'password' => '${SMTP_PASS}',
			)
		);
	}
SSMTP
	)
fi

echo -e "\nCreating wp-config.php..."
wp config create --dbname=${SLUG} \
	--dbuser=${DB_USER} \
	--dbpass=${DB_PASS} \
	--dbprefix=${DB_PREFIX} \
	--extra-php <<PHP
define( 'AUTOMATIC_UPDATER_DISABLED', true );
define( 'WP_ENVIRONMENT_TYPE', 'local' );

if ( defined( 'WP_ENVIRONMENT_TYPE' ) ) {
	switch ( WP_ENVIRONMENT_TYPE ) {
		case 'local':
		case 'development':
			define( 'WP_DEBUG', true );
			define( 'WP_DEBUG_DISPLAY', true );
			define( 'WP_DEBUG_LOG', true );
			define( 'SCRIPT_DEBUG', true );
			define( 'WP_CACHE', false );
			break;
		case 'staging':
			define( 'WP_DEBUG', true );
			define( 'WP_DEBUG_DISPLAY', false );
			define( 'WP_DEBUG_LOG', true );
			define( 'SCRIPT_DEBUG', true );
			define( 'WP_CACHE', false );
			break;
		default:
			define( 'WP_DEBUG', false );
			define( 'WP_DEBUG_DISPLAY', false );
			define( 'WP_DEBUG_LOG', false );
			define( 'SCRIPT_DEBUG', false );
			define( 'WP_CACHE', true );
			break;
	}
}

${SSMTP_MAILER}
PHP
fi

# Create the database and grant permissions to the user
wp db create --dbuser=root --dbpass=${DB_ROOT_PASS}
mariadb -uroot -p${DB_ROOT_PASS} -e "GRANT ALL PRIVILEGES ON ${SLUG}.* TO '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"

# Install WordPress
wp core install --title="${TITLE}" \
	--url="${LOCAL_DOMAIN}" \
	--admin_user="${ADMIN}" \
	--admin_password=${ADMIN_PASS} \
	--admin_email=${ADMIN_EMAIL} \
	--skip-email

# Check if a db dump exists
DEV_DB="${DB_DUMP_DIR}/${SLUG}-dev.sql"
OG_DB="${DB_DUMP_DIR}/${SLUG}.sql"
PROD_DB="${DB_DUMP_DIR}/${SLUG}-prod.sql"

echo -e "\nChecking for existing database dump..."
if [ -f ${DEV_DB} ] || [ -f ${OG_DB} ] || [ -f ${PROD_DB} ]; then
	if [ -f ${DEV_DB} ]; then
		echo -e "Importing the Development database..."
		wp db import ${DEV_DB}
	elif [ -f ${OG_DB} ]; then
		echo -e "Importing the database..."
		wp db import ${OG_DB}
	else
		echo -e "Importing the Production database..."
		wp db import ${PROD_DB}

		# Prompt for the Production domain
		read -p "Enter the Production domain (Default: ${SLUG}.com): " PROD_DOMAIN
		if [ -z "${PROD_DOMAIN}" ]; then
			PROD_DOMAIN=${SLUG}.com
		fi
		# Update the site domain and protocol
		wp search-replace "${PROD_DOMAIN}" "${LOCAL_DOMAIN}" --all-tables --skip-columns=guid --skip-tables=${DB_PREFIX}users
		wp search-replace "https://" "http://" --all-tables --skip-columns=guid --skip-tables=${DB_PREFIX}users

		# Deactivate all plugins
		wp plugin deactivate --all
	fi

	# Change the admin password
	wp user update 1 --user_pass=${ADMIN_PASS} --user_email=${ADMIN_EMAIL}

	# Flush the cache
	wp cache flush
else
	echo -e "\nNo existing database dump found. Skipping import..."
fi

# INstall and activate the Simple SMTP Mailer plugin if SMTP_USER and SMTP_PASS are set
if [ -n "${SMTP_USER}" ] && [ -n "${SMTP_PASS}" ]; then
	echo -e "SMTP environment variables found..."
	wp plugin install simple-smtp-mailer --activate
fi

# Create the Apache configuration file if it doesn't exist
APACHE_CONF="${AVAILABLE_SITES_DIR}/${LOCAL_DOMAIN}.conf"
if [ ! -f ${APACHE_CONF} ]; then
	echo -e "\nCreating the Apache configuration file..."
	cat <<APACHE > ${APACHE_CONF}
<VirtualHost *:80>
	ServerName ${LOCAL_DOMAIN}
	ServerAdmin ${ADMIN_EMAIL}

	DocumentRoot ${INSTALL_DIR}
	<Directory ${DEV_PATH}/${SLUG}>
        Options FollowSymLinks
        AllowOverride None
	    Require all granted
    </Directory>

	<Directory ${INSTALL_DIR}>
		Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Order allow,deny
        Allow from all
	</Directory>
	ErrorLog ${DEV_PATH}/${SLUG}/apache-error.log
	CustomLog \${APACHE_LOG_DIR}/${SLUG}-access.log combined
</VirtualHost>
APACHE
fi

# Create a symbolic link to the Apache configuration file
APACHE_SL="${ENABLED_SITES_DIR}/${LOCAL_DOMAIN}.conf"
if [ ! -f ${APACHE_SL} ]; then
	echo -e "Creating a symbolic link to the Apache configuration file..."
	sudo ln -s ${APACHE_CONF} ${APACHE_SL}
fi

# Restart Apache
echo -e "Restarting Apache...\n"
sudo systemctl restart apache2

# Set the output colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Display message about making sure the site domain is in the hosts file
echo -e "Add the following to the bottom of your hosts file:\n${BLUE}"
echo "127.0.0.1 ${LOCAL_DOMAIN}"
echo "::1 ${LOCAL_DOMAIN}"
echo -e "${NC}"

WINDOWS_HOSTS="C:\\Windows\\System32\\drivers\\\etc\hosts"
echo "On Windows, the hosts file is located at ${WINDOWS_HOSTS}"
echo -e "\nYou will need to edit it with an editor that has elevated privileges."
echo -e "You can do this by running the following command in PowerShell as an administrator:\n"
echo -e " ${BLUE}notepad ${WINDOWS_HOSTS}${NC}"

echo -e "\nOn Ubuntu, the hosts file is located at /etc/hosts"
echo -e "You can edit it with the following command:\n"
echo -e " ${BLUE}sudo nano /etc/hosts${NC}\n"

echo -e "If you ran this script in WSL, you will need to edit the hosts file in Windows."
echo -e "If you are using a different operating system, please consult the documentation for editing the hosts file."

# Display the site URL and login credentials
echo -e "Site created at ${GREEN}http://${LOCAL_DOMAIN}${NC}"
echo -e "*** If nothing was imported, you will see a blank page. ***\n"
echo -e "\n\nWordPress Login: ${GREEN}http://${LOCAL_DOMAIN}/wp-admin${NC} (u: ${ADMIN}, p: ${ADMIN_PASS})\n"