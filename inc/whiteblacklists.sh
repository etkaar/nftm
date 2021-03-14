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

# Change working directory
ABSPATH="$(cd "$(dirname "$0")"; pwd -P)"
cd $ABSPATH

CONF_PATH="$ABSPATH/../conf"

# Ensure only root runs this command
if [ ! `whoami` = "root" ]
then
	>&2 echo "You need to run this command as root (or use sudo)."
	exit 1
fi

func_GET_CURRENT_LIST_LINE() {
	if [ "$TYPE" = "whitelist" ]
	then
		echo "$HOSTNAME_SUBNET_OR_ADDRESS : enabled : $IS_ENABLED, protocol : $PROTOCOL, ports : {$PORTS}"
	elif [ "$TYPE" = "blacklist" ]
	then
		echo "$HOSTNAME_SUBNET_OR_ADDRESS : enabled : $IS_ENABLED"
	fi
}

# Check host is a subnet
func_HOST_IS_SUBNET() {
	HOSTNAME_SUBNET_OR_ADDRESS=$1
	
	CHECK=`echo $HOSTNAME_SUBNET_OR_ADDRESS | grep '/'`
	
	if [ "$CHECK" = "" ]
	then
		return 1
	else
		return 0
	fi
}

# Get IPv4 address from hostname (returns the IPv4 address if address was supplied)
func_GET_IPV4() {

	HOSTNAME_SUBNET_OR_ADDRESS=$1
	RETURN_CIDR_NOTATION=$2
	CIDR_NOTATION="32"
	
	# Temporarily remove CIDR notation for DNS lookup
	if func_HOST_IS_SUBNET "$HOSTNAME_SUBNET_OR_ADDRESS"
	then
		CIDR_NOTATION=`echo $HOSTNAME_SUBNET_OR_ADDRESS | awk -F'/' '{print $2}'`
		HOSTNAME_SUBNET_OR_ADDRESS=`echo $HOSTNAME_SUBNET_OR_ADDRESS | awk -F'/' '{print $1}'`
	fi
	
	DNS_LOOKUP=`getent ahostsv4 $HOSTNAME_SUBNET_OR_ADDRESS | grep ' STREAM' | awk '{print $1}'`
	
	if [ ! "$DNS_LOOKUP" = "" ]
	then
		if [ "$RETURN_CIDR_NOTATION" = 1 ]
		then
			echo $DNS_LOOKUP/$CIDR_NOTATION
		else
			echo $DNS_LOOKUP
		fi
	fi
	
}

# Get IPv6 address from hostname (returns the IPv6 address if address was supplied)
# (Does not return mapped IPv4 addresses)
func_GET_IPV6() {

	HOSTNAME_SUBNET_OR_ADDRESS=$1
	RETURN_CIDR_NOTATION=$2
	CIDR_NOTATION="128"
	
	# Temporarily remove CIDR notation for DNS lookup
	if func_HOST_IS_SUBNET "$HOSTNAME_SUBNET_OR_ADDRESS"
	then
		CIDR_NOTATION=`echo $HOSTNAME_SUBNET_OR_ADDRESS | awk -F'/' '{print $2}'`
		HOSTNAME_SUBNET_OR_ADDRESS=`echo $HOSTNAME_SUBNET_OR_ADDRESS | awk -F'/' '{print $1}'`
	fi
	
	DNS_LOOKUP=`getent ahostsv6 $HOSTNAME_SUBNET_OR_ADDRESS | grep ' STREAM' | grep -v '::ffff:' | awk '{print $1}'`
	
	if [ ! "$DNS_LOOKUP" = "" ]
	then
		if [ "$RETURN_CIDR_NOTATION" = 1 ]
		then
			echo $DNS_LOOKUP/$CIDR_NOTATION
		else
			echo $DNS_LOOKUP
		fi
	fi
	
}

# Create elements list for nft set
func_CREATE_SET_ELEMENTS_FROM_FILE() {

	TYPE=$1
	LIST_FILE_CONTENT=$2
	IP_VERSION=$3
	PROTOCOL_FILTER=$4
	VERDICT=$5

	IFS='
'

	# Iterate through list
	for LINE in $LIST_FILE_CONTENT
	do
	
		HOSTNAME_SUBNET_OR_ADDRESS=`echo "$LINE" | awk '{print $1}'`
		IS_ENABLED=`echo "$LINE" | awk '{print $2}'`
		PROTOCOL=`echo "$LINE" | awk '{print $3}'`
		PORTS=`echo "$LINE" | awk '{print $4}'`		
		
		if [ "$TYPE" = "whitelist" ]
		then
			if [ "$HOSTNAME_SUBNET_OR_ADDRESS" = "" ] || [ "$IS_ENABLED" = "" ] || [ "$PROTOCOL" = "" ] || [ "$PORTS" = "" ]
			then
				>&2 echo "Syntax error in whitelist:\n  `func_GET_CURRENT_LIST_LINE`"
				exit 1
			fi
			
			# Unfortunately we cannot concatenate the port (inet_service) with a subnet (ipv4_addr),
			# so, for whitelists, we need to add it as an additional rule instead of adding it into the set.
			if func_HOST_IS_SUBNET "$HOSTNAME_SUBNET_OR_ADDRESS"
			then
				>&2 echo "Subnets in whitelists are currently not supported:\n  `func_GET_CURRENT_LIST_LINE`"
				exit 1
			fi
			
			RETURN_CIDR_NOTATION=0
		elif [ "$TYPE" = "blacklist" ]
		then
			if [ "$HOSTNAME_SUBNET_OR_ADDRESS" = "" ] || [ "$IS_ENABLED" = "" ]
			then
				>&2 echo "Syntax error in blacklist:\n  `func_GET_CURRENT_LIST_LINE`"
				exit 1
			fi
			
			RETURN_CIDR_NOTATION=1
		fi
		
		# Only if rule is enabled
		if [ ! "$IS_ENABLED" = "1" ]
		then
			continue
		fi
		
		# Return only elements for specified protocol
		if [ ! "$PROTOCOL_FILTER" = "$PROTOCOL" ]
		then
			continue
		fi
		
		# Get IPv4 address from hostname
		if [ $IP_VERSION = 4 ]
		then
			IP_ADDR=`func_GET_IPV4 $HOSTNAME_SUBNET_OR_ADDRESS $RETURN_CIDR_NOTATION`
		elif [ $IP_VERSION = 6 ]
		then
			IP_ADDR=`func_GET_IPV6 $HOSTNAME_SUBNET_OR_ADDRESS $RETURN_CIDR_NOTATION`
		fi
		
		# Validate that the lookup was successful
		if [ "$IP_ADDR" = "" ]
		then
			>&2 echo "WARNING: DNS (IPv$IP_VERSION) lookup for '$HOSTNAME_SUBNET_OR_ADDRESS' failed:\n  `func_GET_CURRENT_LIST_LINE`"
			continue
		fi
		
		# Add to elements set
		if [ "$TYPE" = "whitelist" ]
		then
			# Allow multiple ports
			PORT_LIST=`echo "$PORTS" | tr "," "\n"`

			for PORT in $PORT_LIST
			do
				echo "			$PORT . $IP_ADDR,"
			done
		elif [ "$TYPE" = "blacklist" ]
		then
			echo "			$IP_ADDR,"
		fi
		
	done
	unset IFS
	
	exit 0

}

# Command
CMD=$1

case "$CMD" in

	# Update : Updates the whitelist table only
	# Generate : Generates the ruleset only
	whitelist|blacklist)
	
		ACTION=$2
		
		if [ ! "$ACTION" = "update" ] && [ ! "$ACTION" = "generate" ]
		then
			>&2 echo "Usage: ${0} $CMD {update|generate}"
			exit 1
		fi
	
		# IPv4 or IPv6 only or both?
		IP_VERSIONS=$3
		
		if [ ! "$IP_VERSIONS" = "all" ] && [ ! "$IP_VERSIONS" = 4 ] && [ ! "$IP_VERSIONS" = 6 ]
		then
			>&2 echo "You need to specify one or multiple Internet Protocol Versions."
			>&2 echo "  Usage: ${0} $CMD $ACTION {all|4|6}"
			exit 1
		fi
		
		# Name of whitelist/blacklist sets
		if [ "$CMD" = "whitelist" ]
		then
			NFT_LIST_NAME_PREFIX="whitelist"
			LIST_FILE_PATH="$CONF_PATH/whitelist.conf"
		elif [ "$CMD" = "blacklist" ]
		then
			NFT_LIST_NAME_PREFIX="blacklist"
			LIST_FILE_PATH="$CONF_PATH/blacklist.conf"
		fi
		
		NFT_LIST_NAME_IPV4_TCP="${NFT_LIST_NAME_PREFIX}_ipv4_tcp"
		NFT_LIST_NAME_IPV4_UDP="${NFT_LIST_NAME_PREFIX}_ipv4_udp"
		NFT_LIST_NAME_IPV6_TCP="${NFT_LIST_NAME_PREFIX}_ipv6_tcp"
		NFT_LIST_NAME_IPV6_UDP="${NFT_LIST_NAME_PREFIX}_ipv6_udp"
		
		NFT_LIST_NAME_IPV4="${NFT_LIST_NAME_PREFIX}_ipv4"
		NFT_LIST_NAME_IPV6="${NFT_LIST_NAME_PREFIX}_ipv6"
		
		# Temporary ruleset file which is later
		# used to atomically reload the ruleset
		TMP_RULESET_FILE="$TMP_PATH/table.$NFT_LIST_NAME_PREFIX"
		
		echo -n "" > $TMP_RULESET_FILE
		
		# In case we only want to reload the whitelist and not
		# all of the firewall rules, we need to flush the whitelist
		if [ "$ACTION" = "update" ]
		then
			echo "#!/usr/sbin/nft -f" >> $TMP_RULESET_FILE
			
			if [ "$IP_VERSIONS" = 4 ] || [ "$IP_VERSIONS" = "all" ]
			then
				if [ "$CMD" = "whitelist" ]
				then
					echo "flush set inet filter $NFT_LIST_NAME_IPV4_TCP" >> $TMP_RULESET_FILE
					echo "flush set inet filter $NFT_LIST_NAME_IPV4_UDP" >> $TMP_RULESET_FILE
				elif [ "$CMD" = "blacklist" ]
				then
					echo "flush set inet filter $NFT_LIST_NAME_IPV4" >> $TMP_RULESET_FILE
				fi
			fi
			
			if [ "$IP_VERSIONS" = 6 ] || [ "$IP_VERSIONS" = "all" ]
			then
				if [ "$CMD" = "whitelist" ]
				then
					echo "flush set inet filter $NFT_LIST_NAME_IPV6_TCP" >> $TMP_RULESET_FILE
					echo "flush set inet filter $NFT_LIST_NAME_IPV6_UDP" >> $TMP_RULESET_FILE
				elif [ "$CMD" = "blacklist" ]
				then
					echo "flush set inet filter $NFT_LIST_NAME_IPV6" >> $TMP_RULESET_FILE
				fi
			fi
		fi
		
		# Create our elements lists for the sets at first
		LIST_FILE_CONTENT=`cat $LIST_FILE_PATH | egrep -v "^\s*(#|$)"`
		
		if [ "$CMD" = "whitelist" ]
		then
		
			if [ "$IP_VERSIONS" = 4 ] || [ "$IP_VERSIONS" = "all" ]
			then
				if ! ELEMENTS_IPV4_TCP=`func_CREATE_SET_ELEMENTS_FROM_FILE whitelist "$LIST_FILE_CONTENT" 4 tcp accept`
				then
					exit 1
				fi
				
				if ! ELEMENTS_IPV4_UDP=`func_CREATE_SET_ELEMENTS_FROM_FILE whitelist "$LIST_FILE_CONTENT" 4 udp accept`
				then
					exit 1
				fi
			fi
			
			if [ "$IP_VERSIONS" = 6 ] || [ "$IP_VERSIONS" = "all" ]
			then
				if ! ELEMENTS_IPV6_TCP=`func_CREATE_SET_ELEMENTS_FROM_FILE whitelist "$LIST_FILE_CONTENT" 6 tcp accept`
				then
					exit 1
				fi
				
				if ! ELEMENTS_IPV6_UDP=`func_CREATE_SET_ELEMENTS_FROM_FILE whitelist "$LIST_FILE_CONTENT" 6 udp accept`
				then
					exit 1
				fi
			fi
			
		elif [ "$CMD" = "blacklist" ]
		then
			
			if [ "$IP_VERSIONS" = 4 ] || [ "$IP_VERSIONS" = "all" ]
			then
				if ! ELEMENTS_IPV4=`func_CREATE_SET_ELEMENTS_FROM_FILE blacklist "$LIST_FILE_CONTENT" 4 "" drop`
				then
					exit 1
				fi
			fi
			
			if [ "$IP_VERSIONS" = 6 ] || [ "$IP_VERSIONS" = "all" ]
			then
				if ! ELEMENTS_IPV6=`func_CREATE_SET_ELEMENTS_FROM_FILE blacklist "$LIST_FILE_CONTENT" 6 "" drop`
				then
					exit 1
				fi
			fi
			
		fi
		
		# Open table
		echo "table inet filter {" >> $TMP_RULESET_FILE
		
		if [ "$CMD" = "whitelist" ]
		then
		
			# IPv4
			if [ "$IP_VERSIONS" = 4 ] || [ "$IP_VERSIONS" = "all" ]
			then
			
				# TCP
				echo "	set ${NFT_LIST_NAME_IPV4_TCP} {" >> $TMP_RULESET_FILE
				echo "		type inet_service . ipv4_addr" >> $TMP_RULESET_FILE
				
				if [ ! "$ELEMENTS_IPV4_TCP" = "" ]
				then
					echo "		elements = {" >> $TMP_RULESET_FILE
					echo "$ELEMENTS_IPV4_TCP" >> $TMP_RULESET_FILE
					echo "		}" >> $TMP_RULESET_FILE
				fi
				
				echo "	}" >> $TMP_RULESET_FILE
				
				# UDP
				echo "	set ${NFT_LIST_NAME_IPV4_UDP} {" >> $TMP_RULESET_FILE
				echo "		type inet_service . ipv4_addr" >> $TMP_RULESET_FILE
				
				if [ ! "$ELEMENTS_IPV4_UDP" = "" ]
				then
					echo "		elements = {" >> $TMP_RULESET_FILE
					echo "$ELEMENTS_IPV4_UDP" >> $TMP_RULESET_FILE
					echo "		}" >> $TMP_RULESET_FILE
				fi
				
				echo "	}" >> $TMP_RULESET_FILE
				
			fi
			
			# IPv6
			if [ "$IP_VERSIONS" = 6 ] || [ "$IP_VERSIONS" = "all" ]
			then
			
				# TCP
				echo "	set ${NFT_LIST_NAME_IPV6_TCP} {" >> $TMP_RULESET_FILE
				echo "		type inet_service . ipv6_addr" >> $TMP_RULESET_FILE
				
				if [ ! "$ELEMENTS_IPV6_TCP" = "" ]
				then
					echo "		elements = {" >> $TMP_RULESET_FILE
					echo "$ELEMENTS_IPV6_TCP" >> $TMP_RULESET_FILE
					echo "		}" >> $TMP_RULESET_FILE
				fi
				
				echo "	}" >> $TMP_RULESET_FILE
				
				# UDP
				echo "	set ${NFT_LIST_NAME_IPV6_UDP} {" >> $TMP_RULESET_FILE
				echo "		type inet_service . ipv6_addr" >> $TMP_RULESET_FILE
				
				if [ ! "$ELEMENTS_IPV6_UDP" = "" ]
				then
					echo "		elements = {" >> $TMP_RULESET_FILE
					echo "$ELEMENTS_IPV6_UDP" >> $TMP_RULESET_FILE
					echo "		}" >> $TMP_RULESET_FILE
				fi
				
				echo "	}" >> $TMP_RULESET_FILE
			
			fi
		
		elif [ "$CMD" = "blacklist" ]
		then
		
			# IPv4
			if [ "$IP_VERSIONS" = 4 ] || [ "$IP_VERSIONS" = "all" ]
			then
			
				echo "	set ${NFT_LIST_NAME_IPV4} {" >> $TMP_RULESET_FILE
				echo "		type ipv4_addr; flags interval;" >> $TMP_RULESET_FILE
				
				if [ ! "$ELEMENTS_IPV4" = "" ]
				then
					echo "		elements = {" >> $TMP_RULESET_FILE
					echo "$ELEMENTS_IPV4" >> $TMP_RULESET_FILE
					echo "		}" >> $TMP_RULESET_FILE
				fi
				
				echo "	}" >> $TMP_RULESET_FILE
				
			fi
			
			# IPv6
			if [ "$IP_VERSIONS" = 6 ] || [ "$IP_VERSIONS" = "all" ]
			then
			
				echo "	set ${NFT_LIST_NAME_IPV6} {" >> $TMP_RULESET_FILE
				echo "		type ipv6_addr; flags interval;" >> $TMP_RULESET_FILE
				
				if [ ! "$ELEMENTS_IPV6" = "" ]
				then
					echo "		elements = {" >> $TMP_RULESET_FILE
					echo "$ELEMENTS_IPV6" >> $TMP_RULESET_FILE
					echo "		}" >> $TMP_RULESET_FILE
				fi
				
				echo "	}" >> $TMP_RULESET_FILE
			
			fi
		
		fi
		
		# Close table
		echo "}" >> $TMP_RULESET_FILE
		
		if [ "$ACTION" = "update" ]
		then
			if nft -f $TMP_RULESET_FILE
			then
				echo "Sets for '$NFT_LIST_NAME_PREFIX' atomically updated."
			else
				cat $TMP_RULESET_FILE
			fi
		else
			cat $TMP_RULESET_FILE
		fi
		
		rm $TMP_RULESET_FILE
		
	;;
	
	*)
		>&2 echo "Usage: ${0} {whitelist|blacklist}"
		exit 1
    ;;
	
esac

exit 0
