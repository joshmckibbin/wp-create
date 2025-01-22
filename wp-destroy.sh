#!/bin/bash

# REMOVE SCRIPT FOR LOCAL WORDPRESS DEVELOPMENT
# Assumes the site was created with wp-build.sh

source .env

# Prompt for the site slug if $1 is not provided
if [ -z "$1" ]; then
	read -p "Enter the site slug: " SLUG
	if [ -z "${SLUG}" ]; then
		echo "The site slug is required. Exiting..." 
		exit 1
	fi
else
	SLUG=$1
fi

# Sanitize the slug
SLUG=$(echo "${SLUG}" | \
	iconv -t ascii//TRANSLIT | \
	sed -r s/[~\^]+//g | \
	sed -r s/[^a-zA-Z0-9]+/-/g | \
	sed -r s/^-+\|-+$//g | \
	tr A-Z a-z)

# Set the installation directory, local domain and database name
INSTALL_DIR="${DEV_DIR}/${SLUG}"
LOCAL_DOMAIN="${SLUG}.local"
DB_NAME=$(echo "${SLUG}" | sed 's/-/_/g')

# Confirm the removal
read -p "Are you sure you want to remove the 'http://${LOCAL_DOMAIN}' WordPress installation? (y/yes/n): " CONFIRM
if [ "${CONFIRM}" == "y" ] || [ "${CONFIRM}" == "yes" ]; then
	# Remove the installation directory
	if [ -d ${INSTALL_DIR} ]; then
		rm -rf ${INSTALL_DIR}
		echo -e "Removed install directory at ${INSTALL_DIR}.\n"
	fi
	
	# Remove the database
	read -p "Do you want to remove the database as well? (y/yes/n): " REMOVE_DB
	if [ "${REMOVE_DB}" == "y" ] || [ "${REMOVE_DB}" == "yes" ]; then
		echo -e "Dropping the '${DB_NAME}' database, if it exists..."
		mariadb -uroot -p${DB_ROOT_PASS} -e "DROP DATABASE IF EXISTS ${DB_NAME};"
	fi

	# Remove the site from the Apache configuration if it exists
	APACHE_CONF="${AVAILABLE_SITES_DIR}/${LOCAL_DOMAIN}.conf"
	if [ -f ${APACHE_CONF} ]; then
		read -p "Do you want to remove the Apache configuration as well? (y/yes/n): " REMOVE_APACHE
		if [ "${REMOVE_APACHE}" == "y" ] || [ "${REMOVE_APACHE}" == "yes" ]; then
			echo -e "Removing the Apache configuration for '${LOCAL_DOMAIN}'..."
			sudo rm -f ${ENABLED_SITES_DIR}/${LOCAL_DOMAIN}.conf
			sudo rm -f ${APACHE_CONF}
			sudo systemctl restart apache2
			echo -e "Removed Apache configuration for '${LOCAL_DOMAIN}'.\n"
		fi
	fi

	echo -e "Finished removing 'http://${LOCAL_DOMAIN}'."
	exit 0
else
	echo "WordPress removal cancelled."
	exit 1
fi
