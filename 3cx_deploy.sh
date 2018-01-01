#!/bin/bash

# 3CX multiscript 
# version: 0.2

# Pfad zum 3CX initialisierungs-skript
location_init_script="./change_ports.sh"

# Pfad zum 3CX Adressbuch Synchronisierungs-Skript
location_sync_script="./3cx_sync_script.sh"
c

mode=$1

# check if there are arguments and if they are valid
if [[ -z $mode ||  "$mode" != "cronjob" ||  "$mode" !=  "install" ]]; then
		echo "### 3CX SCRIPT ####"
		echo "Usage: 3cx_deploy.sh [ARGS]"
		echo "Example: 3cx_deploy.sh install    Executes the full 3cx_install_script"
		echo "Example: 3cx_deploy.sh cronjob    Downloads the 3cx_sync_script and creates a cronjob"
fi

	# procedure for installer
if [ ! -z $mode ]; then
	if [ $mode = 'install' ]; then
		echo "- starting install..." 
		echo "- quietly getting 3cx init script..."
		wget -q $location_init_script -O /tmp/init_script.sh 
		echo "- setting permissions and executing init script..."
		chmod +x /tmp/init_script.sh
		/bin/bash /tmp/init_script.sh

		if [ $? -eq 0 ]; then
			echo "- 3cx initialized successfully"
			echo "- deleting 3cx init_script.sh now since it's not needed anymore" 
			rm /tmp/init_script.sh
		else
			echo "- ooh, something happened with the init script.. :("
			exit 1
		fi
	fi
	
	# procedure for getting cronjob and setting up (every minute run)
	if [ $mode = 'cronjob' ]; then
		echo "- quietly getting addressbook sync script..."
		wget -q $location_sync_script -O /tmp/3cx_sync_script.sh
		echo "- setting permissions and moving sync script to /etc/cron.d/"
		chmod +x /tmp/3cx_sync_script.sh
		mv /tmp/3cx_sync_script.sh /etc/cron.d/
		(crontab -l ; echo "* * * * * /etc/cron.d/3cx_sync_script.sh")| crontab -

		if [ $? -eq 0 ]; then
			echo "- cronjob has been added!" 
		else
			"- woah! something fishy happened..."
		fi
	fi
fi
