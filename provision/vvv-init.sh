#!/usr/bin/env bash
# Provision WordPress Stable

DOMAIN=`get_primary_host "${VVV_SITE_NAME}".test`
DOMAINS=`get_hosts "${DOMAIN}"`
SITE_TITLE=`get_config_value 'site_title' "${DOMAIN}"`
WP_VERSION=`get_config_value 'wp_version' 'latest'`
WP_TYPE=`get_config_value 'wp_type' "single"`
DB_NAME=`get_config_value 'db_name' "${VVV_SITE_NAME}"`
DB_NAME=${DB_NAME//[\\\/\.\<\>\:\"\'\|\?\!\*-]/}

# Make a database, if we don't already have one
echo -e "\nCreating database '${DB_NAME}' (if it's not already there)"
mysql -u root --password=root -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME}"
mysql -u root --password=root -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO wp@localhost IDENTIFIED BY 'wp';"
echo -e "\n DB operations done.\n\n"

# Nginx Logs
mkdir -p ${VVV_PATH_TO_SITE}/log
touch ${VVV_PATH_TO_SITE}/log/error.log
touch ${VVV_PATH_TO_SITE}/log/access.log

# Install and configure the latest stable version of WordPress
if [[ ! -f "${VVV_PATH_TO_SITE}/public_html/wp-load.php" ]]; then
    echo "Downloading WordPress..."
	noroot wp core download --version="${WP_VERSION}"
fi

if [[ ! -f "${VVV_PATH_TO_SITE}/public_html/wp-config.php" ]]; then
  echo "Configuring WordPress Stable..."
  noroot wp core config --dbname="${DB_NAME}" --dbuser=wp --dbpass=wp --quiet --extra-php <<PHP
define( 'WP_DEBUG', true );
PHP
fi

if ! $(noroot wp core is-installed); then
  echo "Installing WordPress Stable..."

  if [ "${WP_TYPE}" = "subdomain" ]; then
    INSTALL_COMMAND="multisite-install --subdomains"
  elif [ "${WP_TYPE}" = "subdirectory" ]; then
    INSTALL_COMMAND="multisite-install"
  else
    INSTALL_COMMAND="install"
  fi

  noroot wp core ${INSTALL_COMMAND} --url="${DOMAIN}" --quiet --title="${SITE_TITLE}" --admin_name=admin --admin_email="admin@local.test" --admin_password="password"

  echo "Deactivating wordpress default plugins ..."
  noroot wp plugin deactivate $(noroot wp plugin list --field=name)

  echo "Deleting wordpress default plugins ..."
  noroot wp plugin delete $(noroot wp plugin list --field=name)

  echo "Copying default plugins into plugins dir ..."
  cp -a /vagrant/default-plugins/. ${VVV_PATH_TO_SITE}/public_html/wp-content/plugins/

  echo "Activating plugins ..."
  noroot wp plugin activate --all

  echo "Add roots sage theme ..."
  cd ${VVV_PATH_TO_SITE}/public_html/wp-content/themes/
  git clone https://github.com/roots/sage.git ${VVV_SITE_NAME}
  cd ${VVV_PATH_TO_SITE}/public_html/wp-content/themes/${VVV_SITE_NAME}
  noroot composer install

  echo "Add acf options page to functions.php ..."
  printf "\nif( function_exists('acf_add_options_page') ) {\n  acf_add_options_page();\n}\n" >> resources/functions.php

  echo "Add auto_update_plugin filter functions.php ..."
  printf "\nadd_filter( 'auto_update_plugin', '__return_true' );\n" >> resources/functions.php

  echo "Add pre_comment_user_ip filter to dsgvo.php ..."
  printf "\nadd_filter( 'pre_comment_user_ip', 'wpb_remove_commentsip' );\nfunction  wpb_remove_commentsip( $comment_author_ip ) {\n  return '';\n}\n" >> app/dsgvo.php

  echo "Add gform_ip_disable filter to dsgvo.php ..."
  printf "\nadd_filter( 'gform_ip_address', '__return_empty_string' );\n" >> app/dsgvo.php

  echo "Add disable emoji filter to dsgvo.php ..."
  printf "\nfunction disable_emojis() {\n  remove_action( 'wp_head', 'print_emoji_detection_script', 7 );\n  remove_action( 'admin_print_scripts', 'print_emoji_detection_script' );\n  remove_action( 'wp_print_styles', 'print_emoji_styles' );\n  remove_action( 'admin_print_styles', 'print_emoji_styles' );  \n  remove_filter( 'the_content_feed', 'wp_staticize_emoji' );\n  remove_filter( 'comment_text_rss', 'wp_staticize_emoji' );  \n  remove_filter( 'wp_mail', 'wp_staticize_emoji_for_email' );\n  add_filter( 'tiny_mce_plugins', 'disable_emojis_tinymce' );\n}\nadd_action( 'init', 'disable_emojis' );\n\nfunction disable_emojis_tinymce( $plugins ) {\n  if ( is_array( $plugins ) ) {\n    return array_diff( $plugins, array( 'wpemoji' ) );\n  } else {\n    return array();\n  }\n}\n" >> app/dsgvo.php

  echo "Add disable access to debug.log to .htaccess ..."
  printf "\n<Files debug.log>\n order deny,allow\n deny from all\n</Files>\n" >> ../../.htaccess  

  echo "Activating roots sage theme ..."
  noroot wp theme activate ${VVV_SITE_NAME}/resources

  echo "Deleting inactive themes ..."
  noroot wp theme delete $(noroot wp theme list --status=inactive --field=name)

else
  echo "Updating WordPress Stable..."
  cd ${VVV_PATH_TO_SITE}/public_html
  noroot wp core update --version="${WP_VERSION}"
fi

cp -f "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf.tmpl" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
sed -i "s#{{DOMAINS_HERE}}#${DOMAINS}#" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"

if [ -n "$(type -t is_utility_installed)" ] && [ "$(type -t is_utility_installed)" = function ] && `is_utility_installed core tls-ca`; then
    sed -i "s#{{TLS_CERT}}#ssl_certificate /vagrant/certificates/${VVV_SITE_NAME}/dev.crt;#" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
    sed -i "s#{{TLS_KEY}}#ssl_certificate_key /vagrant/certificates/${VVV_SITE_NAME}/dev.key;#" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
else
    sed -i "s#{{TLS_CERT}}##" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
    sed -i "s#{{TLS_KEY}}##" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
fi
