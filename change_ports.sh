#!/bin/bash

#Text Colors
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color

################################################################################
############################# Function Declaration #############################
function update_db ()
{
	local field_name=$1
	local new_value=$2
	local suppress_output=$3

	while IFS= read -r line ; do
		if [[ $line == "UPDATE 1"* ]] ; then
			if [[ "$suppress_output" != "1" ]] ; then
				echo -e "${GREEN}OK${NC}"
			fi
			local exit_code=1
		else
			if [[ "$suppress_output" != "1" ]] ; then
				if [[ $field_name == "FAX_RTPFIRST"  ]] || [[ $field_name == "FAX_RTPLAST" ]] ; then # Added exception for SP4 as Fax Service was removed
					echo -e "${YELLOW}SKIPPED (Ignore only if on SP4 or newer)${NC}"
				else
					echo -e "${RED}FAILED${NC}"
				fi
			fi
			local exit_code=0
		fi
	done <<< "$(su -c "psql -d database_single -c \"UPDATE parameter SET value = '$new_value' WHERE name='$field_name';\"" postgres)"

        return $exit_code   # Use 'echo $?' to get return code
}

function start_stop_service ()
{
	local service_name=$1
	if [[ "$2" == "1" ]] ; then        # $2 = 1 ---> start / $2 = 0 ---> stop
		local action="start"
	elif [[ "$2" == "0" ]] ; then
		local action="stop"
	else
		echo "Invalid function usage"
		exit
	fi

	service $service_name $action >/dev/null 2>/dev/null

	local action_success=1
	while IFS= read -r line ; do
		if [[ $line == *"Active:"* ]]  ; then
			if [[ "$action" == "start" ]] && [[ $line != *" active"* ]] ; then
				action_success=0
			elif [[ "$action" == "stop" ]] && [[ $line != *" inactive"* ]] ; then
				action_success=0
			fi
		fi
	done <<< "$(service $service_name status)"

	return $action_success  # Use 'echo $?' to get return code
}

function fart() {
	if [ $# -lt 3 ] || [ $# -gt 4 ] ; then
		echo "Function: invalid number of parameters"
		exit
	fi

	local file=$1
	local match_pattern=$2
	local rep_line=$3
	local suppress_output=$4

	local orig_line="$(cat $file | grep "$match_pattern" | head -1)"

	cat $file | sed -e "s/$orig_line/$rep_line/" > $file".scripttemp"
	rm $file >/dev/null 2>/dev/null
	mv $file".scripttemp" $file >/dev/null 2>/dev/null

	local replaced_ok=0
	while IFS= read -r line ; do
		if [[ $line == "$rep_line" ]] ; then
			replaced_ok=1
		fi

		break
	done <<< "$(cat $file | grep "$rep_line" | head -1)"

	if [ $replaced_ok -eq 1 ] && [[ $suppress_output != "1" ]] ; then
		echo -e "${GREEN}OK${NC}"
	elif [ $replaced_ok -eq 0 ] && [[ $suppress_output != "1" ]] ; then
		echo -e "${RED}FAILED${NC}"
	fi

	return $replaced_ok   # Use 'echo $?' to get return code
}
######################## Function Declaration End ##############################
################################################################################


### Check if root is running the script
if [ $(id -u) -ne 0 ] ; then
        echo -e "\n  Only ${RED}root${NC} may use this script. Consider using sudo (install if not present) or logging in as root.\n"
        exit 2
fi


### Check if 3CX is installed
isinstalled=0
while IFS= read -r line ; do
        if [[ $line == *"3cxpbx"*  ]] ; then
		isinstalled=1
        fi
done <<< "$(dpkg -l | grep "3cxpbx")"

if [ $isinstalled -eq 0 ] ; then  # 3CX not installed
	echo -e "\n  3CX is ${RED}not installed${NC} on the system.\n"
	exit
fi


### Check if all 3CX Service are currently running
while IFS= read -r line ; do
	if [[ $line != *" active"* ]] ; then
		echo -e "\n  ${RED}Not all 3CX Services are running.${NC} Please make sure that you have finished the initial setup and that all services are running before running the script again.\n"
        	exit
	fi
done <<< "$(service 3CX* status | grep "Active" && service nginx status | grep "Active" && service postgresql status | grep "Active")"


### Informative Message
clear
echo -e "\n\tIn order to complete this procedure the ${RED}SERVICES WILL BE STOPPED${NC}.\n\tTo aboard press Ctrl + C.\n"


### Ask if each Instance will have its own Public IP or not
while true ; do
	echo -e "Choose what migration pattern you are going to perform:"
	echo -e "  1. Each Instance will have its own Public IP (Reset all ports to default settings)"
	echo -e "  2. All Instances will share the same Public IP"
	echo " "
        read -n1 -p "Enter option "$'\033[0;36m'"1"$'\033[0m'" or "$'\033[0;36m'"2"$'\033[0m'": " sameip
	echo -e " "

        if [ $sameip -eq 1  ] || [ $sameip -eq 2 ] ; then
                break
        fi

        echo -e "\n  ${RED}Incorrect Option!${NC} Please enter option ${GREEN}1${NC} or ${GREEN}2${NC}.\n"
done


### Ask for Instance Number and validate if same Public IP will be used
if [[ $sameip == "2" ]] ; then
	while true ; do
        	read -n1 -n2 -p "Enter the "$'\033[0;36m'"Instance Number"$'\033[0m'" you want this installation to be (1-30): " instance
		echo -e " "

	        if [ $instance -ge 1  ] && [ $instance -le 30 ] ; then
        	        break
	        fi

	        echo -e "\n  ${RED}Incorrect Instance Number${NC}. Please enter a number between 1-30.\n"
	done
fi


### Variable instatiation based on input
if [[ $sameip == "2" ]] ; then  # If Instance share same Public IP, split RTP port ranges
	sipport="$((4+$instance))""060"
	tunnelport="$((4+$instance))""090"
	http="$((4+$instance))""000"
	https="$((4+$instance))""001"
	rtpintfirst="$((34+$instance))""500"
	rtpintlast="$((34+$instance))""999"
	rtpextfirst="$((34+$instance))""000"
	rtpextlast="$((34+$instance))""499"
	ivrrtpfirst="12500"
	ivrrtplast="12755"
	qmrtpfirst="13500"
	qmrtplast="13755"
	faxrtpfirst="10500"
	faxrtplast="10755"
	tnlrtpfirst="11500"
	tnlrtplast="11755"
else   # else use default ports
	sipport="5060"
	tunnelport="5090"
	http="5000"
	https="5001"
	rtpintfirst="7000"
	rtpintlast="7500"
	rtpextfirst="9000"
	rtpextlast="9500"
	ivrrtpfirst="12000"
	ivrrtplast="12255"
	qmrtpfirst="13000"
	qmrtplast="13255"
	faxrtpfirst="10000"
	faxrtplast="10255"
	tnlrtpfirst="11000"
	tnlrtplast="11255"
fi


### Stop all 3CX Services except Postgres, that must be started, then check, else aboard
echo -ne "  Stopping 3CX Services................... "
start_stop_service "3CX*" 0
tcx_stopped=$?

start_stop_service "nginx" 0
nginx_stopped=$?

start_stop_service "postgresql" 1
db_started=$?

if [ $tcx_stopped -eq 1 ] || [ $nginx_stopped -eq 1 ] || [ $db_started -eq 1 ] ; then
        echo -e "${GREEN}OK${NC}"
else
        echo -e "${RED}FAILED${NC}"
	echo " "
	echo "  Could not stop 3CX Services and nginx, and start Postgres Service."
	echo "  Attempting to restart all services and aboarding the process..."
	service 3CX* start >/dev/null 2>/dev/null
	service nginx start >/dev/null 2>/dev/null
	service postgresql start >/dev/null 2>/dev/null
	echo " "
	exit
fi


### Update SQL Entries
echo -ne "  Updating SIP Port....................... "
update_db "SIPPORT" "$sipport"

echo -ne "  Updating Tunnel Port.................... "
update_db "TNL_CLIENT_LISTEN_PORT" "$tunnelport"

echo -ne "  Updating IVR First RTP Port............. "
update_db "IVR_RTPFIRST" "$ivrrtpfirst"

echo -ne "  Updating IVR Last RTP Port.............. "
update_db "IVR_RTPLAST" "$ivrrtplast"

echo -ne "  Updating Queue Manager First RTP Port... "
update_db "QM_RTPFIRST" "$qmrtpfirst"

echo -ne "  Updating Queue Manager Last RTP Port.... "
update_db "QM_RTPLAST" "$qmrtplast"

echo -ne "  Updating FAX First RTP Port............. "
update_db "FAX_RTPFIRST" "$faxrtpfirst"

echo -ne "  Updating FAX Last RTP Port.............. "
update_db "FAX_RTPLAST" "$faxrtplast"

echo -ne "  Updating Tunnel First RTP Port.......... "
update_db "TNL_RTPFIRST" "$tnlrtpfirst"

echo -ne "  Updating Tunnel Last RTP Port........... "
update_db "TNL_RTPLAST" "$tnlrtplast"


### Update and check 3cxmediaserver.ini file with new Internal RTP Ports
echo -ne "  Changing Internal RTP Ports............. "
new_line="$(cat /var/lib/3cxpbx/Bin/3cxmediaserver.ini | grep "^FLP" | head -1 | cut --only-delimited --delimiter=","  --fields=1)"","$rtpintfirst
fart "/var/lib/3cxpbx/Bin/3cxmediaserver.ini" "^FLP" "$new_line" "1"
first_ok=$?

new_line="$(cat /var/lib/3cxpbx/Bin/3cxmediaserver.ini | grep "^LLP" | head -1 | cut --only-delimited --delimiter=","  --fields=1)"","$rtpintlast
fart "/var/lib/3cxpbx/Bin/3cxmediaserver.ini" "^LLP" "$new_line" "1"
last_ok=$?

if [ $first_ok -eq 1 ] && [ $last_ok -eq 1 ] ; then
	echo -e "${GREEN}OK${NC}"
else
	echo -e "${RED}FAILED${NC}"
fi


### Update and check 3cxmediaserver.ini file with new External RTP Ports
echo -ne "  Changing External RTP Ports............. "
new_line="$(cat /var/lib/3cxpbx/Bin/3cxmediaserver.ini | grep "^FEP" | head -1 | cut --only-delimited --delimiter=","  --fields=1)"","$rtpextfirst
fart "/var/lib/3cxpbx/Bin/3cxmediaserver.ini" "^FEP" "$new_line" "1"
first_ok=$?

new_line="$(cat /var/lib/3cxpbx/Bin/3cxmediaserver.ini | grep "^LEP" | head -1 | cut --only-delimited --delimiter=","  --fields=1)"","$rtpextlast
fart "/var/lib/3cxpbx/Bin/3cxmediaserver.ini" "^LEP" "$new_line" "1"
last_ok=$?

if [ $first_ok -eq 1 ] && [ $last_ok -eq 1 ] ; then
        echo -e "${GREEN}OK${NC}"
else
        echo -e "${RED}FAILED${NC}"
fi


### Update nginx.conf file with new HTTP/s Ports
echo -ne "  Changing HTTP/S Ports................... "
line_to_replace="$(cat /var/lib/3cxpbx/Bin/nginx/conf/nginx.conf | grep "listen" | grep -v "ssl")"
new_line="$(echo "$line_to_replace" | awk -F"listen" '{print $1}')""listen "$http";"
fart "/var/lib/3cxpbx/Bin/nginx/conf/nginx.conf" "$line_to_replace" "$new_line" "1"
http_ok=$?

line_to_replace="$(cat /var/lib/3cxpbx/Bin/nginx/conf/nginx.conf | grep "listen" | grep  "ssl")"
new_line="$(echo "$line_to_replace" | awk -F"listen" '{print $1}')""listen "$https" ssl;"
fart "/var/lib/3cxpbx/Bin/nginx/conf/nginx.conf" "$line_to_replace" "$new_line" "1"
https_ok=$?

if [ $http_ok -eq 1 ] && [ $https_ok -eq 1 ] ; then
        echo -e "${GREEN}OK${NC}"
else
        echo -e "${RED}FAILED${NC}"
fi


### Update all URLs in the Databse with the new port information
echo -ne "  Updating URLs with new ports............ "
while IFS= read -r line ; do
        if [[ $line == "PBXPUBLICIP"* ]] ; then
                extfqdn=`echo $line | cut --only-delimited --delimiter="|" --fields=2`
        fi

        if [[ $line == "SIPDOMAIN2"* ]] ; then
                intfqdn=`echo $line | cut --only-delimited --delimiter="|" --fields=2`
        fi
done <<< "$(su -c "psql -d database_single -c \"SELECT name,value FROM parameter WHERE name SIMILAR TO '(PBXPUBLICIP)' OR name SIMILAR TO '(SIPDOMAIN2)';\"" postgres | tr -d ' ')"

name_array=()
found=0
while IFS= read -r line ; do
        if [[ $line == *"$extfqdn"* ]] || [[ $line == *"$intfqdn"*  ]] ; then
                name=`echo $line | cut --only-delimited --delimiter="|" --fields=1`
                name_array+=($name)
                found=$(($found+1))
        fi
done <<< "$(su -c "psql -d database_single -c \"SELECT name,value FROM parameter WHERE value SIMILAR TO '(http|https)(://)($extfqdn|$intfqdn)%';\"" postgres | tr -d ' ')"

changed=0
for name in "${name_array[@]}" ; do
        new=

        if [[ $name == "WEB_ROOT_LOCAL" ]] ; then
                new="http://"$intfqdn":"$http"/"
        elif [[ $name == "WEB_ROOT_EXT" ]] ; then
                new="http://"$extfqdn":"$http"/"
        elif [[ $name == "WEB_ROOT_LOCAL_SEC" ]] ; then
                new="https://"$intfqdn":"$https"/"
        elif [[ $name == "WEB_ROOT_EXT_SEC" ]] ; then
                new="https://"$extfqdn":"$https"/"
        elif [[ $name == "WEB_ROOT_EXT_SEC" ]] ; then
                new="https://"$extfqdn":"$https"/"
        elif [[ $name == "MYPHONE_LINK_LOCAL" ]] ; then
                new="http://"$intfqdn":"$http"/myphone/MPWebService.asmx"
        elif [[ $name == "MYPHONE_LINK_EXT" ]] ; then
                new="http://"$extfqdn":"$http"/myphone/MPWebService.asmx"
        elif [[ $name == "MYPHONE_LINK_LOCAL_SEC" ]] ; then
                new="https://"$intfqdn":"$https"/myphone/MPWebService.asmx"
        elif [[ $name == "MYPHONE_LINK_EXT_SEC" ]] ; then
                new="https://"$extfqdn":"$https"/myphone/MPWebService.asmx"
        elif [[ $name == "REPORTER_LINK_LOCAL" ]] ; then
                new="http://"$intfqdn":"$http"/Reporter"
        elif [[ $name == "REPORTER_LINK_EXT" ]] ; then
                new="http://"$extfqdn":"$http"/Reporter"
        elif [[ $name == "REPORTER_LINK_LOCAL_SEC" ]] ; then
                new="https://"$intfqdn":"$https"/Reporter"
        elif [[ $name == "REPORTER_LINK_EXT_SEC" ]] ; then
                new="https://"$extfqdn":"$https"/Reporter"
        elif [[ $name == "PROVISIONING_LINK_LOCAL" ]] ; then
                new="http://"$intfqdn":"$http"/provisioning"
        elif [[ $name == "PROVISIONING_LINK_EXT" ]] ; then
                new="http://"$extfqdn":"$http"/provisioning"
        elif [[ $name == "PROVISIONING_LINK_LOCAL_SEC" ]] ; then
                new="https://"$intfqdn":"$https"/provisioning"
        elif [[ $name == "PROVISIONING_LINK_EXT_SEC" ]] ; then
                new="https://"$extfqdn":"$https"/provisioning"
        elif [[ $name == "MANAGEMENT_LINK_LOCAL" ]] ; then
                new="http://"$intfqdn":"$http"/management"
        elif [[ $name == "MANAGEMENT_LINK_EXT" ]] ; then
                new="http://"$extfqdn":"$http"/management"
        elif [[ $name == "MANAGEMENT_LINK_LOCAL_SEC" ]] ; then
                new="https://"$intfqdn":"$https"/management"
        elif [[ $name == "MANAGEMENT_LINK_EXT_SEC" ]] ; then
                new="https://"$extfqdn":"$https"/management"
        elif [[ $name == "CALLUS_LINK_EXT_SEC" ]] ; then
                new="https://"$extfqdn":"$https"/webrtc"
        fi

        if [[ $new != ""  ]] ; then
		update_db "$name" "$new" 1   # the '1' at the end is to suppress the output
		changed=$(($changed+1))
        fi
done

if [ $found -eq $changed ] ; then
        echo -e "${GREEN}OK${NC}   [${GREEN}$changed${NC}/$found]"
else
        echo -e "${RED}FAILED${NC}   [${RED}$changed${NC}/$found]"
fi


### Adding iptables rules
echo -ne "  Adding iptables rules................... "

allports_array=()
allports_array+=("5060" "5061" "5090" "5000" "5001" "9000" "9500" "35000" "35500" "7000" "7500" "7500" "8000" "6060" "6061" "6090" "6000" "6001" "36000" "36500" "7000" "7500" "7500" "8000" "7060" "7061" "7090" "7000" "7001" "37000" "37500" "7000" "7500" "7500" "8000" "8060" "8061" "8090" "8000" "8001" "38000" "38500" "7000" "7500" "7500" "8000" "9060" "9061" "9090" "9000" "9001" "39000" "39500" "7000" "7500" "7500" "8000" "10060" "10061" "10090" "10000" "10001" "40000" "40500" "7000" "7500" "7500" "8000" "11060" "11061" "11090" "11000" "11001" "41000" "41500" "7000" "7500" "7500" "8000" "12060" "12061" "12090" "12000" "12001" "42000" "42500" "7000" "7500" "7500" "8000" "13060" "13061" "13090" "13000" "13001" "43000" "43500" "7000" "7500" "7500" "8000" "14060" "14061" "14090" "14000" "14001" "44000" "44500" "7000" "7500" "7500" "8000" "15060" "15061" "15090" "15000" "15001" "45000" "45500" "7000" "7500" "7500" "8000" "16060" "16061" "16090" "16000" "16001" "46000" "46500" "7000" "7500" "7500" "8000" "17060" "17061" "17090" "17000" "17001" "47000" "47500" "7000" "7500" "7500" "8000" "18060" "18061" "18090" "18000" "18001" "48000" "48500" "7000" "7500" "7500" "8000" "19060" "19061" "19090" "19000" "19001" "49000" "49500" "7000" "7500" "7500" "8000" "20060" "20061" "20090" "20000" "20001" "50000" "50500" "7000" "7500" "7500" "8000" "21060" "21061" "21090" "21000" "21001" "51000" "51500" "7000" "7500" "7500" "8000" "22060" "22061" "22090" "22000" "22001" "52000" "52500" "7000" "7500" "7500" "8000" "23060" "23061" "23090" "23000" "23001" "53000" "53500" "7000" "7500" "7500" "8000" "24060" "24061" "24090" "24000" "24001" "54000" "54500" "7000" "7500" "7500" "8000" "25060" "25061" "25090" "25000" "25001" "55000" "55500" "7000" "7500" "7500" "8000" "26060" "26061" "26090" "26000" "26001" "56000" "56500" "7000" "7500" "7500" "8000" "27060" "27061" "27090" "27000" "27001" "57000" "57500" "7000" "7500" "7500" "8000" "28060" "28061" "28090" "28000" "28001" "58000" "58500" "7000" "7500" "7500" "8000" "29060" "29061" "29090" "29000" "29001" "59000" "59500" "7000" "7500" "7500" "8000" "30060" "30061" "30090" "30000" "30001" "60000" "60500" "7000" "7500" "7500" "8000" "31060" "31061" "31090" "31000" "31001" "61000" "61500" "7000" "7500" "7500" "8000" "32060" "32061" "32090" "32000" "32001" "62000" "62500" "7000" "7500" "7500" "8000" "33060" "33061" "33090" "33000" "33001" "63000" "63500" "7000" "7500" "7500" "8000" "34060" "34061" "34090" "34000" "34001" "64000" "64500" "7000" "7500" "7500" "8000")
iptables_array=()

while IFS= read -r line ; do
	found=0
	for port in "${allports_array[@]}" ; do
		if [[ $line == *"$port"* ]] ; then
			found=1
			break
		fi
	done

	if [ $found == 0 ] ; then
		iptables_array+=("$line")
	fi
done <<< "$(iptables -S)"

ssipport="$(($sipport+1))"
iptables_success=1

iptables -F >/dev/null 2>&1 # Flush all iptables rules
if [ $? != 0 ] ; then iptables_success=0 ; fi

# Allow DNS
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT >/dev/null 2>&1
if [ $? != 0 ] ; then iptables_success=0 ; fi
iptables -A INPUT -p udp --sport 53 -j ACCEPT >/dev/null 2>&1
if [ $? != 0 ] ; then iptables_success=0 ; fi

## Allow SSH port 22
iptables -A INPUT -p tcp -m tcp --dport 22 -j ACCEPT >/dev/null 2>&1
if [ $? != 0 ] ; then iptables_success=0 ; fi
iptables -A OUTPUT -p tcp -m tcp --sport 22 -j ACCEPT >/dev/null 2>&1
if [ $? != 0 ] ; then iptables_success=0 ; fi

# Allow 3CX IPs
iptables -A OUTPUT -p tcp -d activation.3cx.com,erp.3cx.com,downloads.3cx.com,stun.3cx.com,stun2.3cx.com,stun3.3cx.com,webmeeting.3cx.net,51.254.74.8,151.80.125.99,158.69.11.10 -j ACCEPT
if [ $? != 0 ] ; then iptables_success=0 ; fi
iptables -A INPUT -p tcp -s activation.3cx.com,erp.3cx.com,downloads.3cx.com,stun.3cx.com,stun2.3cx.com,stun3.3cx.com,webmeeting.3cx.net,51.254.74.8,151.80.125.99,158.69.11.10 -j ACCEPT
if [ $? != 0 ] ; then iptables_success=0 ; fi

# Allow apt-get repositories
while IFS= read -r line ; do
        iptables -A OUTPUT -p tcp -d $line -j ACCEPT >/dev/null 2>&1
        if [ $? != 0 ] ; then iptables_success=0 ; fi
        iptables -A INPUT -p tcp -s $line -j ACCEPT >/dev/null 2>&1
        if [ $? != 0 ] ; then iptables_success=0 ; fi
done <<< "$(cat /etc/apt/sources.list | grep '^deb ' | cut -d'/' -f3)"

# Allow everything from localhost
iptables -A INPUT -i lo -j ACCEPT >/dev/null 2>&1
if [ $? != 0 ] ; then iptables_success=0 ; fi
iptables -A OUTPUT -d 127.0.0.1/32 -j ACCEPT >/dev/null 2>&1
if [ $? != 0 ] ; then iptables_success=0 ; fi
iptables -A OUTPUT -d localhost -j ACCEPT >/dev/null 2>&1
if [ $? != 0 ] ; then iptables_success=0 ; fi

# Add port rules
iptables -A INPUT -p tcp --dport $sipport -j ACCEPT >/dev/null 2>&1
if [ $? != 0 ] ; then iptables_success=0 ; fi
iptables -A INPUT -p udp --dport $sipport -j ACCEPT >/dev/null 2>&1
if [ $? != 0 ] ; then iptables_success=0 ; fi
iptables -A INPUT -p tcp --dport $ssipport -j ACCEPT >/dev/null 2>&1
if [ $? != 0 ] ; then iptables_success=0 ; fi
iptables -A INPUT -p udp --dport $ssipport -j ACCEPT >/dev/null 2>&1
if [ $? != 0 ] ; then iptables_success=0 ; fi
iptables -A INPUT -p tcp --dport $tunnelport -j ACCEPT >/dev/null 2>&1
if [ $? != 0 ] ; then iptables_success=0 ; fi
iptables -A INPUT -p udp --dport $tunnelport -j ACCEPT >/dev/null 2>&1
if [ $? != 0 ] ; then iptables_success=0 ; fi
iptables -A INPUT -p tcp --dport $http -j ACCEPT >/dev/null 2>&1
if [ $? != 0 ] ; then iptables_success=0 ; fi
iptables -A INPUT -p tcp --dport $https -j ACCEPT >/dev/null 2>&1
if [ $? != 0 ] ; then iptables_success=0 ; fi
iptables -A INPUT -p udp --dport $rtpintfirst:$rtpintlast -j ACCEPT >/dev/null 2>&1
if [ $? != 0 ] ; then iptables_success=0 ; fi
iptables -A INPUT -p udp --dport $rtpextfirst:$rtpextlast -j ACCEPT >/dev/null 2>&1
if [ $? != 0 ] ; then iptables_success=0 ; fi
iptables -A OUTPUT -p tcp --sport $sipport -j ACCEPT >/dev/null 2>&1
if [ $? != 0 ] ; then iptables_success=0 ; fi
iptables -A OUTPUT -p udp --sport $sipport -j ACCEPT >/dev/null 2>&1
if [ $? != 0 ] ; then iptables_success=0 ; fi
iptables -A OUTPUT -p tcp --sport $ssipport -j ACCEPT >/dev/null 2>&1
if [ $? != 0 ] ; then iptables_success=0 ; fi
iptables -A OUTPUT -p udp --sport $ssipport -j ACCEPT >/dev/null 2>&1
if [ $? != 0 ] ; then iptables_success=0 ; fi
iptables -A OUTPUT -p tcp --sport $tunnelport -j ACCEPT >/dev/null 2>&1
if [ $? != 0 ] ; then iptables_success=0 ; fi
iptables -A OUTPUT -p udp --sport $tunnelport -j ACCEPT >/dev/null 2>&1
if [ $? != 0 ] ; then iptables_success=0 ; fi
iptables -A OUTPUT -p tcp --sport $http -j ACCEPT >/dev/null 2>&1
if [ $? != 0 ] ; then iptables_success=0 ; fi
iptables -A OUTPUT -p tcp --sport $https -j ACCEPT >/dev/null 2>&1
if [ $? != 0 ] ; then iptables_success=0 ; fi
iptables -A OUTPUT -p udp --sport $rtpintfirst:$rtpintlast -j ACCEPT >/dev/null 2>&1
if [ $? != 0 ] ; then iptables_success=0 ; fi
iptables -A OUTPUT -p udp --sport $rtpextfirst:$rtpextlast -j ACCEPT >/dev/null 2>&1
if [ $? != 0 ] ; then iptables_success=0 ; fi

for rule in "${iptables_array[@]}" ; do
        iptables $rule >/dev/null 2>&1
	if [ $? != 0 ] ; then iptables_success=0 ; fi
done

# save rules
rm /etc/iptables3cx.up.rules >/dev/null 2>/dev/null
iptables-save | cat -n | sort -uk2 | sort -nk1 | cut -f2- > /etc/iptables3cx.up.rules
iptables -F
iptables-restore < /etc/iptables3cx.up.rules
rm /etc/network/if-pre-up.d/iptables3cx >/dev/null 2>/dev/null
echo -e '#!/bin/sh\n/sbin/iptables-restore < /etc/iptables3cx.up.rules' > /etc/network/if-pre-up.d/iptables3cx
chmod +x /etc/network/if-pre-up.d/iptables3cx

if [[ $iptables_success == 1 ]] ; then
	echo -e "${GREEN}OK${NC}"
else
	echo -e "${RED}FAILED${NC}"
fi


### Restart Services and check they started
echo -ne "  Starting 3CX Services................... "
start_stop_service "3CX*" 1
tcx_started=$?

start_stop_service "nginx" 1
nginx_started=$?

start_stop_service "postgresql" 1
db_started=$?

if [ $tcx_started -eq 1 ] && [ $nginx_started -eq 1 ] && [ $db_started -eq 1 ] ; then
        echo -e "${GREEN}OK${NC}"
else
        echo -e "${RED}FAILED${NC}"
fi


### Output Summary
echo -e "\n"
echo -e "${YELLOW}  =============================================="
echo -e "    Ports that need Forwarding on the Firewall"
echo -e "  ==============================================${NC}"
echo " "
echo -e "\tNew HTTP Port:       "$http" (TCP) - Do not open on firewall"
echo -e "\tNew HTTPS Port:      "$https" (TCP)"
echo -e "\tNew SIP Port:        "$sipport" (TCP/UDP)"
echo -e "\tNew Secure SIP Port: "$(($sipport+1))" (TCP/UDP)"
echo -e "\tNew Tunnel Port:     "$tunnelport" (TCP/UDP)"
echo -e "\tNew RTP Ports:       "$rtpextfirst"-"$rtpextlast" (UDP)"
echo -e "\n\n"

