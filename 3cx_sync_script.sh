#!/bin/bash

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
                                                XMLELEMENT(Name "Telephone", uvr.dn)
                                        )
                                )
                        ) as entry FROM users_view_reverse uvr
                ) AS xmlpb
        ) TO '/tmp/yealink_extensions.xml';
EOF

# Some black magic
sed -i 's/<\/DivinusIPPhoneDirectory>//g' /tmp/yealink_phonebook.xml
cat /tmp/yealink_extensions.xml >> /tmp/yealink_phonebook.xml && echo "</DivinusIPPhoneDirectory>" >> /tmp/yealink_phonebook.xml


