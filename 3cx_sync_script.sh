#!/bin/bash

cat << \EOF | sudo su postgres -c "psql -d database_single"
COPY(
SELECT
XMLFOREST( xmlpb.entry as "DivinusIPPhoneDirectory" )
FROM (
SELECT 
XMLCONCAT (
XMLELEMENT ( NAME "Title", 'Phonelist' ),
XMLELEMENT ( NAME "Prompt", 'Prompt' ),
XMLAGG ( 
XMLELEMENT ( 
NAME "DirectoryEntry", 
XMLELEMENT( Name "Name", 
case 
when (pb.company = '') IS FALSE AND pb.lastname != '' and pb.firstname != '' then pb.company || ' - ' || pb.lastname || ', ' || pb.firstname
when (pb.company = '') IS FALSE AND pb.lastname != '' and pb.firstname = '' then pb.company || ' - ' || pb.lastname
when (pb.company = '') IS FALSE AND pb.lastname = '' and pb.firstname = '' then pb.company
when (pb.company = '') IS FALSE AND pb.lastname = '' and pb.firstname != '' then pb.company || ' - ' || pb.firstname
when (pb.company = '') IS NOT FALSE AND pb.lastname != '' and pb.firstname != '' then pb.lastname || ', ' || pb.firstname
when (pb.company = '') IS NOT FALSE AND  pb.lastname != '' and pb.firstname = '' then pb.lastname
end ),
XMLELEMENT( Name "Telephone", pb.pv_an3 ),
XMLELEMENT( Name "Telephone",
case
when not exists ( SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'phonebook' AND COLUMN_NAME = 'pv_an4') then ''
when exists ( SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'phonebook' AND COLUMN_NAME = 'pv_an4')  then pb.pv_an4
end ),
XMLELEMENT( Name "Telephone", pb.phonenumber ),
XMLELEMENT( Name "Telephone", pb.pv_an1 ),
XMLELEMENT( Name "Telephone", pb.pv_an2 )
) 
)
) as entry 
FROM
phonebook pb
WHERE fkidtenant = 1
) AS xmlpb
) TO '/tmp/yealink_phonebook.xml';
EOF



# do not add a trailing slash!
provisioning_location="/var/lib/3cxpbx/Instance1/Data/Http/Interface/provisioning"


if [ $(find $provisioning_location -maxdepth 1 -type d | wc -l) -gt 2 ]; 
then
	echo '- oh noes! there is more than 1 folder in /provisioning/!';
	echo '- exitting now, so I dont cause any chaos!';
	exit 1;
else
	echo "- looking good, 1 folder exists in /provisioning/";
	folder_name=$( ls -d -tr $provisioning_location/*/ | head -1)
	echo "- moving exported phonebook to provisioning folder now..."
	mv /tmp/yealink_phonebook.xml $folder_name/yealink_phonebook.xml
	chown phonesystem:phonesystem $folder_name/yealink_phonebook.xml
	echo "- finished! :)"
fi
 
