#!/bin/bash
#
# Initialize virtual environment

source ~/miniconda2/etc/profile.d/conda.sh
conda activate asset_load

# Script Initializations

export NEWLOG_FILE="/home/asadev/amupdate/`date +%Y-%m-%d`.log"
echo "Release log: $NEWLOG_FILE"

export MYHOST=`hostname -s`

if [ ${MYHOST} = "ooiufs01" ] || [ ${MYHOST} = "cie-tuf-01" ];
then
   export EDEX_PREFIX="edex-data_request"
else
   export EDEX_PREFIX="edex-ooi"
fi
export EDEX_LOG_FILE=/home/asadev/uframes/ooi/uframe-1.0/edex/logs/${EDEX_PREFIX}-`date +%Y%m%d`.log
echo "Current EDEX log: $EDEX_LOG_FILE"

# Check out the proper release and do some cleanup

cd ~/amupdate
rm -rf 2019* asset-management/ generated_file_list processed_file_list vocabulary_update.log
git clone https://github.com/ooi-integration/asset-management.git
cd asset-management
export RELEASE=`git tag -l | tail -1`
git checkout ${RELEASE}
rm cruise/README.md

# Build the actual XLSX files

set -x
/bin/mkdir /home/asadev/amupdate/asset-management/tools/load/cruise
/home/asadev/amupdate/asset-management/tools/load/load_cruises.py /home/asadev/amupdate/asset-management/cruise /home/asadev/amupdate/asset-management/tools/load/cruise

/bin/mkdir /home/asadev/amupdate/asset-management/tools/load/deploy
/home/asadev/amupdate/asset-management/tools/load/load_deploy.py /home/asadev/amupdate/asset-management/deployment /home/asadev/amupdate/asset-management/tools/load/deploy

/bin/mkdir /home/asadev/amupdate/asset-management/tools/load/cal
/home/asadev/amupdate/asset-management/tools/load/load_cal.py /home/asadev/amupdate/asset-management/calibration /home/asadev/amupdate/asset-management/tools/load/cal

/bin/ls /home/asadev/amupdate/asset-management/tools/load/{cruise,deploy,cal} | /bin/sort | /bin/egrep -ve '^$|:' > /home/asadev/amupdate/generated_file_list
set +x

wc -l /home/asadev/amupdate/generated_file_list

echo " "
echo "tail -f ${EDEX_LOG_FILE} | tee ${NEWLOG_FILE} | egrep -ve '^INFO|^}|^[[:space:]]|^$'"
echo " "
echo "Press any key when ready"
echo " "
read blah

# Deactivate virtual environment

conda deactivate

if [ ${MYHOST} = "ooiufs01" ];
then
   export DBSERVER=192.168.145.202
elif [ ${MYHOST} = "cie-tuf-01" ];
then
   export DBSERVER=192.168.165.202
else
   export DBSERVER=localhost
fi
echo "Database server: ${DBSERVER}"

if [ ${MYHOST} = "ooiufs01" ] || [ ${MYHOST} = "cie-tuf-01" ];
then
   export EDEX_SOURCE_FILE="/home/asadev/uframes/ooi/bin/edex-server"
else
   export EDEX_SOURCE_FILE="/home/asadev/uframes/ooi_postgres/bin/edex-server"
fi
echo "EDEX Source File: ${EDEX_SOURCE_FILE}"

source ${EDEX_SOURCE_FILE}

# Run the psql command to truncate_asset_management.sql

psql -U awips metadata -h ${DBSERVER} -f /home/asadev/amupdate/ci-deploy-asset-management/truncate_asset_management.sql

# Load asset management data in proper order

set -x
/bin/mv -v /home/asadev/amupdate/asset-management/tools/load/cruise/* /home/asadev/uframes/ooi/uframe-1.0/edex/data/ooi/xasset_spreadsheet/
sleep 60
/bin/cp -v /home/asadev/amupdate/asset-management/bulk/array_bulk_load-AssetRecord.csv /home/asadev/uframes/ooi/uframe-1.0/edex/data/ooi/xasset_spreadsheet/
sleep 20
/bin/cp -v /home/asadev/amupdate/asset-management/bulk/eng_bulk_load-AssetRecord.csv /home/asadev/uframes/ooi/uframe-1.0/edex/data/ooi/xasset_spreadsheet/
sleep 20
/bin/cp -v /home/asadev/amupdate/asset-management/bulk/platform_bulk_load-AssetRecord.csv /home/asadev/uframes/ooi/uframe-1.0/edex/data/ooi/xasset_spreadsheet/
sleep 20
/bin/cp -v /home/asadev/amupdate/asset-management/bulk/node_bulk_load-AssetRecord.csv /home/asadev/uframes/ooi/uframe-1.0/edex/data/ooi/xasset_spreadsheet/
sleep 20
/bin/cp -v /home/asadev/amupdate/asset-management/bulk/sensor_bulk_load-AssetRecord.csv /home/asadev/uframes/ooi/uframe-1.0/edex/data/ooi/xasset_spreadsheet/
sleep 150
/bin/cp -v /home/asadev/amupdate/asset-management/bulk/unclassified_bulk_load-AssetRecord.csv /home/asadev/uframes/ooi/uframe-1.0/edex/data/ooi/xasset_spreadsheet/
sleep 150
/bin/mv -v /home/asadev/amupdate/asset-management/tools/load/deploy/* /home/asadev/uframes/ooi/uframe-1.0/edex/data/ooi/xasset_spreadsheet/
sleep 150
/bin/mv -v /home/asadev/amupdate/asset-management/tools/load/cal/* /home/asadev/uframes/ooi/uframe-1.0/edex/data/ooi/xasset_spreadsheet/
set +x

# Run the psql command to truncate_vocab.sql

psql -U awips metadata -h ${DBSERVER} -f /home/asadev/amupdate/ci-deploy-asset-management/truncate_vocab.sql

python /home/asadev/amupdate/ci-deploy-asset-management/vocab_ingest.py /home/asadev/amupdate/asset-management/vocab/vocab.csv | /usr/bin/tee /home/asadev/amupdate/vocabulary_update.log
/bin/grep "XIngestor: EDEX - Completed" ${NEWLOG_FILE} | /usr/bin/rev | /bin/cut -d\/ -f1 | /usr/bin/rev | /bin/sed -e 's/\]//'| /bin/sort | /bin/grep .xlsx >> /home/asadev/amupdate/processed_file_list
set -x
/usr/bin/md5sum /home/asadev/amupdate/{generated_file_list,processed_file_list}
/bin/grep CREATED /home/asadev/amupdate/vocabulary_update.log | /usr/bin/wc -l
set +x
/usr/bin/wc -l /home/asadev/amupdate/asset-management/vocab/vocab.csv

echo " "
echo "clear redis flask cache on UI server before logging in to ooinet"
echo " "
echo "Press any key when ready"
echo " "
read blah
