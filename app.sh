#!/bin/dash
: '''
Copyright (c) 2020-21 etkaar <https://github.com/etkaar>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE
OR OTHER DEALINGS IN THE SOFTWARE.
'''
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# dependencies: nftables

# Change working directory
ABSPATH="$(cd "$(dirname "$0")"; pwd -P)"
cd $ABSPATH

CONF_PATH="$ABSPATH/conf"
PRESETS_PATH="$CONF_PATH/presets"
TMP_PATH="$ABSPATH/.tmp"

AVAILABLE_PRESETS_PATH="$PRESETS_PATH/available"
ENABLED_PRESETS_PATH="$PRESETS_PATH/enabled"

ADDITIONAL_RULES_FILE="$CONF_PATH/additional_rules.txt"

# Ensure only root runs this command
if [ ! `whoami` = "root" ]
then
	>&2 echo "You need to run this command as root (or use sudo)."
	exit 1
fi

# Create dirs if not exist
for CHECKPATH in "$TMP_PATH"
do
	if [ ! -d $CHECKPATH ]
	then
		mkdir $CHECKPATH
	fi
done

# Set permissions for internal scripts
for FILE in `ls ./inc`
do
	chmod 0750 ./inc/$FILE
done

# Command
CMD=$1

case "$CMD" in

	# Show full ruleset
	show)
		nft list ruleset -nn
	;;
	
	# For crontabs only
	cron)
		$0 update
	;;
	
	# Used after reboot
	init)
		$0 full-reload
	;;
	
	# Update whitelists or do a
	# full reload of all rules
	update|full-reload)

		# Ensure default preset is enabled
		if ! ls $ENABLED_PRESETS_PATH/*default* >/dev/null 2>&1
		then
			>&2 echo "No default preset enabled."
			exit 1
		fi

		# Check if IPv6 is enabled
		IPV6_ENABLED=1

		if ./presets.sh status default ipv4-only >/dev/null 2>&1
		then
			IPV6_ENABLED=0
		fi
		
		# Whitelist and blacklist presets
		IP_VERSIONS="all"
		
		if [ "$IPV6_ENABLED" = 0 ]
		then
			IP_VERSIONS=4
		fi
		
		# Update only (reloads whitelist and blacklist)
		if [ "$CMD" = "update" ]
		then
		
			if [ "`nft list ruleset`" = "" ]
			then
				>&2 echo "No ruleset loaded. Run \"${0} full-reload\"."
				exit 1
			fi
		
			# Update whitelist and blacklist
			if ! ./inc/whiteblacklists.sh whitelist update $IP_VERSIONS >/dev/null
			then
				>&2 echo "ERROR: Failed to generate whitelist."
				exit 1
			fi
			
			if ! ./inc/whiteblacklists.sh blacklist update $IP_VERSIONS >/dev/null
			then
				>&2 echo "ERROR: Failed to generate blacklist."
				exit 1
			fi
			
		elif [ "$CMD" = "full-reload" ]
		then

			# Temporary ruleset file which is later
			# used to atomically reload the ruleset
			TMP_RULESET_FILE="$TMP_PATH/ruleset"
			
			echo -n "" > $TMP_RULESET_FILE
			
			echo "#!/usr/sbin/nft -f" >> $TMP_RULESET_FILE
			echo "flush ruleset" >> $TMP_RULESET_FILE

			# Apply all presets
			for PRESET in `ls $ENABLED_PRESETS_PATH`
			do
				echo "" >> $TMP_RULESET_FILE
				cat $ENABLED_PRESETS_PATH/$PRESET >> $TMP_RULESET_FILE
			done
			
			# Re-generate whitelist and blacklist
			if ! ./inc/whiteblacklists.sh whitelist generate $IP_VERSIONS >> $TMP_RULESET_FILE
			then
				>&2 echo "ERROR: Failed to generate whitelist."
				exit 1
			fi
			
			if ! ./inc/whiteblacklists.sh blacklist generate $IP_VERSIONS >> $TMP_RULESET_FILE
			then
				>&2 echo "ERROR: Failed to generate blacklist."
				exit 1
			fi
			
			# Append additional rules
			cat $ADDITIONAL_RULES_FILE >> $TMP_RULESET_FILE
			
			if nft -f $TMP_RULESET_FILE
			then
				rm $TMP_RULESET_FILE
			fi
		
		fi
		
	;;
	
	*)
		>&2 echo "Usage: ${0} {show|update|full-reload}"
		exit 1
    ;;
	
esac

exit 0
