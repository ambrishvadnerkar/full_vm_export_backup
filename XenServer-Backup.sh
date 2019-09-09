#!/bin/bash
###########################################


STORE_BY="SERVER_NAME" # either SERVER_NAME or POOL_NAME or HYPERVISOR_NAME
TMP_UUID_FILE=/tmp/xen-uuids.txt
NFS_SERVER_IP="NFS_SREVER_IP"
MOUNTPOINT="/NFS_DRIVE_NAME"
FILE_LOCATION_ON_NFS="/home/backups/vms_full/daily"
COMPRESS="YES" # either YES or NO to compress
DAYS_TO_KEEP="7"
LOG="/var/log/XenServer-Backup_daily.log"
###########################################
DATE=$(date +%m-%d-%Y)
shopt -s nocasematch
SECONDS=0
echo "Backup:: Script Start -- $(date +%Y%m%d_%H%M)" >> $LOG

if [[ $COMPRESS = "YES" ]]; then
   echo "Compression is ON" >> $LOG
elif [[ $COMPRESS = "NO" ]]; then
   echo "Compression is OFF" >> $LOG
else
  echo "$COMPRESS not set correctly!\n"
fi

if [[ $STORE_BY = "SERVER_NAME" ]]; then
  DIR=$(echo $HOSTNAME)
elif [[ $STORE_BY = "POOL_NAME" ]]; then
  DIR=$(xe pool-list params=name-label --minimal)
else
  echo "$STORE_BY not set correctly!\n"
  exit 1
fi

[[ -d $MOUNTPOINT ]] || mkdir -p $MOUNTPOINT
mount -t nfs $NFS_SERVER_IP:$FILE_LOCATION_ON_NFS $MOUNTPOINT
if [ ! $? -eq 0 ]; then
  echo "Mount command failed!\n"
  exit 2
fi


BACKUPPATH=$MOUNTPOINT/$DIR/$DATE
mkdir -p $BACKUPPATH

if [ ! -d $BACKUPPATH ]; then
  echo "$BACKUPPATH not found!\n"
  umount -f $MOUNTPOINT
  umount -f $MOUNTPOINT
  exit 3
fi

xe vm-list is-control-domain=false is-a-snapshot=false | grep uuid | cut -d":" -f2 > $TMP_UUID_FILE

if [ ! -f $TMP_UUID_FILE ]; then
  echo "$TMP_UUID_FILE not found!\n"
  umount -f $MOUNTPOINT
  umount -f $MOUNTPOINT
  exit 4
fi

while read VMUUID
do
  VMNAME=$(xe vm-list uuid=$VMUUID | grep name-label | cut -d":" -f2 | sed 's/^ *//g')
  echo "$VMNAME" >> $LOG
  SNAPUUID=$(xe vm-snapshot uuid=$VMUUID new-name-label="SNAPSHOT-$VMUUID-$DATE")
  xe template-param-set is-a-template=false ha-always-run=false uuid=$SNAPUUID
  xe vm-export vm=$SNAPUUID filename="$BACKUPPATH/$VMNAME-$DATE.xva"
  if [[ $COMPRESS = "YES" ]]; then
    gzip $BACKUPPATH/$VMNAME-$DATE.xva
  fi
  xe vm-uninstall uuid=$SNAPUUID force=true
done < $TMP_UUID_FILE

find $MOUNTPOINT -mtime +$DAYS_TO_KEEP -type f -print -delete >> $LOG
find $MOUNTPOINT -type d -empty -print -delete >> $LOG
umount -f $MOUNTPOINT
umount -f $MOUNTPOINT

echo "Backup :: Script End -- $(date +%Y%m%d_%H%M)" >> $LOG
echo "Elapsed Time :: $(($SECONDS / 3600))h:$((($SECONDS / 60) % 60))m:$(($SECONDS % 60))s" >> $LOG

