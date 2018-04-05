# VVV Custom site template
For when you just need a simple dev site

## Overview
This template will allow you to create a WordPress dev environment using only `vvv-custom.yml`.

The supported environments are:
- A single site
- A subdomain multisite
- A subdirectory multisite

# Configuration

### The minimum required configuration:

```
my-site:
  repo: https://github.com/Varying-Vagrant-Vagrants/custom-site-template
  hosts:
    - my-site.test
```
| Setting    | Value       |
|------------|-------------|
| Domain     | my-site.test |
| Site Title | my-site.test |
| DB Name    | my-site     |
| Site Type  | Single      |
| WP Version | Latest      |

### Minimal configuration with custom domain and WordPress Nightly:

```
my-site:
  repo: https://github.com/Varying-Vagrant-Vagrants/custom-site-template
  hosts:
    - foo.test
  custom:
    wp_version: nightly
```
| Setting    | Value       |
|------------|-------------|
| Domain     | foo.test     |
| Site Title | foo.test     |
| DB Name    | my-site     |
| Site Type  | Single      |
| WP Version | Nightly     |

### WordPress Multisite with Subdomains:

```
my-site:
  repo: https://github.com/Varying-Vagrant-Vagrants/custom-site-template
  hosts:
    - multisite.test
    - site1.multisite.test
    - site2.multisite.test
  custom:
    wp_type: subdomain
```
| Setting    | Value               |
|------------|---------------------|
| Domain     | multisite.test      |
| Site Title | multisite.test      |
| DB Name    | my-site             |
| Site Type  | Subdomain Multisite |
| WP Version | Nightly             |

## Configuration Options

```
hosts:
    - foo.test
    - bar.test
    - baz.test
```
Defines the domains and hosts for VVV to listen on. 
The first domain in this list is your sites primary domain.

```
custom:
    site_title: My Awesome Dev Site
```
Defines the site title to be set upon installing WordPress.

```
custom:
    wp_version: 4.6.4
```
Defines the WordPress version you wish to install.
Valid values are:
- nightly
- latest
- a version number

Older versions of WordPress will not run on PHP7, see this page on [how to change PHP version per site](https://varyingvagrantvagrants.org/docs/en-US/adding-a-new-site/changing-php-version/).

```
custom:
    wp_type: single
```
Defines the type of install you are creating.
Valid values are:
- single
- subdomain
- subdirectory

```
custom:
    db_name: super_secet_db_name
```
Defines the DB name for the installation.

## Syncing Databases

based on: https://zach-adams.com/2015/07/keep-varying-vagrant-vagrants-vvv-in-sync-across-multiple-computers/

### Copy databases to wp-content/.db folder for every site on vagrant halt:
create vagrant_halt_custom with following content in config/homebin:
```
#!/bin/bash
#
# Create individual SQL files for each database. These files
# are imported automatically during an initial provision if
# the databases exist per the import-sql.sh process.
DATE=$(date +"%Y%m%d%H%M%S")
mysql -e 'show databases' | \
grep -v -F "information_schema" | \
grep -v -F "performance_schema" | \
grep -v -F "mysql" | \
grep -v -F "test" | \
grep -v -F "Database" | \
while read dbname; do
  mysqldump -uroot "$dbname" > /srv/database/backups/"$dbname".sql &&
  mkdir -p /srv/www/"$dbname"/public_html/wp-content/.db &&
  cp /srv/database/backups/"$dbname".sql /srv/www/"$dbname"/public_html/wp-content/.db/"$dbname"_$DATE.sql &&
  echo "Database $dbname backed up (custom) ..."
done
```

Then run "vagrant up --provision" (you need to provision all sites, when running with --provision-with the files won't be copied)
Then ssh into your box, goto bin/ and:
```
sudo chmod 755 ~/bin/vagrant_halt_custom
sudo chmod +x ~/bin/vagrant_halt_custom
```

### Import sites in vagrant up
create file import-custom-sql.sh with following content in database folder:
```
#!/bin/bash
#
# Import provided SQL files in to MariaDB/MySQL.
#
# The files in the {vvv-dir}/database/backups/ directory should be created by
# mysqldump or some other export process that generates a full set of SQL commands
# to create the necessary tables and data required by a database.
#
# For an import to work properly, the SQL file should be named `db_name.sql` in which
# `db_name` matches the name of a database already created in {vvv-dir}/database/init-custom.sql
# or {vvv-dir}/database/init.sql.
#
# If a filename does not match an existing database, it will not import correctly.
#
# If tables already exist for a database, the import will not be attempted again. After an
# initial import, the data will remain persistent and available to MySQL on future boots
# through {vvv-dir}/database/data
#
# Let's begin...

# Move into the newly mapped backups directory, where mysqldump(ed) SQL files are stored
printf "\nStart MariaDB Database Import\n"
cd /srv/database/backups/

# Parse through each file in the directory and use the file name to
# import the SQL file into the database of the same name
sql_count=`ls -1 *.sql 2>/dev/null | wc -l`
if [ $sql_count != 0 ]
then
        for file in $( ls *.sql )
        do
        pre_dot=${file%%.sql}
        mysql_cmd='SHOW TABLES FROM `'$pre_dot'`' # Required to support hypens in database names
        db_exist=`mysql -u root -proot --skip-column-names -e "$mysql_cmd"`
        if [ "$?" != "0" ]
        then
                printf "  * Error - Create $pre_dot database via init-custom.sql before attempting import\n\n"
        else
                if [ "" == "$db_exist" ]
                then
                        printf "mysql -u root -proot $pre_dot < $pre_dot.sql\n"
                        mysql -u root -proot $pre_dot < $pre_dot.sql
                        printf "  * Import of $pre_dot successful\n"
                else # tables exist - search for db in wp-content/.db folder
                        filename=`cd /srv/www/"$pre_dot"/public_html/wp-content/.db/ &> /dev/null && (ls | tail -1)`
                        if [[ $filename ]]
                        then
                                printf "  * Updating $pre_dot with contents of $filename\n"
                        # if found, import latest db backup
                        else
                        # if not found, skip it
                                printf "  * Skipped import of $pre_dot - tables exist and no db found in wp-content/.db\n"
                        fi
                fi
        fi
        done
        printf "Databases imported\n"
else
        printf "No custom databases to import\n"
fi
```

