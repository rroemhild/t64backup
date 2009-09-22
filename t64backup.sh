#!/bin/sh

# Tru64 Unix backup script using vdump and mt to write backups to tape
# For help, run this script with the -h switch.

# Copyright (c) 2003, Rafael Roemhild <rafael@roemhild.de>
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#   * Redistributions of source code must retain the above copyright notice,
#     this list of conditions and the following disclaimer.
#   * Redistributions in binary form must reproduce the above copyright
#     notice, this list of conditions and the following disclaimer in the
#     documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
# PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER
# OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# ROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


VERSION="0.1d"
LAST_MODIFICATION="2003-10-06"
PROG="t64backup.sh"

### CONFIG FILE: maybe you will change this
CONFIG_FILE="./t64backup.conf"

# Read the config file
. "$CONFIG_FILE" || exit 1

##
# Function: print_help()
##
print_help()
{
cat <<End_Of_Help
Usage: $0 [options]
 Options:
	-c		Check tape for label and hostname and quit
	-p		Only print the label from tape to stdout
	-w		Only write label to tape
	-x		Print the tape device status

	-d "/etc"	Directories to backup (whitespace separated)
	-f "/etc/motd"  Files to backup (whitespace separated)
	-m "/ /usr"	Mountpoints to backup (whitespace separated)

	-e "dbbkup.sh"	Programm to execute bevor backup

	-D "day"	Set tape day
	-H "hostname"	Set tape hostname	
	-t "device"	Set tape device (/dev/ntape/tape0_d0)

	-M		Prevent sending e-mail report (Default: send)
	-R		Prevent rewind tape (Default: rewind)
	-S		Prevent write to syslog (Default: write)
	-U		Prevent unload tape (Default: unload)
	-I		Prevent tape check of day and hostname (Default: check)

	-h		Print this help text
	-r		Print short intro howto restore backup
	-v		Verbose output
	-V		Print Version info

Copyright (c) 2003, Rafael Roemhild <rafael@roemhild.de>
This script is licensed under the BSD license.
End_Of_Help
}

##
# Function: print_version()
##
print_version()
{
	echo "$PROG version $VERSION last modified on $LAST_MODIFICATION"
	echo "Copyright (c) 2003, Rafael Roemhild <rafael@roemhild.de>"
	echo "This script is licensed under the BSD license."
}

##
# Funktion: print_restore_howto()
##
print_restore_howto()
{
cat <<End_Of_Howto_Restore_Backup

Short instruction howto restore files from backup tape
======================================================

Insert the tape you'll restore from and execute t64backup.sh with the \'-p\'
switch to print the tape label of the inserded tape. You see alot of
information on which date and host the backup has been taken. Now you have
to look at the tape file positions on wich your Dump is stored.
When you need to restore a file from /usr/users, you have to set the tape
to the file position /usr/users is stored on. \'mt fsf #\' is the command
syntax for this job. After the tape is on the right file position you
can enter an interactive restoring of files by executing the command
\`vrestore -i -f <tapedev>\`. Now you're on a restore shell and you can
type ? for instruction howto use it.

Good luck.

End_Of_Howto_Restore_Backup
}

##
# Function: rc_check()
#
# Desc: checks the return code an writes to syslog()
# Usage: rc_check $? "Text"
##
rc_check()
{
	if [ "$1" = "0" ]; then
		syslog DEBUG "$2"
	else
		syslog ERROR "$3"
	fi
	return $1
}

##
# Function: syslog()
#
# Desc: Write script information to syslog and/or to the term
# Usage: syslog <facility> "text to log"
##
syslog()
{
	[ "$VERBOSE" = "1" ] && echo "`date '+%b %e %H:%M:%S'`: $2"
	[ "$SYSLOG" = "1" ] && $LOGGER -t $PROG -p $FACILITY.$1 $2
}

##
# Function: tapectl()
#
# Usage: tapectl (online|offline|rewind|unload|status)
##
tapectl()
{
	case $1 in
		'online')
			$mt -f $TAPE_DEV online > /dev/null
			RC=$?
			return $RC
			;;
		'offline')
			$mt -f $TAPE_DEV offline > /dev/null
			RC=$?
			return $RC
			;;
		'rewind')
			$mt -f $TAPE_DEV rewind > /dev/null
			RC=$?
			return $RC
			;;
		'unload')
			$mt -f $TAPE_DEV unload > /dev/null
			RC=$?
			return $RC
			;;
		'status')
			TSTATUS="`$mt -f $TAPE_DEV status | grep "unit_status" | awk '{print $2}'`"
			if [ "$TSTATUS" = "0x101" ]; then
				return "0" # online
			elif [ "$TSTATUS" = "0x102" ]; then
				return "1" # offline
			fi
			;;
	esac
}

##
# Function: read_tape_label()
#
# Desc: Reads the first point (Label) from tape into <tmp-file>
# Usage: read_tape_label [print]
##
read_tape_label()
{
	syslog DEBUG "Rewinding tape"
	tapectl rewind || panic "In function: read_tape_label"
	syslog DEBUG "Reading tape label"
	cat $TAPE_DEV > $TEMP_OLD_LABEL
	return $?
}

##
# Function: write_tape_label()
#
# Desc: Writes the label though the tape
# Usage: write_tape_label
##
write_tape_label()
{
	syslog DEBUG "Rewinding tape"
	tapectl rewind || panic "In function: write_tape_label"
	syslog DEBUG "Writing tape label to $TAPE_DEV"
	cat < $TEMP_NEW_LABEL > $TAPE_DEV
	return $?
	rc_check $RC "Tape label written" "Error writing tape label" || panic
}

##
# Function: check_tabe_label()
#
# Desc: checks the label match hostname and day of backup
##
check_tape_label()
{
	syslog INFO "Check tape match against host and day"
	TDAY="`grep '^Day:' $TEMP_OLD_LABEL | awk '{print $2}'`"
	syslog DEBUG "Tapeday is $TDAY"
	THOSTNAME="`grep '^Hostname:' $TEMP_OLD_LABEL | awk '{print $2}'`"
	syslog DEBUG "Tapehost is $THOSTNAME"
	if [ "$TDAY" = "$DAYNAME" -a "$THOSTNAME" = "$HOSTNAME" ]; then
		return 0
	else
		return 1
	fi
}

##
# Function: bytes2human()
#
# Usage: bytes2human bytes
##
bytes2human()
{
	LENGTH="`expr length $1`"
	if [ $LENGTH -gt 7 ]; then
		VALUE="`expr $1 / 1024 / 1024` (mb)"
	elif [ $LENGTH -gt 3 -a $1 -gt 1024 ]; then
		VALUE="`expr $1 / 1024` (kb)"
	else
		VALUE="$1 (b)"
	fi
	echo $VALUE
}

##
# Function: panic()
#
# Desc: panic() removes first all $TEMP* temporarie files
#       and quit with exit 1. If status report is enabled
#       it send a short panic mail to all recipients.
# Usage: panic ["text"]
##
panic()
{
	[ -n "$1" ] && syslog ERROR "$1"
	if [ $MAIL_REPORT -eq 1 ]; then
		syslog ERROR "Sending error mail"
		SUBJECT="$HOSTNAME: Error while backup"
		echo "" > $TEMP_REPORT
		echo "     P A N I C" >> $TEMP_REPORT
		echo "" >> $TEMP_REPORT
		echo "Something went wrong during backup process" >> $TEMP_REPORT
		echo "Please take a look at the logfile" >> $TEMP_REPORT
		if [ -n "$1" ]; then
			echo "" >> $TEMP_REPORT
			echo "Panic text: $1" >> $TEMP_REPORT
		fi
		mail_report $TEMP_REPORT
	fi
	syslog DEBUG "Removing tempfiles"
	rm -rf $TEMP*
	syslog ERROR "PANIC: No regular exit"
	exit 1
}

##
# Function: cleanup_and_exit()
##
cleanup_and_exit()
{
	syslog DEBUG "Cleanup tempfiles"
	rm -rf $TEMP*
	syslog INFO "Finished. Exit."
	exit 0
}

##
# Function: status_mail()
#
# Desc: This function send an status mail to recipients
#	via sendmail(8)
# Usage: status_mail <body temp file> <temp of executed cmd>
##
mail_report()
{
	TIME_STAMP="`date +%H%M%S`"
	[ -n "$2" ] && RCPT="$2"

	# Write mail header to file
	echo "From: $FROM" >> $TEMP_MAIL
	echo "To: `echo $RCPTS | sed 's/ /; /g'`" >> $TEMP_MAIL
	echo "Subject: $SUBJECT" >> $TEMP_MAIL
	echo "X-Mailer: t64backup-script-status-mail" >> $TEMP_MAIL
	echo "Message-ID: <$TIME_STAMP-t64backup@`hostname`>" >> $TEMP_MAIL
	echo "Mime-Version: 1.1" >> $TEMP_MAIL
	echo "Content-Type: multipart/mixed; boundary=\"19811231$TIME_STAMP\"" \
		>> $TEMP_MAIL
	echo "This is a mime formated message." >> $TEMP_MAIL
	echo "" >> $TEMP_MAIL
	echo "--19811231$TIME_STAMP" >> $TEMP_MAIL
	echo "Content-Type: text/plain" >> $TEMP_MAIL
	echo "Content-Disposition: inline" >> $TEMP_MAIL
	echo "" >> $TEMP_MAIL
	cat $1 >> $TEMP_MAIL
	echo "" >> $TEMP_MAIL
	echo "(brought to you by $PROG version $VERSION)" >> $TEMP_MAIL
	echo "" >> $TEMP_MAIL

	# Attech exec_cmd logfile if exist
	if [ -r "$2" ]; then
	echo "--19811231$TIME_STAMP" >> $TEMP_MAIL
	echo "Content-Type: text/plain" >> $TEMP_MAIL
	echo "Content-Disposition: attachment; filename=\"exec_log.txt\"" \
		>> $TEMP_MAIL
	echo "" >> $TEMP_MAIL
	cat $2 >> $TEMP_MAIL
	echo "" >> $TEMP_MAIL
	fi

	# end of mailsource
	echo "--19811231$TIME_STAMP--" >> $TEMP_MAIL

	# Sending the mail with sendmail(8)
	for RCPT in $RCPTS; do
		cat $TEMP_MAIL | $MTA "$RCPT" &> /dev/null
		RC=$?
		rc_check $RC "Mail deliverd to $RCPT" \
			 "Error delivering mail to $RCPT"
	done
}

##
# Get options
##
set -- `getopt cd:e:f:hm:prt:wvxD:H:IMRSUV $*`
if [ $? != 0 ]; then
	exit 1
fi

while [ $1 != -- ]; do
	case $1 in
	-c) # check tape
		SYSLOG=0
		NO_EXEC=1
		SWITCH_c=1;;
	-d) # dirs to save
		BKUP_DIRS=$2
		shift;;
	-e) # execute
		EXEC_CMD=$2
		shift;;
	-f) # files to save
		BKUP_FILES=$2
		shift;;
	-h) # print help
		print_help
		exit 0;;
	-m) # mount points to save
		BKUP_MNTS=$2
		shift;;
	-p) # print tape label
		SYSLOG=0
		NO_EXEC=1
		SWITCH_p=1;;
	-r) # print restore howto
		print_restore_howto
		exit 0;;
	-t) # tape dev
		TAPE_DEV=$2
		shift;;
	-w) # only label tape
		SYSLOG=0
		NO_EXEC=1
		TAPE_CHECK=0
		BKUP_MNTS=""; BKUP_FILES=""; BKUP_DIRS=""
		SWITCH_w=1;;
	-v) # verbose flag
		VERBOSE=1;;
	-x) # Print the tape dev stat
		SYSLOG=0
		NO_EXEC=1
		SWITCH_x=1;;
	-D) # set day
		DAYNAME=$2
		shift;;
	-H) # set hostname
		HOSTNAME=$2
		shift;;
	-I) # no check of right tape
		TAPE_CHECK=0;;
	-M) # Send mail report
		MAIL_REPORT=0;;
	-R) # rewind tape
		TAPE_REWIND=0;;
	-U) # unload tape
		TAPE_UNLOAD=0;;
	-V) # print version
		print_version
		exit 0;;
	esac
	shift # next switch
done
shift

syslog INFO "$PROG version $VERSION startet"

# Create temp files
touch $TEMP_MAIL $TEMP_NEW_LABEL $TEMP_OLD_LABEL $TEMP_REPORT $TEMP_REPORT_TMP
RC=$?
rc_check $RC "Tempfiles touched" "Unable to touch tempfiles" || panic

StartDATE="`date '+%Y.%m.%d at %H:%M:%S'`"

##
# Execute another command first
##
if [ -n "$EXEC_CMD" -a -z "$NO_EXEC" ];then
	syslog INFO "Execute command \"$EXEC_CMD\""
	echo "\nCommand: $EXEC_CMD\n" >> $TEMP_EXEC
	$EXEC_CMD > $TEMP_EXEC
	RC=$?
	rc_check $RC "Command $EXEC_CMD executed" "Error executing $EXEC_CMD"
	if [ $? -gt 0 ]; then
		echo "\n--- The exit status was not NULL ---" >> $TEMP_EXEC
		echo "--- Maybe something goes wrong   ---" >> $TEMP_EXEC
	fi
fi

##
# Tape management
##

# Check tape dev stat and position
tapectl status
RC=$?
if [ "$RC" = "0" ]; then
	[ -n "$SWITCH_x" ] && VERBOSE=1
	syslog DEBUG "Tape is online"
	[ -n "$SWITCH_x" ] && VERBOSE=0 && cleanup_and_exit
   else
	[ -n "$SWITCH_x" ] && VERBOSE=1
	syslog DEBUG "Tape seems to be offline"
	[ -n "$SWITCH_x" ] && VERBOSE=0 && cleanup_and_exit
	syslog DEBUG "Try to bring tape online"
	tapectl online
	RC=$?
	rc_check $RC "Tape is now online" "Can not online tape" || panic
fi

# Read tape label
if [ $TAPE_CHECK -eq 1 ]; then
    read_tape_label
fi
RC=$?
rc_check $RC "Old tape label written to $TEMP_OLD_LABEL" \
		"Error reading old tape label" || panic "Error reading old label"
if [ -n "$SWITCH_p" -a -n "$SWITCH_c" ]; then
	cat $TEMP_OLD_LABEL
	echo
   elif [ -n "$SWITCH_p" ]; then
	cat $TEMP_OLD_LABEL
	cleanup_and_exit
fi

# Check tape label
check_tape_label
RC=$?
if [ "$RC" = "0" -a $TAPE_CHECK -eq 1 ]; then
	[ -n "$SWITCH_c" -o -n "$SWITCH_w" ] && VERBOSE=1
	syslog DEBUG "Tape label match"
	[ -n "$SWITCH_c" -o -n "$SWITCH_w" ] && cleanup_and_exit
  else
	if [ $TAPE_CHECK -eq 1 ]; then
		[ -n "$SWITCH_c" -o -n "$SWITCH_w" ] && VERBOSE=1
		syslog ERROR "Tape label doesn't match"
		syslog ERROR "Hostday is $DAYNAME"
		syslog ERROR "Hostname is $HOSTNAME"
		[ -n "$SWITCH_c" ] && cleanup_and_exit
		panic "Tape label doesn't match"
	  elif [ $TAPE_CHECK -eq 0 ]; then
		[ -n "$SWITCH_c" -o -n "$SWITCH_w" ] && VERBOSE=1
		syslog ERROR "Tape label doesn't match. Continue."
		syslog ERROR "Hostday is $DAYNAME"
		syslog ERROR "Hostname is $HOSTNAME"
		[ -n "$SWITCH_c" ] && cleanup_and_exit
		syslog DEBUG "Continue with wrong labeld tape"
	fi
fi

# Generate new tape label
syslog DEBUG "Generate new tape label"
TAPEDATE="`date '+%Y-%m-%d'`"
TAPETIME="`date '+%H:%M'`"
TAPEHARDWARE="`/usr/sbin/uerf -r 300|grep AlphaServer|head -1|awk '{print $1,$2,$3}'`"
TAPESYSTEM="`uname -s`"
TAPEOSVERSION="`uname -r` (`uname -v`)"

cat > $TEMP_NEW_LABEL <<End_of_label_head
============================================================
	--------------
	| TAPE LABEL |
	--------------

	$PROG version $VERSION

Day: $DAYNAME
Date: $TAPEDATE	Time: $TAPETIME

Hostname: $HOSTNAME		Hardware: $TAPEHARDWARE
System: $TAPESYSTEM		OS-Version: $TAPEOSVERSION

File positions on tape:
	#0 = tape label
End_of_label_head

# Add the backup sets as positions to new tape label
SETS="$BKUP_MNTS $BKUP_DIRS $BKUP_FILES"
SET_COUNT="1"
for POINT in $SETS; do
	echo "\t#${SET_COUNT} = ${POINT}" >> $TEMP_NEW_LABEL
	SET_COUNT="`expr $SET_COUNT + 1`"
done

# Write the new tape label bottom
cat >> $TEMP_NEW_LABEL <<End_of_label_bottom

For a short manual howto restore a backup execute
$PROG with the -r switch.
============================================================
End_of_label_bottom

# Write new tape label
write_tape_label
RC=$?
[ -n "$SWITCH_w" ] && VERBOSE=1
rc_check $RC "Tape label written" "Error writing tape label" || panic
[ -n "$SWITCH_w" ] && cleanup_and_exit

##
# Begin with backup
##

# Backup mountpoints/devices
if [ -n "$BKUP_MNTS" ]; then
	for B in $BKUP_MNTS; do
		syslog INFO "Backup -> $B"
		echo "[$B]" >> $TEMP_REPORT_TMP
		echo "Start:`date '+%d%m%Y-%H:%M:%S'`" >> $TEMP_REPORT_TMP
		$vdump -0uf $TAPE_DEV $B >> $TEMP_REPORT_TMP 2>&1
		RC=$?
		rc_check $RC "$B backuped" "Errors while backup $B" || \
			echo "-problems" >> $TEMP_REPORT_TMP
		echo "Stop:`date '+%d%m%Y-%H:%M:%S'`" >> $TEMP_REPORT_TMP
		echo "" >> $TEMP_REPORT_TMP
	done
fi

# Backup directories
if [ -n "$BKUP_DIRS" ]; then
	for B in $BKUP_DIRS; do
		syslog INFO "Backup -> $B"
		echo "[$B]" >> $TEMP_REPORT_TMP
		echo "Start:`date '+%d%m%Y-%H:%M:%S'`" >> $TEMP_REPORT_TMP
		$vdump -0uf $TAPE_DEV -D $B >> $TEMP_REPORT_TMP 2>&1
		RC=$?
		rc_check $RC "$B backuped" "Errors while backup $B" || \
			echo "-problems" >> $TEMP_REPORT_TMP
		echo "Stop:`date '+%d%m%Y-%H:%M:%S'`" >> $TEMP_REPORT_TMP
		echo "" >> $TEMP_REPORT_TMP
	done
fi

# Backup files
if [ -n "$BKUP_FILES" ]; then
	for B in $BKUP_FILES; do
		syslog INFO "Backup -> $B"
		echo "[$B]" >> $TEMP_REPORT_TMP
		echo "Start:`date '+%d%m%Y-%H:%M:%S'`" >> $TEMP_REPORT_TMP
		$vdump -0uf $TAPE_DEV -D $B >> $TEMP_REPORT_TMP 2>&1
		RC=$?
		rc_check $RC "$B backuped" "Errors while backup $B" || \
			echo "-problems" >> $TEMP_REPORT_TMP
		echo "Stop:`date '+%d%m%Y-%H:%M:%S'`" >> $TEMP_REPORT_TMP
		echo "" >> $TEMP_REPORT_TMP
	done
fi

syslog INFO "Backup finished"

# Rewind tape
if [ "$TAPE_REWIND" = "1" ]; then
	syslog DEBUG "Rewinding tape"
	tapectl rewind
	RC=$?
	rc_check $RC "Tape rewindet" "Can not rewind tape"
else
	syslog INFO "No tape rewind due to -R switch"
fi

# Unload tape
if [ "$TAPE_UNLOAD" = "1" ]; then
	syslog DEBUG "Unloading tape"
	tapectl unload
	RC=$?
	rc_check $RC "Tape unloaded" "Can not unload tape"
else
	syslog INFO "No tape unload due to -U switch"
fi

StopDATE="`date '+%Y.%m.%d at %H:%M:%S'`"

# Skript ends here if no status report
if [ $MAIL_REPORT -eq 0 ]; then
	syslog INFO "No status report"
	cleanup_and_exit
fi

##
# Generate status report
##

 syslog DEBUG "Generate report"
# Write report to file
echo "Backup report for Day \"$DAYNAME\".\n" > $TEMP_REPORT
echo "Day: $DAYNAME\nDate: $TAPEDATE\n" >> $TEMP_REPORT
echo "Hostname: $HOSTNAME\t\tHardware: $TAPEHARDWARE" >> $TEMP_REPORT
echo "System: $TAPESYSTEM\t\tOS-Version: $TAPEOSVERSION\n" >> $TEMP_REPORT
echo "Backup start: $StartDATE" >> $TEMP_REPORT
echo "Backup end  : $StopDATE\n" >> $TEMP_REPORT
echo "Backup statistics:\n" >> $TEMP_REPORT
printf "%-12s %-8s %-8s %-12s %-6s %-6s\n" "Path" "Start" "End" "Size" "Dirs" "Files" >> $TEMP_REPORT
echo "==========================================================" >> $TEMP_REPORT

# Generate Statistics
syslog DEBUG "Generate report stats"
cat $TEMP_REPORT_TMP | while read LINE; do
	[ -z "$LINE" ] && continue
	case $LINE in
		\[*\])
			REPORT_PATH="`echo $LINE | sed 's/\[//;s/\]//'`"
			fin=0
			continue
			;;
		Start:*)	
			REPORT_START="`echo $LINE | cut -d '-' -f2`" 
			;;
		dev/fset*)
			REPORT_DEV_FSET="`echo $LINE | sed 's/^.*:.//'`"
			;;
		type*)
			REPORT_TYPE="`echo $LINE | sed 's/^.*:.//'`"
			;;
		vdump:*)
			if `echo $LINE | awk '{ if ( $0 !~ /vdump:.Dumping.*.bytes,.*.directories,.*.files$/ ) exit 1}'`; then
				BYTES="`echo $LINE | cut -d ' ' -f3`"
				REPORT_SIZE="`bytes2human $BYTES`"
				REPORT_DIRS="`echo $LINE | cut -d ' ' -f5`"
				REPORT_FILES="`echo $LINE | cut -d ' ' -f7`"
				continue
			fi
			;;
		Stop:*)
			REPORT_STOP="`echo $LINE | cut -d '-' -f2`"
			printf "%-12s %-8s %-8s %-12s %-6d %-6d\n" "${REPORT_PATH}" "${REPORT_START}" "${REPORT_STOP}" "${REPORT_SIZE}" "${REPORT_DIRS}" "${REPORT_FILES}" >> $TEMP_REPORT
			continue
			;;
	esac
done

##
# End
##
syslog DEBUG "Sending report"
mail_report $TEMP_REPORT $TEMP_EXEC
cleanup_and_exit
# end
