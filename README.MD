# WP-Build

This repository contains shell scripts designed to automate the creation and destruction of local WordPress sites running on Ubuntu.

## Prerequisites

**Ubuntu (or WSL2 running Ubuntu)** with the following installed and running:
- PHP 8.2+ with the following modules active: curl, dom, gd, json, mbstring, mysqli, openssl, xml, zip
- Apache with mod_rewrite enabled
- MariaDB 10.6+ with root access

## Scripts

### `wp-build.sh`
This script creates a local WordPress site in the directory specified by the ${DEV_PATH} environment variable.

It prompts for a `SLUG`. If no `SLUG` is provided, it defaults to `wordpress`.
It also prompts for a `TITLE` for the site. If no `TITLE` is provided, it defaults to the `SLUG` with the first letter capitalized.

- Creates the necessary directory structure at '`DEV_PATH`/`SLUG`/wordpress'
- Installs `wp-cli` if necessary
- Downloads the latest version of WordPress
- Creates the wp-config.php file
- Creates the database using the `SLUG` variable
- Installs WordPress
- Checks `DB_DUMP_DIR` for an existing database dump file and imports it. In this order:
	- `SLUG`-dev.sql
	- `SLUG`.sql
	- `SLUG`-prod.sql
- Installs and activates the [Simple SMTP Mailer](https://wordpress.org/plugins/simple-smtp-mailer) plugin if ${SMTP_USER} and ${SMTP_PASS} are set.

### `wp-destroy.sh`
Removes a WordPress site created from running the `wp-build.sh` script.
==This script removes everything and should be used with extreme caution.==

It prompts for the `SLUG`, which is required.
It also asks you if you want to delete the database.

## Usage

1. Clone or download the repository

```sh
git clone git@github.com:joshmckibbin/wp-build.git
```

2. Make sure you have execute permissions for the scripts

```sh
chmod +x wp-build.sh wp-destroy.sh
```

3. Copy the `.env-sample` file to `.env` and replace the environment values with your own.

```sh
cp .env-sample .env
```

4. Run one of the shell scripts

```sh
./wp-build.sh
```

5. Profit?

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.