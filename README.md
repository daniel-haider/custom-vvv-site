# VVV Custom site template
For when you just need a simple dev site ... with some additional features for collaborating purposes :) :)

## Setup Default Plugins

To install default plugins you need to create a directory 'default-plugins' which resides inside your vagrant folder (same level as www). Then put the plugins you wish to install inside this folder. Note: the folder of the plugin and not as .zip

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
                                mysql -u root -proot -Nse 'show tables' $pre_dot | while read table; do mysql -u root -proot -e "SET FOREIGN_KEY_CHECKS = 0; drop table $table" $pre_dot; done
                                mysql -u root -proot $pre_dot < /srv/www/"$pre_dot"/public_html/wp-content/.db/$filename
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

Place following snippet in Vagrantfile inside "if defined? VagrantPlugins::Triggers" block:
```
config.trigger.after :up, :stdout => true do
	info "Updating databases..."
	run_remote "bash /srv/database/import-custom-sql.sh"
end
```

### Auto update sites from git
This feature can be enabled on a per site basis. To activate it add the "auto_update" argument to a site in vvv-custom.yml, e.g.
```auto_update: yes please```
You will also need following snippet in your Vagrantfile:
```
# Git Updates and Pulls
  # 
  # If the update argument is specified on vagrant up, all sites will be pulled automatically.
  # If the update argument is specified on vagrant halt, all sites will be commited and pushed
  # automatically.

  if ARGV[0] == "up"
    puts "Saugeiler scheiss: pulling sites"
    vvv_config['sites'].each do |site, args|
      if args['auto_update']
        puts "  * Pulling site "+site
        system("cd "+args['local_dir']+"/public_html/wp-content && git pull origin master")
      end
    end
  elsif ARGV[0] == "halt"
    puts "Saugeiler scheiss: commiting and pushing sites"
    vvv_config['sites'].each do |site, args|
      if args['auto_update']
        puts "  * Commiting and pushing site "+site
        system("cd "+args['local_dir']+"/public_html/wp-content && git add -A && git commit -m 'vagrant auto-commit' && git push -u origin master")
      end
    end
  end
```



