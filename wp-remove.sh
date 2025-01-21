#!/bin/bash

# REMOVE SCRIPT FOR LOCAL WORDPRESS DEVELOPMENT
# Assumes the site was created with wp-build.sh

source .env

# Prompt for the site slug
read -p "Enter the site slug (Default: wordpress): " SLUG
if [ -z "${SLUG}" ]; then
	echo "The site slug is required."
	exit 1
else
	SLUG=$(echo ${SLUG} | tr '[:upper:]' '[:lower:]')
fi

# Set the installation directory and local domain
INSTALL_DIR="${DEV_PATH}/${SLUG}"
LOCAL_DOMAIN="${SLUG}.local"

# Check if the WordPress installation exists
if [ -f "${INSTALL_DIR}/wordpress/wp-config.php" ]; then
	read -p "Are you sure you want to remove the 'http://${LOCAL_DOMAIN}' WordPress installation? (y/n): " CONFIRM
	if [ "${CONFIRM}" == "y" ]; then

		# Remove the database
		read -p "Do you want to remove the database as well? (y/n): " REMOVE_DB
		if [ "${REMOVE_DB}" == "y" ]; then
			echo -e "Dropping the '${SLUG}' database..."
			wp db drop --yes --path="${INSTALL_DIR}/wordpress"
		fi

		echo -e ""

		# Remove the site from the Apache configuration
		APACHE_CONF="${AVAILABLE_SITES_DIR}/${LOCAL_DOMAIN}.conf"
		if [ -f ${APACHE_CONF} ]; then
			sudo rm ${ENABLED_SITES_DIR}/${LOCAL_DOMAIN}.conf
			sudo rm -f ${APACHE_CONF}
			sudo systemctl restart apache2
			echo -e "Removed Apache configuration for '${LOCAL_DOMAIN}'.\n"
		fi

		rm -rf ${INSTALL_DIR}
		echo -e "Removed WordPress directory at ${INSTALL_DIR}.\n\nFinished removing 'http://${LOCAL_DOMAIN}'."
		exit 0
	else
		echo "WordPress removal cancelled."
		exit 1
	fi
else
	echo "WordPress installation not found at ${INSTALL_DIR}."
	exit 1
fi