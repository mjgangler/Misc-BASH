#/bin/bash
set -euo pipefail
#set -eux pipefail
IFS=$'\n\t'
# Set Job Run name here for logging:
#export jobrun=mdw_deploy
#---------------------------------------------------------------
# mdw_deploy.sh
# Author: Kellyn Gorman
# Deploys Modern Data Warehouse Solution via Azure CLI to Azure
# Scripted- 04/24/2019
#---------------------------------------------------------------
# -e: immediately exit if anything is missing
# -o: prevents masked errors
# IFS: deters from bugs, looping arrays or arguments (e.g. $@)
#---------------------------------------------------------------
usage() { echo "Usage: $0 -i <subscriptionID> -g <groupname> -p <password> -pp <proxypassword> -s <servername> -ad <adfname> -as <aasname> -l <zone> -d <data> -b <brcksize>" 1>&2; exit 1; }
declare subscriptionID=""
declare groupname=""
declare password=""
declare proxypassword=""
declare servername=""
declare adfname=""
declare aasname=""
declare zone=""
declare data=""
declare brcksize=""

# Initialize parameters specified from command line
while getopts ":i:g:p:pp:s:ad:as:l:d:b:" arg; do
        case "${arg}" in
                i)
			subscriptionID=${OPTARG}
			;;
		g)
			groupname=${OPTARG}
			;;
		p)
			password=${OPTARG}
			;;
		pp)
			proxypassword=${OPTARG}
			;;
		s)
			servername=${OPTARG}
			;;
		ad)
			adfname=${OPTARG}
			;;
		as)
			aasname=${OPTARG}
			;;
		l)
			zone=${OPTARG}
			;;
		d)
			data=${OPTARG}
			;;
		b)
			brcksize=${OPTARG}
			;;
		esac
done
shift $((OPTIND-1))

#template Files to be used
templateFile1="template1.json"

if [ ! -f "$templateFile1" ]; then
        echo "$templateFile1 not found"
        exit 1
fi

templateFile2="template2.json"

if [ ! -f "$templateFile2" ]; then
        echo "$templateFile2 not found"
        exit 1
fi

#parameter files to be used
parametersFile1="parameters1.json"

if [ ! -f "$parametersFile1" ]; then
        echo "$parametersFile1 not found"
        exit 1
fi

parametersFile2="parameters2.json"

if [ ! -f "$parametersFile2" ]; then
        echo "$parametersFile2 not found"
        exit 1
fi

#Prompt for parameters is some required parameters are missing
#login to azure using your credentials

echo "Here is your Subscription ID Information"
az account show | grep id
if [[ -z "$subscriptionID" ]]; then
	echo "Copy and Paste the Subscription ID from above, without the quotes to be used:"
	read subscriptionID
	[[ "${subscriptionID:?}" ]]
fi

if [[ -z "$groupname" ]]; then
	echo "What is the name for the resource group to create the deployment in? Example: EDU_Group "
	echo "Enter your Resource Group name:"
	read groupname
	[[ "${groupname:?}" ]]
fi

if [[ -z "$password" ]]; then
	echo "Your database login will be sqladmin and you'll need a password for this login?"
        echo "Password must meet requirements for sql server, including capilatization, special characters.  Example: SQLAdm1nt3st1ng!"
	echo "Enter the login password "
	read password
	[[ "${password:?}" ]]
fi

if [[ -z "$proxypassword" ]]; then
        echo "This password is for the proxy user that will work wtih the objects in the databsaes. Special characters can cause issues, use only number and letters for this password.  Example: SQLAdm1nt3st1ng"
	echo "Enter a password for your database proxy login:"
	read proxypassword
	[[ "${proxypassword:?}" ]]
fi

if [[ -z "$servername" ]]; then
	echo "What would you like for the name of the server that will house your sql databases? Example hiedmdwsql1 "
	echo "Enter the server name:"
	read servername
	[[ "${servername:?}" ]]
fi

if [[ -z "$adfname" ]]; then
	echo "What would you like for the name of the Azure Data Factory.  This MUST be GLOBALLY UNIQUE, all small letters.  Example adfxxxx1 "
        echo "Enter the Azure Data Factory name:"
	read adfname
	[[ "${adfname:?}" ]]
fi

if [[ -z "$aasname" ]]; then
	echo "What would you like for the name of the Azure Analysis Service?  This MUST ALSO be GLOBALLY UNIQUE, all small letters.  Example xxxxxaas1 "
	echo "Enter the Azure Analysis Services name:"
	read aasname
	[[ "${aasname:?}" ]]
fi

if [[ -z "$zone" ]]; then
	echo "What will be the Azure location zone to create everything in? Choose from the list below: "
	az account list-locations | grep name | awk  '{print $2}'| tr -d \"\, | grep us | grep -v australia
	echo "Enter the location name:"
	read zone
	[[ "${zone:?}" ]]
fi

if [[ -z "$data" ]]; then
	echo "Will you be using the example data load vs. using your own data?  If using the example data, answer yes otherwise no if you wish to skip the example data."
	read data
	[[ "${data:?}" ]]
fi

if [[ -z "$brcksize" ]]; then
        #Create list of available Skus and DTUs for the location zone chosen.
	az sql db list-editions -l $zone --edition DataWarehouse -o table | grep True > wh.lst
        cat wh.lst | awk '{print "SKU:"$1,"DTU:"$4}' | tr -d \"\,
        echo "Choose a SKU from the above list:"
	read brcksize 
	[[ "${brcksize:?}" ]]
fi

# The ip address range that you want to allow to access your DB. 
# This rule is used by Visual Studio and SSMS to access and load data.  The firewall is dynamically offered for the workstation, but not for the Azure Cloud Shell.
# Added dynamic pull for IP Address for firewall rule 10/23/2018, KGorman
# Added a logfile and a static sqladmin for the database login.

echo "getting IP Address for Azure Cloud Shell for firewall rule"
export myip=$(curl http://ifconfig.me)
export startip=$myip
export endip=$myip
export logfile=./mdw_deploy.txt
export adminlogin=sqladmin
export schema='$schema'
export vnet=$servername"_vnet"l
export snet=$vnet"_snet"
export cap=$(cat wh.lst | grep $brcksize | awk '{print $4}' | tr -d \"\,)

# Update the JSON files with the correct resource names and zones.

cat >./$parametersFile1 <<EOF
{
    "$schema": "https://schema.management.azure.com/schemas/2015-01-01/deploymentParameters.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
        "name": {
            "value": "$adfname"
        },
        "location": {
            "value": "$zone"
        },
        "apiVersion": {
            "value": "2018-06-01"
        }
    }
}
EOF

cat >./$parametersFile2 <<EOF
{
    "$schema": "https://schema.management.azure.com/schemas/2015-01-01/deploymentParameters.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
        "name": {
            "value": "$aasname"
        },
        "location": {
            "value": "$zone"
        },
        "sku": {
            "value": "B1"
        },
        "backupBlobContainerUri": {
            "value": ""
        },
        "managedMode": {
            "value": 1
        }
    }
}
EOF

#---------------------------------------------------------------
# Customers should only update the variables in the top of the script, nothing below this line.
#---------------------------------------------------------------

# Unzip data load files
rm -rf ./hied_data
unzip hied_data.zip
mv ./hied_data/* .

# Set default subscription ID if not already set by customer.
# Created on 10/14/2018
az account set --subscription $subscriptionID
 
echo "Create a resource group"
az group create \
	--name $groupname \
	--location $zone

echo "Create VNet"
az network vnet create \
  --name $vnet \
  --resource-group $groupname \
  --subnet-name $snet

echo "Create Routing Table to Support"
az network route-table create --resource-group $groupname  --name MyRouteTable


az network route-table route create --resource-group $groupname --route-table-name MyRouteTable -n MDWRoute \
   --next-hop-type Internet --address-prefix 0.0.0.0/0

az network vnet subnet update \
  --vnet-name $vnet  \
  --name $snet \
  --resource-group $groupname \
  --route-table MyRouteTable

# Create a logical server in the resource group
az sql server create \
	--name $servername \
	--resource-group $groupname \
	--location $zone  \
	--admin-user $adminlogin \
	--admin-password $password


# Configure a firewall rule for the server
az sql server firewall-rule create \
	--resource-group $groupname \
	--server $servername \
	-n AllowYourIp \
	--start-ip-address $startip \
	--end-ip-address $endip

az configure --defaults sql-server=$servername
# Create a database for the staging database
# Enhancement-  add dyanmice for capacity/sku here, too.
az sql db create \
	--resource-group $groupname \
	--name HiEd_Staging \
        --service-objective S0 \
        --capacity 10 \
	--zone-redundant false 

# Create a database  for the data warehouse
# Enhancement-  add dynamic for capacity/sku here, too
az sql db create \
        --resource-group $groupname \
        --name HiEd_DW \
        --service-objective S0 \
        --capacity 10 \
        --zone-redundant false 

# Create Azure SQL Warehouse    
az sql db create \
    --resource-group $groupname \
    --name AzureDW \
    --edition DataWarehouse \
    --service-objective $brcksize \
    --collation SQL_Latin1_General_CP1_CI_AS \
    --capacity $cap \
    --zone-redundant false

# Create Databricks 
virtualenv -p /usr/bin/python2.7 bricks-cli

source bricks-cli/bin/activate

pip install databricks-cli

# Enhancement-  find a way to dynamically populate the values for both prompts.
echo "You will now be prompted for two values to enter-"
echo "the name of databricks host- naming example for yours would be https://$zone.azuredatabricks.net"
echo "name your token a security password that you will remember."
databricks configure --token 


# Install the Azure DevOps Extension to be used with deployment of Azure DevOps ADF Pipelines
az extension add --name azure-devops

# Deploy Azure Analysis Server and ADF
# Added 10/16/2018, updated 4/8/2019 to use dynamic population of json files.
# Start deployment
(
        set -x
        az group deployment create --resource-group "$groupname" --template-file "$templateFile1" --parameters "@${parametersFile1}"
)

if [ $?  == 0 ];
 then
        echo "Azure Data Factory has been successfully deployed"
fi
 
# Enhancement- find a way to populate the admin value for AAS
echo "You will be requested for the Azure administrator for the Analysis server: Example-  kegorman@microsoft.com"

(
        set -x
        az group deployment create --resource-group "$groupname" --template-file "$templateFile2" --parameters "@${parametersFile2}"
)

if [ $?  == 0 ];
 then
        echo "Azure Analysis Server has been successfully deployed"
fi

echo "This Completes Part I, the physical resources deployment, Part II will now begin."

# Populate Database Objects
# Added data load and logic for sample data, 4/08/2019,  KGorman
# Added proxy login to support scripts and added check log for post deploy. 10/25/2018
# Updated to no longer just DDL, but added data to be loaded as part of DW and Staging data
# DataWarehouse
echo "Part II logs into the SQL Server and deploys the logical objects, support structures and data if requested."

if [ "$data" == "yes" ];
then
  echo "Loading Example Schema and Data-  This will take about an hour to perform the data load."
  sqlcmd -U $adminlogin -S"${servername}.database.windows.net" -P "$password" -d master -Q "CREATE LOGIN HigherEDProxyUser WITH PASSWORD = '${proxypassword}'; "
  sqlcmd -U $adminlogin -S "${servername}.database.windows.net" -P "$password" -d HiEd_DW -i "hied_dw.sql"
  sqlcmd -U $adminlogin -S "${servername}.database.windows.net" -P "$password" -d HiEd_Staging -i "hied_staging_enroll.sql"
  sqlcmd -U $adminlogin -S "${servername}.database.windows.net" -P "$password" -d HiEd_Staging -i "hied_staging_data.sql"
  echo "Data and object build for both databases is complete.  Counts for views in last steps to log should have counts in each."
else
  echo "Request is for schema only, no data, the objects, no data will be built inside the databases."
  sqlcmd -U $adminlogin -S"${servername}.database.windows.net" -P "$password" -d master -Q "CREATE LOGIN HigherEDProxyUser WITH PASSWORD = '${proxypassword}'; "
  sqlcmd -U $adminlogin -S "${servername}.database.windows.net" -P "$password" -d HiEd_DW -i "mdw_ddl_dw.sql"
  sqlcmd -U $adminlogin -S "${servername}.database.windows.net" -P "$password" -d HiEd_Staging -i "mdw_ddl_staging.sql"
  echo "Object Build for both databases is complete.  No data was loaded, so zero rows are expected in counts of views"
fi
# Part II is now complete, onto Part III, logging

# Part III- Log all information from the deployment to the log file
echo "This is your SQL Server, Admin User and Password:" > $logfile
echo $servername $adminlogin $password >> $logfile
echo "This is your ADF, Analysis Server and the Proxy Password for the AAS:"
echo $adfname $aasname $proxypassword
echo "This is your Azure location zone:" $zone >> $logfile
echo "This is the subscription deployed to and the Firewall IP:" >> $logfile 
echo $subscriptionID $myip >> $logfile
#echo "This is your databricks cluster info:"
#echo databricks clusters list >> $logfile
echo "------------------------------------------------------------------------------------------------------------"
# Check for data and push to output file
sqlcmd -U $adminlogin -S "${servername}.database.windows.net" -P "$password" -d HiEd_Staging -i "ck_views.sql" > $logfile

echo "All Steps in the deployment are now complete."
