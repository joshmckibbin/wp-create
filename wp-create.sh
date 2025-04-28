#!/bin/bash

# BUILD SCRIPT FOR LOCAL WORDPRESS DEVELOPMENT
# Author: Josh Mckibbin
# Version: 1.0.3
#
# This script creates a new WordPress site using the variables defined in the .env file:
# 	- Creates the necessary directory structure (e.g., ${DEV_DIR}/${SLUG}/wordpress)
#	- Downloads the latest version of WordPress
# 	- Creates the database schema and user with necessary permissions
# 	- Creates the wp-config.php file
# 	- Installs WordPress
# 	- Creates the .htaccess file
# 	- Checks for an existing database dump (${SLUG}-dev.sql, ${SLUG}.sql, ${SLUG}-prod.sql) in ${DB_DUMP_DIR} and imports it if found
#	- Installs and activates the Simple SMTP Mailer plugin (if SMTP_USER and SMTP_PASS are set)
#
# Minimum Requirements:
#	- Local linux development environment (WSL2 running Ubuntu in this case):
#		- Apache with mod_rewrite enabled
#		- MariaDB 10.6+ with root access
#		- PHP 8.2+ with the curl, imagick, json, mbstring, mysql, xml and zip extensions installed
#	- The provided .env file placed in the same directory as this script with the ADMIN_EMAIL variable replaced with a valid email address
#
# DO NOT RUN THIS SCRIPT IN A PRODUCTION ENVIRONMENT !!!

source $(dirname "$BASH_SOURCE")/.env

# Prompt for the site title if $1 is not provided
if [ -z "$1" ]; then
	read -p "Enter the site title (Default: WordPress): " TITLE
	if [ -z "${TITLE}" ]; then
		TITLE="WordPress"
	fi
else
	TITLE=$1
fi

# Create a slugify function
slugify() {
	SLUG=$(echo "${1}" | \
		iconv -t ascii//TRANSLIT | \
		sed -r s/[~\^]+//g | \
		sed -r s/[^a-zA-Z0-9]+/-/g | \
		sed -r s/^-+\|-+$//g | \
		tr A-Z a-z)
	echo ${SLUG:0:15}
}

# Prompt for the site slug
SLUG=$(slugify "${TITLE}")
read -p "Enter the site slug (Default: ${SLUG}}): " USER_SLUG
if [[ -v ${USER_SLUG} ]]; then
	SLUG=$(slugify "${USER_SLUG}")
fi

# Set the output colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

INSTALL_DIR="${DEV_DIR}/${SLUG}/wordpress"

# Attempt to create the config directory if it doesn't exist and if it fails, exit
if [ ! -d ${CONFIG_DIR} ]; then
	mkdir -p ${CONFIG_DIR}
	if [ $? -ne 0 ]; then
		echo "The configuration directory could not be created. Exiting..."
		exit 1
	fi
	echo -e "${GREEN}Success:${NC} Configuration directory created at ${CONFIG_DIR}"
fi

# Attempt to create the installation directory if it doesn't exist and if it fails, exit
if [ ! -d ${INSTALL_DIR} ]; then
	mkdir -p ${INSTALL_DIR}
	if [ $? -ne 0 ]; then
		echo "The installation directory could not be created. Exiting..."
		exit 1
	fi
	echo -e "${GREEN}Success:${NC} Installation directory created at ${INSTALL_DIR}"
fi

# Move to the web directory
cd ${INSTALL_DIR}

# Check if there is already a WordPress installation
if [ -f wp-config.php ]; then
	echo "WordPress is already installed in this directory. Exiting..."
	exit 1
else

# Download the latest version of WordPress
echo -e "Downloading WordPress..."
wp core download --skip-content

# Generate DB_NAME
DB_NAME=$(echo ${SLUG} | sed 's/-/_/g')

# Create the database and grant permissions to the user
echo -e "Creating database: ${DB_NAME}..."
#wp db create --dbuser=root --dbpass=${DB_ROOT_PASS}
if mariadb -u root -p${DB_ROOT_PASS} -e \
	"CREATE DATABASE IF NOT EXISTS ${DB_NAME}; \
	CREATE USER IF NOT EXISTS ${DB_USER}@localhost; \
	GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO ${DB_USER}@localhost IDENTIFIED BY '${DB_PASS}';" \
	&> "${CONFIG_DIR}/mariadb.log"; then
	echo -e "${GREEN}Success:${NC} Database created and user permissions granted"
else
	echo -e "Database creation and user permissions failed. Exiting..."
	exit 1
fi

# Create the wp-config.php file
DB_PREFIX="wp_${DB_NAME}_"
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

wp config create --dbname=${DB_NAME} \
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

# Install WordPress
wp core install --title="${TITLE}" \
	--url="${LOCAL_DOMAIN}" \
	--admin_user="${ADMIN_USER}" \
	--admin_password=${ADMIN_PASS} \
	--admin_email=${ADMIN_EMAIL} \
	--skip-email

# Create the .htaccess file
cat <<HTACCESS > .htaccess
# BEGIN WordPress

RewriteEngine On
RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]

# END WordPress
HTACCESS

# Set loose permissions
echo -e "Updating the permissions..."
sudo chown -R "${USER}":www-data ${INSTALL_DIR}
sudo find ${INSTALL_DIR} -type d -exec chmod 755 {} \;
sudo find ${INSTALL_DIR} -type f -exec chmod 644 {} \;
sudo find ${INSTALL_DIR}/wp-content -type d -exec chmod 775 {} \;
sudo find ${INSTALL_DIR}/wp-content -type f -exec chmod 664 {} \;

# Check if a db dump exists
DEV_DB="${DB_DUMP_DIR}/${SLUG}-dev.sql"
OG_DB="${DB_DUMP_DIR}/${SLUG}.sql"
PROD_DB="${DB_DUMP_DIR}/${SLUG}-prod.sql"

if [ -f ${DEV_DB} ] || [ -f ${OG_DB} ] || [ -f ${PROD_DB} ]; then
	echo -e "Existing database dump found..."
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
fi

# Install and activate the Simple SMTP Mailer plugin if SMTP_USER and SMTP_PASS are set
if [ -n "${SMTP_USER}" ] && [ -n "${SMTP_PASS}" ]; then
	echo -e "SMTP environment variables found..."
	wp plugin install simple-smtp-mailer --activate
fi

# Create the available sites directory if it doesn't exist, exit if it fails
if [ ! -d ${AVAILABLE_SITES_DIR} ]; then
	echo -e "Creating the available sites directory..."
	mkdir -p ${AVAILABLE_SITES_DIR}
	if [ $? -ne 0 ]; then
		echo "The available sites directory could not be created. Exiting..."
		exit 1
	fi
fi

# Create the Apache configuration file if it doesn't exist
APACHE_CONF="${AVAILABLE_SITES_DIR}/${LOCAL_DOMAIN}.conf"
if [ ! -f ${APACHE_CONF} ]; then
	cat <<APACHE > ${APACHE_CONF}
<VirtualHost *:80>
	ServerName ${LOCAL_DOMAIN}
	ServerAdmin ${ADMIN_EMAIL}

	DocumentRoot ${INSTALL_DIR}
	<Directory ${DEV_DIR}/${SLUG}>
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
	ErrorLog ${DEV_DIR}/${SLUG}/apache-error.log
	CustomLog \${APACHE_LOG_DIR}/${SLUG}-access.log combined
</VirtualHost>
APACHE
	echo -e "${GREEN}Success:${NC} Apache configuration file created at ${APACHE_CONF}"
fi

# Create a symbolic link to the Apache configuration file
APACHE_SL="${ENABLED_SITES_DIR}/${LOCAL_DOMAIN}.conf"
if [ ! -f ${APACHE_SL} ]; then
	sudo ln -s ${APACHE_CONF} ${APACHE_SL}
	echo -e "${GREEN}Success:${NC} Enabled the site via symbolic link at ${APACHE_SL}"
fi

# Restart Apache
if sudo systemctl restart apache2 &> /dev/null; then
	echo -e "${GREEN}Success:${NC} Apache restarted\n"
else
	echo -e "Apache could not be restarted."
	echo -e "Check the Apache error log at ${DEV_DIR}/${SLUG}/apache-error.log. Exiting..."
	exit 1
fi

# Display message about making sure the site domain is in the hosts file
echo -e "Add the following to the bottom of your hosts file:\n${GREEN}"
echo "127.0.0.1 ${LOCAL_DOMAIN}"
echo "::1 ${LOCAL_DOMAIN}"
echo -e "${NC}"

WINDOWS_HOSTS="C:\\Windows\\System32\\drivers\\\etc\hosts"
echo -e "If you ran this installer in WSL, you need to update the Windows hosts file."
echo -e "It is located at ${BLUE}${WINDOWS_HOSTS}${NC}"
echo -e "Open PowerShell as an Administrator and run the following command:\n"
echo -e "${GREEN}notepad ${WINDOWS_HOSTS}${NC}\n"

echo -e "If it was ran in native Ubuntu, the hosts file is located at ${BLUE}/etc/hosts${NC}"
echo -e "You can edit it with the following command:\n"
echo -e "${GREEN}sudo nano /etc/hosts${NC}\n"

# Display the Login URL and credentials
echo -e "WordPress Login: ${BLUE}http://${LOCAL_DOMAIN}/wp-admin${NC} (u: ${ADMIN_USER}, p: ${ADMIN_PASS})\n"
exit 0