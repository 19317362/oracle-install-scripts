#!/bin/bash
#
# DB Software Installation script
# Installs Oracle Grid Infrastructure and Database software
#
# Prerequisites:
# - Installed package "oracle-rdbms-server-12cR1-preinstall.rpm"
# - Executed oracle-rdbms-server-12cR1-preinstall-verify
# - Copied V*.zip packages (GI and DB software) to $ORACLE_INSTALLFILES_LOCATION
# - (Optional) # passwd oracle
#
# Simon Krenger <simon@krenger.ch>
# August 2013

export ORACLE_USER=oracle
export ORACLE_HOME=/u01/app/oracle/product/12.1.0/db_1
export ORACLE_BASE=/u01/app/oracle

export ORACLE_BASE_MOUNTS="/u01 /u02 /u03"
export ORACLE_INVENTORY_LOCATION=/etc/oraInventory
export ORACLE_INSTALLFILES_LOCATION=/home/oracle

export GRID_USER=oracle
export GRID_BASE=/u01/app/grid
export GRID_HOME=/u01/app/grid/product/12.1.0/grid_1

export ORACLE_MEMORY_SIZE=800M

unset LANG

### Script start

usage()
{
cat << EOF
usage: $0 [-h] [-u ORACLE_USER] [-m ORACLE_MEMORY_SIZE] [-i INSTALLFILES_DIR]

This script is used to install Oracle Grid Infrastructure and the Oracle
database software. The default settings will install the database software
according to the OFA standard.

OPTIONS:
   -h      Show this message
   -i      Folder that contains the installation ZIP files. Defaults to
           "/home/oracle/"
   -u      User that owns the Oracle software installation. Defaults to "oracle"
   -m      Aggregate shared memory size for all databases on this machine.
           Defaults to 800M.
EOF
}

# Parse arguments
while getopts "hi:u:m:" OPTION
do
     case $OPTION in
         h)
             usage
             exit 1
             ;;
         i)
             ORACLE_INSTALLFILES_LOCATION=$OPTARG
             ;;
	 u)
	     ORACLE_USER=$OPTARG
	     ;;
	 m)
	     ORACLE_MEMORY_SIZE=$OPTARG
	     ;;
         ?)
             usage
             exit
             ;;
     esac
done

# Check if run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

id $ORACLE_USER 2>/dev/null
if [ $? -eq 0 ]; then
	echo "User $ORACLE_USER found, proceeding..."
else
	echo "User $ORACLE_USER not found, aborting..."
	exit 1
fi

# Check necessary programs installed
which unzip
if [ $? -eq 0 ]; then
	echo "unzip is installed"
else
	echo "unzip not found, aborting..."
	exit 1
fi

which oracle-rdbms-server-12cR1-preinstall-verify
if [ $? -eq 0 ]; then
	echo "oracle-rdbms-server-12cR1-preinstall-verify is installed"
else
	echo "oracle-rdbms-server-12cR1-preinstall-verify not found, aborting..."
	exit 1
fi

which ntpdate
if [ $? -eq 0 ]; then
	echo "ntpdate is installed"
else
	echo "ntpdate not found, aborting..."
	exit 1
fi

if [ -d "$ORACLE_INSTALLFILES_LOCATION" ]; then
	echo "$ORACLE_INSTALLFILES_LOCATION exists"
	if [ `ls -l $ORACLE_INSTALLFILES_LOCATION/V385*-01_*of2.zip | wc -l` -eq 4 ]; then
		echo "Correct amount of ZIPs found, proceeding..."
	else
		echo "No or wrong installation ZIP files found."
		echo "Please make sure V38501-01_1of2.zip, V38501-01_2of2.zip, V38500-01_1of2.zip and V38500-01_2of2.zip are placed in $ORACLE_INSTALLFILES_LOCATION"
		exit 1
	fi
else
	echo "$ORACLE_INSTALLFILES_LOCATION does not exist, aborting..."
	exit 1
fi


# Prepare filesystem
mkdir -p ${ORACLE_BASE_MOUNTS}
mkdir -p ${ORACLE_HOME}
mkdir -p ${ORACLE_INVENTORY_LOCATION}
chown -R ${ORACLE_USER}:oinstall ${ORACLE_BASE_MOUNTS}
chown -R ${ORACLE_USER}:oinstall ${ORACLE_BASE}
chown -R ${ORACLE_USER}:oinstall ${ORACLE_INVENTORY_LOCATION}

# Prepare groups and users
groupadd asmdba
groupadd asmoper
groupadd dgdba
groupadd bckpdba
groupadd kmdba
usermod -a -G dba,asmoper,asmdba,dgdba,bckpdba,kmdba ${ORACLE_USER}


# Modify NTPD
service ntpd stop
echo 'OPTIONS="-u ntp:ntp -x -p /var/run/ntpd.pid"' > /etc/sysconfig/ntpd
ntpdate pool.ntp.org
service ntpd start

# Modify /etc/hosts
mv /etc/hosts /etc/hosts.original
cat /etc/hosts.original | awk '$1~"^127.0.0.1|^::1"{$2="'`hostname -s`' '`hostname`' "$2}1' OFS="\t" > /etc/hosts

# Modify /etc/fstab
mv /etc/fstab /etc/fstab.original
cat /etc/fstab.original | awk '$3~"^tmpfs$"{$4="size='$ORACLE_MEMORY_SIZE'"}1' OFS="\t" > /etc/fstab
mount -t tmpfs shmfs -o size=$ORACLE_MEMORY_SIZE /dev/shm


## Unpack files
cd ${ORACLE_INSTALLFILES_LOCATION}

# Grid infrastructure
unzip ${ORACLE_INSTALLFILES_LOCATION}/V38501-01_1of2.zip
unzip ${ORACLE_INSTALLFILES_LOCATION}/V38501-01_2of2.zip
chown -R ${ORACLE_USER}:oinstall ${ORACLE_INSTALLFILES_LOCATION}/grid
#TODO: Check if everything worked as expected and only remove if no errors occured
#rm ${ORACLE_INSTALLFILES_LOCATION}/V38501-01_1of2.zip ${ORACLE_INSTALLFILES_LOCATION}/V38501-01_2of2.zip

# Oracle database software
unzip ${ORACLE_INSTALLFILES_LOCATION}/V38500-01_1of2.zip
unzip ${ORACLE_INSTALLFILES_LOCATION}/V38500-01_2of2.zip
chown -R ${ORACLE_USER}:oinstall ${ORACLE_INSTALLFILES_LOCATION}/database
#TODO: Check if everything worked as expected and only remove if no errors occured
#rm  ${ORACLE_INSTALLFILES_LOCATION}/V38500-01_1of2.zip ${ORACLE_INSTALLFILES_LOCATION}/V38500-01_2of2.zip


# Installation of Grid Infrastructure
cd ${ORACLE_INSTALLFILES_LOCATION}/grid
echo "oracle.install.responseFileVersion=/oracle/install/rspfmt_crsinstall_response_schema_v12.1.0
ORACLE_HOSTNAME="`hostname`"
INVENTORY_LOCATION="${ORACLE_INVENTORY_LOCATION}"
SELECTED_LANGUAGES=en
oracle.install.option=CRS_SWONLY
ORACLE_BASE="${GRID_BASE}"
ORACLE_HOME="${GRID_HOME}"
oracle.install.asm.OSDBA=dba
oracle.install.asm.OSOPER=asmoper
oracle.install.asm.OSASM=asmdba
oracle.installer.autoupdates.option=SKIP_UPDATES" > ${ORACLE_INSTALLFILES_LOCATION}/grid_install.rsp

echo "Now installing Grid Infrastructure. This may take a while..."
su ${ORACLE_USER} -c 'cd ${ORACLE_INSTALLFILES_LOCATION}/grid; ./runInstaller -silent -waitForCompletion -responseFile ${ORACLE_INSTALLFILES_LOCATION}/grid_install.rsp'

# Register OraInventory
${ORACLE_INVENTORY_LOCATION}/orainstRoot.sh

# Configure GI (run this as root)
${GRID_HOME}/root.sh
${GRID_HOME}/perl/bin/perl -I${GRID_HOME}/perl/lib -I${GRID_HOME}/crs/install ${GRID_HOME}/crs/install/roothas.pl

echo "Finished installing Grid Infrastructure."

# Installation of Database Software
cd  ${ORACLE_INSTALLFILES_LOCATION}/database
rm -rf ${ORACLE_INSTALLFILES_LOCATION}/grid

echo "oracle.install.responseFileVersion=/oracle/install/rspfmt_dbinstall_response_schema_v12.1.0
oracle.install.option=INSTALL_DB_SWONLY
ORACLE_HOSTNAME="`hostname`"
UNIX_GROUP_NAME=oinstall
INVENTORY_LOCATION="${ORACLE_INVENTORY_LOCATION}"
SELECTED_LANGUAGES=en
ORACLE_HOME="${ORACLE_HOME}"
ORACLE_BASE="${ORACLE_BASE}"
oracle.install.db.InstallEdition=EE
oracle.install.db.DBA_GROUP=dba
oracle.install.db.BACKUPDBA_GROUP=bckpdba
oracle.install.db.DGDBA_GROUP=dgdba
oracle.install.db.KMDBA_GROUP=kmdba
SECURITY_UPDATES_VIA_MYORACLESUPPORT=false
DECLINE_SECURITY_UPDATES=true
oracle.installer.autoupdates.option=SKIP_UPDATES" > ${ORACLE_INSTALLFILES_LOCATION}/db_install.rsp

echo "Now installing Database software. This may take a while..."
su ${ORACLE_USER} -c 'cd ${ORACLE_INSTALLFILES_LOCATION}/database; ./runInstaller -silent -waitForCompletion -responseFile ${ORACLE_INSTALLFILES_LOCATION}/db_install.rsp'

# Configure DB software
${ORACLE_HOME}/root.sh

# Cleanup
cd
rm -rf ${ORACLE_INSTALLFILES_LOCATION}/database

echo "Installation finished. Check the logfiles for errors"

