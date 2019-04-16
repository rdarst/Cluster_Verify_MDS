#!/bin/bash
# declare vars
session="gw-sid.txt"
configs=( "static-route" "dns" "ntp" "snmp" "syslog" )

if [ -f "$session" ] ;
then
  echo "Removing old session file $session"
  rm $session
fi

#login to the CMA and gather all Clusters
mgmt_cli -r true login > $session 2>&1

#login and get all CMAs on the MDS
CMAS=`mgmt_cli show-domains --format json -s $session |jq '.objects[].name' |sed 's/\"//g'`
CMA_Count=`echo "$CMAS" |wc -l `
echo "Total CMA Count is $CMA_Count"

#Start Loop for each CMA
while read -r cma; do
echo ""
echo "#######################################"
echo "Logging into $cma"
mgmt_cli -r true login domain "$cma" > $cma-$session 2>&1

#Get Policy Packages
CLUSTERS=`mgmt_cli show-gateways-and-servers details-level full --format json -s $cma-$session |jq '.objects[] | select(.type | contains("CpmiGatewayCluster")) |  {name: .name, members: ."cluster-member-names"  } '`
CLUSTERNAMES=`echo $CLUSTERS | jq '.name' |sed 's/\"//g'`
CLUSTERCOUNT=`echo "$CLUSTERNAMES" | wc -l`
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
MEMBERS=`echo $CLUSTERS | jq "select(.name | contains(\"$name\")) | .members[]" |sed 's/\"//g' `
while read -r member; do
      output=`mgmt_cli run-script script-name configucheck script 'clish -c "show configuration '$command'"' targets "$member" --format json -s $cma-$session 2>\&1`
      if [ $? -eq 0 ]
        then
          base64+=(`echo $output |jq '.tasks[]."task-details"[].responseMessage' |sed 's/\"//g'`)
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

echo "Logging out of $cma"
logoutcma=`mgmt_cli logout -s $cma-$session 2>&1`
if [ $? -ne 0 ]; then
  echo "Error logging out of CMA $cma"
fi

if [ -f "$cma-$session" ] ;
then
  echo "Removing old session file $cma-$session"
  rm $cma-$session
fi

 done <<< "$CMAS"


#logout of the session
echo "Logging out of the MDS Session"
logout=`mgmt_cli logout -s $session 2>&1`
if [ $? -ne 0 ]; then
  echo "Error logging out of MDS"
fi


if [ -f "$session" ] ;
then
  echo "Removing old session file $session"
  rm $session
fi

