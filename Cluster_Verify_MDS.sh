#!/bin/bash
# declare vars
configs=( "static-route" "dns" "ntp" "snmp" "syslog" )

#login to the MDS and record SID
echo "Logging in Read-Only to the MDS level to retreive CMA list"
MDSSID=$(mgmt_cli -r true login read-only true --format json |jq -r '.sid')

#login and get all CMAs on the MDS
CMAS=$(mgmt_cli show-domains limit 250 --session-id ${MDSSID} --format json |jq -r  '.objects[].name')
CMA_Count=`echo "$CMAS" |wc -l `
echo "Total CMA Count is $CMA_Count"

echo "Logging out of Read-Only session to R80 MDS"
mgmt_cli logout --session-id $MDSSID --format json | jq -r '.message'

#Start Loop for each CMA
while read -r cma; do
echo ""
echo "#######################################"
echo "Logging into $cma"
SID=$(mgmt_cli -r true login domain "$cma" --format json |jq -r '.sid')

#Get Policy Packages
CLUSTERS=`mgmt_cli show-gateways-and-servers details-level full --format json --session-id $SID |jq '.objects[] | select(.type | contains("CpmiGatewayCluster")) |  {name: .name, members: ."cluster-member-names"  } '`
CLUSTERNAMES=`echo $CLUSTERS | jq -r '.name' `
CLUSTERCOUNT=`echo "$CLUSTERS" |jq -r '.name' | wc -l`
#Check to see if any Clusters are present
if [ $CLUSTERCOUNT -ne "0" ]; then

echo "CMA Contains $CLUSTERCOUNT Cluster(s)"
echo "-------------------------------------------"
echo  $CLUSTERNAMES |tr ' ' '\n'
echo "-------------------------------------------"
echo

while read -r name; do
echo "Verify $name"
SR=""
base64=()
 for command in "${configs[@]}"
   do
echo "Checking $command"
MEMBERS=`echo $CLUSTERS | jq -r "select(.name | contains(\"$name\")) | .members[]" `
while read -r member; do
      output=`mgmt_cli run-script script-name configucheck script 'clish -c "show configuration '$command'"' targets "$member" --format json --session-id $SID 2>\&1`
      if [ $? -eq 0 ]
        then
          base64+=(`echo $output |jq -r '.tasks[]."task-details"[].responseMessage'`)
        else
          echo "Error getting data from cluster $name member $member"
        fi
  output=""
done <<< "$MEMBERS"
 #echo
 #echo "## Checking for non-matching configuration with show configuration $command"
 verify=`echo "${base64[@]}" | tr ' ' '\n' | sort -u | wc -l`
 if [ $verify -ne "1" ]; then
   echo "Configurations do not match for $name!"
   MEM=1
   for ver in "${base64[@]}"
     do
       echo "Configuration for show configuration $command on #$MEM"
       echo
       echo "$ver" |base64 -di
       echo
       MEM=$[MEM +1]
     done
 fi
MEMBERS=""
base64=()
done
done <<< "$CLUSTERNAMES"
fi
echo "Logging out of $cma"
logoutcma=`mgmt_cli logout --session-id $SID`
if [ $? -ne 0 ]; then
  echo "Error logging out of CMA $cma"
fi

done <<< "$CMAS"
