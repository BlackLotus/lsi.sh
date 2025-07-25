#!/usr/bin/env bash
#
# Calomel.org 
#     https://calomel.org/megacli_lsi_commands.html
#     LSI MegaRaid CLI 
#     lsi.sh @ Version 0.05
#
# description: MegaCLI script to configure and monitor LSI raid cards.

# TODO: cleaning the code

# Full path to the MegaRaid CLI binary
if [[ -e "$(which MegaCli 2>/dev/null)" ]]; then
    MegaCli=$(which MegaCli)
elif [[ -e "/usr/local/sbin/MegaCli64" ]]; then
    MegaCli="/usr/local/sbin/MegaCli64"
elif [[ -e "/opt/MegaRAID/MegaCli/MegaCli64" ]]; then
    MegaCli="/opt/MegaRAID/MegaCli/MegaCli64"
fi

if [[ -e "$(which nawk 2>/dev/null)" ]] ; then
    AWK=$(which nawk)
elif [[ -e "$(which awk 2>/dev/null)" ]] ; then
    AWK=$(which awk)
fi


if [ ! -x "${MegaCli}" ];then
    echo MegaCli is not installed or has the wrong permissions
    exit 1
fi

if [ ! -x "${AWK}" ];then
    echo awk is not installed or has the wrong permissions
    exit 1
fi

# The identifying number of the enclosure. Default for our systems is "8". Use
# "${MegaCli}64 -PDlist -a0 | grep "Enclosure Device"" to see what your number
# is and set this variable.
#ENCLOSURE="8"
if [[ -z $ENCLOSURE ]] ; then
  if [[ $(${MegaCli} -PDlist -a0 | ${AWK} '/Enclosure Device ID/ {print $NF}' | sort | uniq) -gt 0 ]] ; then
    ENCLOSURE=$(${MegaCli} -PDlist -a0 | ${AWK} '/Enclosure Device ID/ {print $NF}' | sort | uniq)
  fi
fi
if [[ $ENCLOSURE -gt 0 ]] ; then
  echo "Found ENCLOSURE Device ID: ${ENCLOSURE}" &>/dev/stderr
else
  echo "Could not determine ENCLOSURE Device ID for Adapter #0:" &>/dev/stderr
  ${MegaCli} -PDlist -a0 | ${AWK} '/Enclosure Device ID:/ || /Slot Number:/ || /DiskGroup:/ || /Firmware state:/ || /Media Type:/'
  exit
fi

## list disk/slot basic info:
#${MegaCli} -PDlist -a0 | ${AWK} '/^$/ || /WWN:/ || /Enclosure Device ID:/ || /Slot Number:/ || /DiskGroup:/ || /Firmware state:/ || /SAS Address/ || /Connected Port Number:/ || /Inquiry Data:/ || /Media Type:/'

if [[ $# == 0 ]] || [[ "$1" == "-h" ]] || [[ "$1" == "help" ]] || [[ "$1" == "--help" ]] ; then
  echo "
              OBPG  .:.  lsi.sh \$arg1 \$arg2
  -----------------------------------------------------
  status	= Status of Virtual drives (volumes)
  drives	= Status of hard drives
  ident \$slot	= Blink light on drive (need slot number)
  good \$slot	= Simply makes the slot \Unconfigured(good)\ (need slot number)
  replace \$slot = Replace \Unconfigured(bad)\ drive (need slot number)
  remove \$slot	= Remove hard drive from controller
  progress	= Status of drive rebuild
  errors	= Show drive errors which are non-zero
  bat		= Battery health and capacity
  batrelearn	= Force BBU re-learn cycle
  logs		= Print card logs
  checkNemail	= Check volume(s) and send email on raid errors
  allinfo	= Print out all settings and information about the card
  settime	= Set the raid card's time to the current system time
  setdefaults	= Set preferred default settings for new raid setup
  alarm		= Enable (1) or disable (0) the alarm sound
  jbod		= Enable (1) or diable (0) jbod
  raid0		= Set single harddisk to raid0
  create-jbod   = Set single harddisk to jbod
  clear-cache   = Clear Harddisk cache to be able to reinsert disk
  list-cache    = List all disks with preserved cache
  list-foreign  = List all foreign configurations on the controller (on error: ... does not have appropriate attribute...)
  clear-foreign = Clear all foreign configurations from the controller
"
  exit
fi

# General status of all RAID virtual disks or volumes and if PATROL disk check
# is running.
if [ "$1" = "status" ]
   then
      ${MegaCli} -LDInfo -Lall -aALL -NoLog
      echo "###############################################"
      ${MegaCli} -AdpPR -Info -aALL -NoLog
      echo "###############################################"
      ${MegaCli} -LDCC -ShowProg -LALL -aALL -NoLog
   exit
fi

# Shows the state of all drives and if they are online, unconfigured or missing.
if [ "$1" = "drives" ] ; then
      ${MegaCli} -PDlist -aALL -NoLog | grep -E 'Slot|state' | ${AWK} '/Slot/{if (x)print x;x="";}{x=(!x)?$0:x" -"$0;}END{print x;}' | sed 's/Firmware state://g'
   exit
fi

# Use to blink the light on the slot in question. Hit enter again to turn the blinking light off.
if [ "$1" = "ident" ]
   then
      ${MegaCli}  -PdLocate -start -physdrv["${ENCLOSURE}":$2] -a0 -NoLog
      logger "$(hostname) - identifying enclosure $ENCLOSURE, drive $2 "
      read -p "Press [Enter] key to turn off light..."
      ${MegaCli}  -PdLocate -stop -physdrv["${ENCLOSURE}":$2] -a0 -NoLog
   exit
fi

# When a new drive is inserted it might have old RAID headers on it. This
# method simply removes old RAID configs from the drive in the slot and make
# the drive "good." Basically, Unconfigured(bad) to Unconfigured(good). We use
# this method on our FreeBSD ZFS machines before the drive is added back into
# the zfs pool.
if [ "$1" = "good" ]
   then
      # set Unconfigured(bad) to Unconfigured(good)
      ${MegaCli} -PDMakeGood -PhysDrv["${ENCLOSURE}":$2] -a0 -NoLog
      # clear 'Foreign' flag or invalid raid header on replacement drive
      ${MegaCli} -CfgForeign -Clear -aALL -NoLog
   exit
fi

# Use to diagnose bad drives. When no errors are shown only the slot numbers
# will print out. If a drive(s) has an error you will see the number of errors
# under the slot number. At this point you can decided to replace the flaky
# drive. Bad drives might not fail right away and will slow down your raid with
# read/write retries or corrupt data. 
if [ "$1" = "errors" ]
   then
      echo "Slot Number: 0"; ${MegaCli} -PDlist -aALL -NoLog | grep -E -i 'error|fail|slot' | grep -E -v ' 0'
   exit
fi

# status of the battery and the amount of charge. Without a working Battery
# Backup Unit (BBU) most of the LSI read/write caching will be disabled
# automatically. You want caching for speed so make sure the battery is ok.
if [ "$1" = "bat" ]
   then
      ${MegaCli} -AdpBbuCmd -aAll -NoLog
   exit
fi

# Force a Battery Backup Unit (BBU) re-learn cycle. This will discharge the
# lithium BBU unit and recharge it. This check might take a few hours and you
# will want to always run this in off hours. LSI suggests a battery relearn
# monthly or so. We actually run it every three(3) months by way of a cron job.
# Understand if your "Current Cache Policy" is set to "No Write Cache if Bad
# BBU" then write-cache will be disabled during this check. This means writes
# to the raid will be VERY slow at about 1/10th normal speed. NOTE: if the
# battery is new (new bats should charge for a few hours before they register)
# or if the BBU comes up and says it has no charge try powering off the machine
# and restart it. This will force the LSI card to re-evaluate the BBU. Silly
# but it works.
if [ "$1" = "batrelearn" ]
   then
      ${MegaCli} -AdpBbuCmd -BbuLearn -aALL -NoLog
   exit
fi

# Use to replace a drive. You need the slot number and may want to use the
# "drives" method to show which drive in a slot is "Unconfigured(bad)". Once
# the new drive is in the slot and spun up this method will bring the drive
# online, clear any foreign raid headers from the replacement drive and set the
# drive as a hot spare. We will also tell the card to start rebuilding if it
# does not start automatically. The raid should start rebuilding right away
# either way. NOTE: if you pass a slot number which is already part of the raid
# by mistake the LSI raid card is smart enough to just error out and _NOT_
# destroy the raid drive, thankfully.
if [ "$1" = "replace" ]
   then
      logger "$(hostname) - REPLACE enclosure $ENCLOSURE, drive $2 "
      # set Unconfigured(bad) to Unconfigured(good)
      ${MegaCli} -PDMakeGood -PhysDrv["${ENCLOSURE}":$2] -a0 -NoLog
      # clear 'Foreign' flag or invalid raid header on replacement drive
      ${MegaCli} -CfgForeign -Clear -aALL -NoLog
      # set drive as hot spare
      ${MegaCli} -PDHSP -Set -PhysDrv ["${ENCLOSURE}":$2] -a0 -NoLog
      # show rebuild progress on replacement drive just to make sure it starts
      ${MegaCli} -PDRbld -ShowProg -PhysDrv ["${ENCLOSURE}":$2] -a0 -NoLog
   exit
fi

# Print all the logs from the LSI raid card. You can grep on the output.
if [ "$1" = "logs" ]
   then
      ${MegaCli} -FwTermLog -Dsply -aALL -NoLog
   exit
fi

# Use to query the RAID card and find the drive which is rebuilding. The script
# will then query the rebuilding drive to see what percentage it is rebuilt and
# how much time it has taken so far. You can then guess-ti-mate the
# completion time.
if [ "$1" = "progress" ] ; then
      DRIVE=$(${MegaCli} -PDlist -aALL -NoLog | grep -E 'Slot|state' | ${AWK} '/Slot/{if (x)print x;x="";}{x=(!x)?$0:x" -"$0;}END{print x;}' | sed 's/Firmware state://g' | grep -E build | ${AWK} '{print $3}')
      if [[ -z $DRIVE ]] ; then
        echo "No Drives in rebuild process"
      fi
      #${MegaCli} -PDRbld -ShowProg -PhysDrv ["${ENCLOSURE}":${DRIVE}] -a0 -NoLog
      OUTPUT=$(${MegaCli} -PDRbld -ShowProg -PhysDrv ["${ENCLOSURE}":${DRIVE}] -a0 -NoLog)
      OUTPUT=$(${MegaCli} -PDRbld -ShowProg -PhysDrv ["${ENCLOSURE}":${DRIVE}] -a0 -NoLog)
      PERC=$(echo ${OUTPUT}|${AWK} '{print $12}'|sed 's/%//')
      MIN=$(echo ${OUTPUT}|${AWK} '{print $14}')
      ETA=$((${MIN}*(100-${PERC})/${PERC}))
      HOUR=$((${ETA}/60))
      RMIN=$((${ETA}-60*${HOUR}))
      echo "$OUTPUT"
      echo "ETA is $ETA min (${HOUR}h ${RMIN}m)"
   exit
fi

# Use to check the status of the raid. If the raid is degraded or faulty the
# script will send email to the address in the $EMAIL variable. We normally add
# this method to a cron job to be run every few hours so we are notified of any
# issues.
if [ "$1" = "checkNemail" ]
   then
      EMAIL="raidadmin@localhost"

      # Check if raid is in good condition
      STATUS=$(${MegaCli} -LDInfo -Lall -aALL -NoLog | grep -E -i 'fail|degrad|error')

      # On bad raid status send email with basic drive information
      if [ "$STATUS" ]; then
         ${MegaCli} -PDlist -aALL -NoLog | grep -E 'Slot|state' | ${AWK} '/Slot/{if (x)print x;x="";}{x=(!x)?$0:x" -"$0;}END{print x;}' | sed 's/Firmware state://g' | mail -s $(hostname)' - RAID Notification' $EMAIL
      fi
fi

# Use to print all information about the LSI raid card. Check default options,
# firmware version (FW Package Build), battery back-up unit presence, installed
# cache memory and the capabilities of the adapter. Pipe to grep to find the
# term you need.
if [ "$1" = "allinfo" ]
   then
      ${MegaCli} -AdpAllInfo -aAll -NoLog
   exit
fi

# Update the LSI card's time with the current operating system time. You may
# want to setup a cron job to call this method once a day or whenever you
# think the raid card's time might drift too much. 
if [ "$1" = "settime" ]
   then
      ${MegaCli} -AdpGetTime -aALL -NoLog
      ${MegaCli} -AdpSetTime $(date +%Y%m%d) $(date +%H:%M:%S) -aALL -NoLog
      ${MegaCli} -AdpGetTime -aALL -NoLog
   exit
fi

# These are the defaults we like to use on the hundreds of raids we manage. You
# will want to go through each option here and make sure you want to use them
# too. These options are for speed optimization, build rate tweaks and PATROL
# options. When setting up a new machine we simply execute the "setdefaults"
# method and the raid is configured. You can use this on live raids too.
if [ "$1" = "setdefaults" ]
   then
      # Read Cache enabled specifies that all reads are buffered in cache memory. 
       ${MegaCli} -LDSetProp -Cached -LAll -aAll -NoLog
      # Adaptive Read-Ahead if the controller receives several requests to sequential sectors
       ${MegaCli} -LDSetProp ADRA -LALL -aALL -NoLog
      # Hard Disk cache policy enabled allowing the drive to use internal caching too
       ${MegaCli} -LDSetProp EnDskCache -LAll -aAll -NoLog
      # Write-Back cache enabled
       ${MegaCli} -LDSetProp WB -LALL -aALL -NoLog
      # Continue booting with data stuck in cache. Set Boot with Pinned Cache Enabled.
       ${MegaCli} -AdpSetProp -BootWithPinnedCache -1 -aALL -NoLog
      # PATROL run every 672 hours or monthly (RAID6 77TB @60% rebuild takes 21 hours)
       ${MegaCli} -AdpPR -SetDelay 672 -aALL -NoLog
      # Check Consistency every 672 hours or monthly
       ${MegaCli} -AdpCcSched -SetDelay 672 -aALL -NoLog
      # Enable autobuild when a new Unconfigured(good) drive is inserted or set to hot spare
       ${MegaCli} -AdpAutoRbld -Enbl -a0 -NoLog
      # RAID rebuild rate to 60% (build quick before another failure)
       ${MegaCli} -AdpSetProp \{RebuildRate -60\} -aALL -NoLog
      # RAID check consistency rate to 60% (fast parity checks)
       ${MegaCli} -AdpSetProp \{CCRate -60\} -aALL -NoLog
      # Enable Native Command Queue (NCQ) on all drives
       ${MegaCli} -AdpSetProp NCQEnbl -aAll -NoLog
      # Sound alarm disabled (server room is too loud anyways)
       ${MegaCli} -AdpSetProp AlarmDsbl -aALL -NoLog
      # Use write-back cache mode even if BBU is bad. Make sure your machine is on UPS too.
       ${MegaCli} -LDSetProp CachedBadBBU -LAll -aAll -NoLog
      # Disable auto learn BBU check which can severely affect raid speeds
       OUTBBU=$(mktemp /tmp/output.XXXXXXXXXX)
       echo "autoLearnMode=1" > $OUTBBU
       ${MegaCli} -AdpBbuCmd -SetBbuProperties -f $OUTBBU -a0 -NoLog
       rm -rf $OUTBBU
   exit
fi

# The LSI-Raid controller have an alarm that sounds when a hd is removed
# which may or not can cause harm/lasting damage to people in the vicinity.
# Use this option to disable or enable the alarm
if [ "$1" = "alarm" ];then
    if [ "$2" = "0" ];then
        ${MegaCli} -AdpSetProp AlarmDsbl -a0
    elif [ "$2" = "1" ];then
        ${MegaCli} -AdpSetProp AlarmEnbl -a0
    else
        echo "Either 0 (disable) or 1 (enable) is needed as a parameter"
    fi
fi

# Enables JBOD support (if it's supported by the controller which isn't a given)
if [ "$1" = "jbod" ];then
    if [ "$2" = "0" ];then
        ${MegaCli} -AdpSetProp EnableJBOD -a0
    elif [ "$2" = "1" ];then
        ${MegaCli} -AdpSetProp EnableJBOD -a0
    else
        echo "Either 0 (disable) or 1 (enable) is needed as a parameter"
    fi
fi

if [ "$1" = "raid0" ];then
# TODO: need logic beep ba boop
   if [ $# -gt 2 ];then
      echo Join
      echo ${@:2}
      r0=$(printf ",32:%s" "${@:3}")
      r0="[32:${2}${r3}]"
   elif [ $# -eq 2 ];then
      r0="[${ENCLOSURE}:$2]"
   else
      echo "Raid0 needs at least one disk"
   fi
   ${MegaCli} -CfgLdAdd -r0 ${r0} -a0
fi

if [ "$1" = "remove" ];then
    # set offline
    ${MegaCli} -PDOffline -PhysDrv "[${ENCLOSURE}:$2]" -a0
    # mark drive as missing to be able to remove the drive
    if [ $? -eq 0 ];then
        ${MegaCli} -PDMarkMissing -PhysDrv "[${ENCLOSURE}:$2]" -a0
    else
        echo "Failed to set drive as offline"
        exit 0
    fi
    # prepare controller for removal of drive/removes the driver from controller configuration
    # sets drive to unconfigured (good)
    if [ $? -eq 0 ];then
        ${MegaCli} -PdPrpRmv -PhysDrv "[${ENCLOSURE}:$2]" -a0
    else
        echo "Failed to remove drive $2"
    fi
fi

if [ "$1" = "create-jbod" ];then
   ${MegaCli} PDMakeJBOD -PhysDrv "[${ENCLOSURE}:$2]" -a0
fi

if [ "$1" = "clear-cache" ];then
   ${MegaCli} -DiscardPreservedCache  -L${2} -a0
fi

if [ "$1" = "list-cache" ];then
   ${MegaCli} -GetPreservedCacheList -a0
fi

if [ "$1" = "list-foreign" ];then
   ${MegaCli} -CfgForeign -Scan -a0
fi

if [ "$1" = "clear-foreign" ];then
   ${MegaCli} -CfgForeign -Clear -a0
fi
