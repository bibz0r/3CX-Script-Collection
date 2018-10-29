#!/bin/bash

##########################################
#                                        #
#	Which Column is which Number	 #
#					 #
#        column     |   nubmertype       #
#                   |                    #
#       phonenumber |   mobile           #
#       pv_an0      |   mobile2          #
#       pv_an1      |   private          #
#       pv_an2      |   private2         #
#       pv_an3      |   business         #
#       pv_an4      |   business2        #
#                                        #
##########################################

# Remove old files
rm -rf /tmp/yealink_extensions.xml
rm -rf /tmp/yealink_phonebook.xml

# Export phonebook entries
cat << \EOF | sudo su postgres -c "psql -d database_single"
        COPY(
                SELECT XMLFOREST(xmlpb.entry as "DivinusIPPhoneDirectory") FROM(
                        SELECT XMLCONCAT(
                                XMLELEMENT(NAME "Title", 'Phonelist'),
                                XMLELEMENT(NAME "Prompt", 'Prompt'),
                                XMLAGG(
                                        XMLELEMENT(
                                                NAME "DirectoryEntry",
                                                XMLELEMENT(Name "Name",
                                                        case when(pb.company = '') IS FALSE AND pb.lastname != ''
                                                        and pb.firstname != ''
                                                        then pb.company || ' - ' || pb.lastname || ', ' || pb.firstname when(pb.company = '') IS FALSE AND pb.lastname != ''
                                                        and pb.firstname = ''
                                                        then pb.company || ' - ' || pb.lastname when(pb.company = '') IS FALSE AND pb.lastname = ''
                                                        and pb.firstname = ''
                                                        then pb.company when(pb.company = '') IS FALSE AND pb.lastname = ''
                                                        and pb.firstname != ''
                                                        then pb.company || ' - ' || pb.firstname when(pb.company = '') IS NOT FALSE AND pb.lastname != ''
                                                        and pb.firstname != ''
                                                        then pb.lastname || ', ' || pb.firstname when(pb.company = '') IS NOT FALSE AND pb.lastname != ''
                                                        and pb.firstname = ''
                                                        then pb.lastname end),
                                                XMLELEMENT(Name "Telephone", pb.pv_an3),
                                                XMLELEMENT(Name "Telephone",
                                                        case when not exists(SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'phonebook'
                                                                AND COLUMN_NAME = 'pv_an4') then ''
                                                        when exists(SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'phonebook'
                                                                AND COLUMN_NAME = 'pv_an4') then pb.pv_an4 end),
                                                XMLELEMENT(Name "Telephone", pb.phonenumber),
                                                XMLELEMENT(Name "Telephone", pb.pv_an1),
                                                XMLELEMENT(Name "Telephone", pb.pv_an2)
                                        )
                                )
                        ) as entry FROM phonebook pb WHERE pb.fkidtenant = 1
                ) AS xmlpb
        ) TO '/tmp/yealink_phonebook.xml';
EOF


# Export assigned extensions, since those are not saved in the phonebook
cat << \EOF | sudo su postgres -c "psql -d database_single"
        COPY(
                SELECT * FROM(
                        SELECT XMLCONCAT(
                                XMLAGG(
                                        XMLELEMENT(
                                                NAME "DirectoryEntry",
                                                XMLELEMENT(Name "Name", uv.display_name),
                                                XMLELEMENT(Name "Telephone", uv.dn)
                                        )
                                )
                        ) as entry FROM users_view uv
                ) AS xmlpb
        ) TO '/tmp/yealink_extensions.xml';
EOF

# Some black magic
sed -i 's/<\/DivinusIPPhoneDirectory>//g' /tmp/yealink_phonebook.xml
cat /tmp/yealink_extensions.xml >> /tmp/yealink_phonebook.xml && echo "</DivinusIPPhoneDirectory>" >> /tmp/yealink_phonebook.xml
rm -rf /tmp/yealink_extensions.xml

#Further cleanup will be done by caller script
