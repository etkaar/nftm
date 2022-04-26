#!/bin/sh
: '''
Copyright (c) 2020-22 etkaar <https://github.com/etkaar/nftm>

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

# Show line where the syntax error occurred
func_GET_CURRENT_LIST_LINE() {
	if [ "$TYPE" = "whitelist" ]
	then
		printf '%s\n' "$HOSTNAME_SUBNET_OR_ADDRESS : enabled : $IS_ENABLED, protocol : $PROTOCOL, ports : {$PORTS}"
	elif [ "$TYPE" = "blacklist" ]
	then
		printf '%s\n' "$HOSTNAME_SUBNET_OR_ADDRESS : enabled : $IS_ENABLED"
	fi
}

# Check host is a subnet
func_HOST_IS_SUBNET() {
	HOSTNAME_SUBNET_OR_ADDRESS="$1"
	
	CHECK="$(printf '%s' "$HOSTNAME_SUBNET_OR_ADDRESS" | grep '/')"
	
	if [ "$CHECK" = "" ]
	then
		return 1
	else
		return 0
	fi
}

# Check if given string is an IPv4 address
# WARNING: This is nothing more than a *weak* plausibility check.
func_IS_IPV4_ADDRESS() {
	HOSTNAME_SUBNET_OR_ADDRESS="$1"
	
	# We need exactly three (3) dots (.)
	COUNT="$(func_SUBSTR_COUNT "." "$HOSTNAME_SUBNET_OR_ADDRESS")"
	
	if [ ! "$COUNT" = 3 ]
	then
		return 1
	fi
	
	RETVAL=0
	
	# Groups are separated by a dot (.)
	func_SET_IFS '\n'
	
	for GROUP in $(printf '%s' "$HOSTNAME_SUBNET_OR_ADDRESS" | awk -F'/' '{print $1}' | sed "s/\./\n/g")
	do
		# Check if group is an integer number
		if ! func_IS_UNSIGNED_INTEGER "$GROUP"
		then
			RETVAL=1
			break
		fi
		
		# Validate range (0-255)
		if [ "$GROUP" -lt 0 ] || [ "$GROUP" -gt 255 ]
		then
			RETVAL=1
			break
		fi
	done
	
	func_RESTORE_IFS
	
	return "$RETVAL"
}

# Get IPv4 address from hostname (returns the IPv4 address if address was supplied)
func_GET_IPV4() {
	HOSTNAME_SUBNET_OR_ADDRESS="$1"
	RETURN_CIDR_NOTATION="$2"
	CIDR_NOTATION="32"
	
	# Temporarily remove CIDR notation for DNS lookup
	if func_HOST_IS_SUBNET "$HOSTNAME_SUBNET_OR_ADDRESS"
	then
		CIDR_NOTATION="$(printf '%s' "$HOSTNAME_SUBNET_OR_ADDRESS" | awk -F'/' '{print $2}')"
		HOSTNAME_SUBNET_OR_ADDRESS="$(printf '%s' "$HOSTNAME_SUBNET_OR_ADDRESS" | awk -F'/' '{print $1}')"
	fi
	
	DNS_LOOKUP="$(getent ahostsv4 "$HOSTNAME_SUBNET_OR_ADDRESS" | grep ' STREAM' | awk '{print $1}')"
	
	if [ ! "$DNS_LOOKUP" = "" ]
	then
		if [ "$RETURN_CIDR_NOTATION" = 1 ]
		then
			printf '%s\n' "$DNS_LOOKUP/$CIDR_NOTATION"
		else
			printf '%s\n' "$DNS_LOOKUP"
		fi
	fi
}

# Check if given string is an IPv6 address
# WARNING: This is nothing more than a *weak* plausibility check.
func_IS_IPV6_ADDRESS() {
	HOSTNAME_SUBNET_OR_ADDRESS="$1"
	
	# We need at least two colons (:) but not more than 8
	COUNT="$(func_SUBSTR_COUNT ":" "$HOSTNAME_SUBNET_OR_ADDRESS")"
	
	if [ "$COUNT" -lt 2 ] || [ "$COUNT" -gt 8 ]
	then
		return 1
	fi
	
	RETVAL=0
	
	# Groups are separated by colon (:)
	func_SET_IFS '\n'
	
	for GROUP in $(printf '%s' "$HOSTNAME_SUBNET_OR_ADDRESS" | awk -F'/' '{print $1}' | sed "s/:/\n/g")
	do
		# Validate range (not more than 4 bytes)
		if [ ${#GROUP} -gt 4 ]
		then
			RETVAL=1
			break
		fi
	
		# Check if group is a hexadecmal number
		if ! func_IS_HEX "$GROUP"
		then
			RETVAL=1
			break
		fi
	done
	
	func_RESTORE_IFS
	
	return "$RETVAL"
}

# Get IPv6 address from hostname (returns the IPv6 address if address was supplied)
# (Does not return mapped IPv4 addresses)
func_GET_IPV6() {
	HOSTNAME_SUBNET_OR_ADDRESS="$1"
	RETURN_CIDR_NOTATION="$2"
	CIDR_NOTATION="128"
	
	# Temporarily remove CIDR notation for DNS lookup
	if func_HOST_IS_SUBNET "$HOSTNAME_SUBNET_OR_ADDRESS"
	then
		CIDR_NOTATION="$(printf '%s' "$HOSTNAME_SUBNET_OR_ADDRESS" | awk -F'/' '{print $2}')"
		HOSTNAME_SUBNET_OR_ADDRESS="$(printf '%s' "$HOSTNAME_SUBNET_OR_ADDRESS" | awk -F'/' '{print $1}')"
	fi
	
	DNS_LOOKUP="$(getent ahostsv6 "$HOSTNAME_SUBNET_OR_ADDRESS" | grep ' STREAM' | grep -v '::ffff:' | awk '{print $1}')"
	
	if [ ! "$DNS_LOOKUP" = "" ]
	then
		if [ "$RETURN_CIDR_NOTATION" = 1 ]
		then
			printf '%s\n' "$DNS_LOOKUP/$CIDR_NOTATION"
		else
			printf '%s\n' "$DNS_LOOKUP"
		fi
	fi
}

# Unfortunately we cannot concatenate the port (inet_service) with a subnet (ipv4_addr) in nftables < 0.9.4
# See: https://marc.info/?l=netfilter&m=158575148505527&w=2
func_ARE_CONCATENATED_SETS_SUPPORTED() {
	NFTABLES_CONCATENATION_SUPPORT_REQUIRED_MIN_VERSION_STRING="0.9.4"
	NFTABLES_CONCATENATION_SUPPORT_REQUIRED_MIN_VERSION_INTEGER="$(func_VERSION_STRING_TO_INTEGER 3 "$NFTABLES_CONCATENATION_SUPPORT_REQUIRED_MIN_VERSION_STRING")"
	
	if [ "$NFTABLES_INSTALLED_VERSION_INTEGER" -lt "$NFTABLES_CONCATENATION_SUPPORT_REQUIRED_MIN_VERSION_INTEGER" ]
	then
		return 1
	else
		return 0
	fi
}

# We need this to replace some __VARIABLES__ in the template files
func_APPLY_TEMPLATE_SUBSTITUTIONS() {
	TEMPLATE="$1"
	
	# The interval flag (concatenated sets with more than one type) may be not supported,
	# so we only set it if support is guaranteed (nftables >= 0.9.4). Blacklists are not
	# affected, since they do not concatenate anything.
	if func_ARE_CONCATENATED_SETS_SUPPORTED
	then
		INTERVAL_FLAG_IF_SUPPORTED=" flags interval;"
	else
		INTERVAL_FLAG_IF_SUPPORTED=""
	fi
	
	TEMPLATE="$(printf '%s\n' "$TEMPLATE" | sed "s/__INTERVAL_FLAG_IF_SUPPORTED_/$INTERVAL_FLAG_IF_SUPPORTED/g")"
	printf '%s\n' "$TEMPLATE"
}

# Create elements list for nft set
func_CREATE_SET_ELEMENTS_FROM_FILE() {
	TYPE="$1"
	LIST_FILE_CONTENT="$2"
	IP_VERSION="$3"
	PROTOCOL_FILTER="$4"
	VERDICT="$5"

	IFS='
'

	# Iterate through list
	for LINE in $LIST_FILE_CONTENT
	do
		HOSTNAME_SUBNET_OR_ADDRESS="$(printf '%s' "$LINE" | awk '{print $1}')"
		IS_ENABLED="$(printf '%s' "$LINE" | awk '{print $2}')"
		PROTOCOL="$(printf '%s' "$LINE" | awk '{print $3}')"
		PORTS="$(printf '%s' "$LINE" | awk '{print $4}')"
		
		if [ "$TYPE" = "whitelist" ]
		then
			if [ "$HOSTNAME_SUBNET_OR_ADDRESS" = "" ] || [ "$IS_ENABLED" = "" ] || [ "$PROTOCOL" = "" ] || [ "$PORTS" = "" ]
			then
				func_EXIT_ERROR 1 "Syntax error in whitelist:" "  $(func_GET_CURRENT_LIST_LINE)"
			fi
			
			if ! func_ARE_CONCATENATED_SETS_SUPPORTED
			then
				if func_HOST_IS_SUBNET "$HOSTNAME_SUBNET_OR_ADDRESS"
				then
					func_EXIT_ERROR 1 "Subnets in whitelists are currently not supported (needs nftables >= $NFTABLES_CONCATENATION_SUPPORT_REQUIRED_MIN_VERSION_STRING):" "  $(func_GET_CURRENT_LIST_LINE)"
				else
					RETURN_CIDR_NOTATION=0
				fi
			else
				RETURN_CIDR_NOTATION=1
			fi
		elif [ "$TYPE" = "blacklist" ]
		then
			if [ "$HOSTNAME_SUBNET_OR_ADDRESS" = "" ] || [ "$IS_ENABLED" = "" ]
			then
				func_EXIT_ERROR 1 "Syntax error in blacklist:" "  $(func_GET_CURRENT_LIST_LINE)"
			fi
			
			RETURN_CIDR_NOTATION=1
		fi
		
		# Please do not use multiple protocols (not 'tcp,udp' but two lines for each protocol)
		if [ ! "$(printf '%s' "$PROTOCOL" | grep ',')" = "" ]
		then
			func_EXIT_ERROR 1 "Syntax error in whitelist (use of multiple protocols):" "  $(func_GET_CURRENT_LIST_LINE)"
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
		
		# Ignore IPv6 addresses for IPv4 sets and vice versa
		if [ "$IP_VERSION" = 4 ] && func_IS_IPV6_ADDRESS "$HOSTNAME_SUBNET_OR_ADDRESS"
		then
			if [ "$OPT_DEBUG" = 1 ]
			then
				func_PRINT_DEBUG "DEBUG: Ignoring IPv6 address '$HOSTNAME_SUBNET_OR_ADDRESS' for IPv4 whitelist:" "  $(func_GET_CURRENT_LIST_LINE)"
			fi
			
			continue
		elif [ "$IP_VERSION" = 6 ] && func_IS_IPV4_ADDRESS "$HOSTNAME_SUBNET_OR_ADDRESS"
		then
			if [ "$OPT_DEBUG" = 1 ]
			then
				func_PRINT_DEBUG "DEBUG: Ignoring IPv4 address '$HOSTNAME_SUBNET_OR_ADDRESS' for IPv6 whitelist:" "  $(func_GET_CURRENT_LIST_LINE)"
			fi
			
			continue
		fi
		
		# Get IPv4/6 address from hostname *or* returns the IP address if actually no hostname was given
		if [ "$IP_VERSION" = 4 ]
		then
			IP_ADDR="$(func_GET_IPV4 "$HOSTNAME_SUBNET_OR_ADDRESS" "$RETURN_CIDR_NOTATION")"
		elif [ "$IP_VERSION" = 6 ]
		then
			IP_ADDR="$(func_GET_IPV6 "$HOSTNAME_SUBNET_OR_ADDRESS" "$RETURN_CIDR_NOTATION")"
		fi
		
		# Validate that the lookup was successful (here we need to request both the IPv4 and IPv6 address, so it is normal
		# that it will fail in cases the hostname only has an A (IPv4), but not an AAAA (IPv6) record or viceversa)
		if [ "$IP_ADDR" = "" ]
		then
			if [ ! "$OPT_NO_WARNINGS" = 1 ]
			then
				func_PRINT_WARNING "WARNING: IPv${IP_VERSION}-DNS lookup for '$HOSTNAME_SUBNET_OR_ADDRESS' failed:" "  $(func_GET_CURRENT_LIST_LINE)"
			fi
			
			continue
		fi
		
		# Add to elements set
		if [ "$TYPE" = "whitelist" ]
		then
			# Allow multiple ports
			PORT_LIST="$(printf '%s' "$PORTS" | tr "," "\n")"

			for PORT in $PORT_LIST
			do
				printf '%s\n' "			$PORT . $IP_ADDR,"
			done
		elif [ "$TYPE" = "blacklist" ]
		then
			printf '%s\n' "			$IP_ADDR,"
		fi
	done
	unset IFS
	
	exit 0
}

# Create the final whitelist or blacklist template
func_CREATE_WHITE_OR_BLACKLIST_TEMPLATE() {
	# whitelist|blacklist
	TYPE="$1"
	
	# update|generate
	ACTION="$2"
	
	# all|4|6
	IP_VERSIONS="$3"
	
	if [ ! "$ACTION" = "update" ] && [ ! "$ACTION" = "generate" ]
	then
		func_EXIT_ERROR 1 "Usage: ${0} $TYPE {update|generate}"
	fi

	# IPv4 or IPv6 only or both?
	if [ ! "$IP_VERSIONS" = "all" ] && [ ! "$IP_VERSIONS" = 4 ] && [ ! "$IP_VERSIONS" = 6 ]
	then
		func_EXIT_ERROR 1 "You need to specify one or multiple Internet Protocol Versions." "  Usage: ${0} $TYPE $ACTION {all|4|6}"
	fi
	
	# Name of whitelist/blacklist sets
	if [ "$TYPE" = "whitelist" ]
	then
		NFT_LIST_NAME_PREFIX="whitelist"
		LIST_FILE_PATH="$CONF_PATH/whitelist.conf"
	elif [ "$TYPE" = "blacklist" ]
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
	
	printf "" > "$TMP_RULESET_FILE"
	
	# In case we only want to reload the whitelist and not
	# all of the firewall rules, we need to flush the whitelist
	if [ "$ACTION" = "update" ]
	then
		printf '%s\n' "#!/usr/sbin/nft -f" >> "$TMP_RULESET_FILE"
		
		if [ "$IP_VERSIONS" = 4 ] || [ "$IP_VERSIONS" = "all" ]
		then
			if [ "$TYPE" = "whitelist" ]
			then
				printf '%s\n' "flush set inet filter $NFT_LIST_NAME_IPV4_TCP" >> "$TMP_RULESET_FILE"
				printf '%s\n' "flush set inet filter $NFT_LIST_NAME_IPV4_UDP" >> "$TMP_RULESET_FILE"
			elif [ "$TYPE" = "blacklist" ]
			then
				printf '%s\n' "flush set inet filter $NFT_LIST_NAME_IPV4" >> "$TMP_RULESET_FILE"
			fi
		fi
		
		if [ "$IP_VERSIONS" = 6 ] || [ "$IP_VERSIONS" = "all" ]
		then
			if [ "$TYPE" = "whitelist" ]
			then
				printf '%s\n' "flush set inet filter $NFT_LIST_NAME_IPV6_TCP" >> "$TMP_RULESET_FILE"
				printf '%s\n' "flush set inet filter $NFT_LIST_NAME_IPV6_UDP" >> "$TMP_RULESET_FILE"
			elif [ "$TYPE" = "blacklist" ]
			then
				printf '%s\n' "flush set inet filter $NFT_LIST_NAME_IPV6" >> "$TMP_RULESET_FILE"
			fi
		fi
	fi
	
	# Create our elements lists for the sets at first
	LIST_FILE_CONTENT="$(func_READ_CONFIG_FILE "$LIST_FILE_PATH")"
	
	if [ "$TYPE" = "whitelist" ]
	then
	
		if [ "$IP_VERSIONS" = 4 ] || [ "$IP_VERSIONS" = "all" ]
		then
			if ! ELEMENTS_IPV4_TCP="$(func_CREATE_SET_ELEMENTS_FROM_FILE whitelist "$LIST_FILE_CONTENT" 4 tcp accept)"
			then
				exit 1
			fi
			
			if ! ELEMENTS_IPV4_UDP="$(func_CREATE_SET_ELEMENTS_FROM_FILE whitelist "$LIST_FILE_CONTENT" 4 udp accept)"
			then
				exit 1
			fi
		fi
		
		if [ "$IP_VERSIONS" = 6 ] || [ "$IP_VERSIONS" = "all" ]
		then
			if ! ELEMENTS_IPV6_TCP="$(func_CREATE_SET_ELEMENTS_FROM_FILE whitelist "$LIST_FILE_CONTENT" 6 tcp accept)"
			then
				exit 1
			fi
			
			if ! ELEMENTS_IPV6_UDP="$(func_CREATE_SET_ELEMENTS_FROM_FILE whitelist "$LIST_FILE_CONTENT" 6 udp accept)"
			then
				exit 1
			fi
		fi
		
	elif [ "$TYPE" = "blacklist" ]
	then
		
		if [ "$IP_VERSIONS" = 4 ] || [ "$IP_VERSIONS" = "all" ]
		then
			if ! ELEMENTS_IPV4="$(func_CREATE_SET_ELEMENTS_FROM_FILE blacklist "$LIST_FILE_CONTENT" 4 "" drop)"
			then
				exit 1
			fi
		fi
		
		if [ "$IP_VERSIONS" = 6 ] || [ "$IP_VERSIONS" = "all" ]
		then
			if ! ELEMENTS_IPV6="$(func_CREATE_SET_ELEMENTS_FROM_FILE blacklist "$LIST_FILE_CONTENT" 6 "" drop)"
			then
				exit 1
			fi
		fi
		
	fi
	
	# Open table
	printf '%s\n' "table inet filter {" >> "$TMP_RULESET_FILE"
	
	if [ "$TYPE" = "whitelist" ]
	then
	
		# IPv4
		if [ "$IP_VERSIONS" = 4 ] || [ "$IP_VERSIONS" = "all" ]
		then
		
			# TCP
			printf '%s\n' "	set ${NFT_LIST_NAME_IPV4_TCP} {" >> "$TMP_RULESET_FILE"
			
			if func_ARE_CONCATENATED_SETS_SUPPORTED
			then
				printf '%s\n' "		type inet_service . ipv4_addr; flags interval;" >> "$TMP_RULESET_FILE"
			else
				printf '%s\n' "		type inet_service . ipv4_addr" >> "$TMP_RULESET_FILE"
			fi
			
			if [ ! "$ELEMENTS_IPV4_TCP" = "" ]
			then
				printf '%s\n' "		elements = {" >> "$TMP_RULESET_FILE"
				printf '%s\n' "$ELEMENTS_IPV4_TCP" >> "$TMP_RULESET_FILE"
				printf '%s\n' "		}" >> "$TMP_RULESET_FILE"
			fi
			
			printf '%s\n' "	}" >> "$TMP_RULESET_FILE"
			
			# UDP
			printf '%s\n' "	set ${NFT_LIST_NAME_IPV4_UDP} {" >> "$TMP_RULESET_FILE"

			if func_ARE_CONCATENATED_SETS_SUPPORTED
			then
				printf '%s\n' "		type inet_service . ipv4_addr; flags interval;" >> "$TMP_RULESET_FILE"
			else
				printf '%s\n' "		type inet_service . ipv4_addr" >> "$TMP_RULESET_FILE"
			fi			
			
			if [ ! "$ELEMENTS_IPV4_UDP" = "" ]
			then
				printf '%s\n' "		elements = {" >> "$TMP_RULESET_FILE"
				printf '%s\n' "$ELEMENTS_IPV4_UDP" >> "$TMP_RULESET_FILE"
				printf '%s\n' "		}" >> "$TMP_RULESET_FILE"
			fi
			
			printf '%s\n' "	}" >> "$TMP_RULESET_FILE"
			
		fi
		
		# IPv6
		if [ "$IP_VERSIONS" = 6 ] || [ "$IP_VERSIONS" = "all" ]
		then
		
			# TCP
			printf '%s\n' "	set ${NFT_LIST_NAME_IPV6_TCP} {" >> "$TMP_RULESET_FILE"
			
			if func_ARE_CONCATENATED_SETS_SUPPORTED
			then
				printf '%s\n' "		type inet_service . ipv6_addr; flags interval;" >> "$TMP_RULESET_FILE"
			else
				printf '%s\n' "		type inet_service . ipv6_addr" >> "$TMP_RULESET_FILE"
			fi
			
			if [ ! "$ELEMENTS_IPV6_TCP" = "" ]
			then
				printf '%s\n' "		elements = {" >> "$TMP_RULESET_FILE"
				printf '%s\n' "$ELEMENTS_IPV6_TCP" >> "$TMP_RULESET_FILE"
				printf '%s\n' "		}" >> "$TMP_RULESET_FILE"
			fi
			
			printf '%s\n' "	}" >> "$TMP_RULESET_FILE"
			
			# UDP
			printf '%s\n' "	set ${NFT_LIST_NAME_IPV6_UDP} {" >> "$TMP_RULESET_FILE"

			if func_ARE_CONCATENATED_SETS_SUPPORTED
			then
				printf '%s\n' "		type inet_service . ipv6_addr; flags interval;" >> "$TMP_RULESET_FILE"
			else
				printf '%s\n' "		type inet_service . ipv6_addr" >> "$TMP_RULESET_FILE"
			fi
			
			if [ ! "$ELEMENTS_IPV6_UDP" = "" ]
			then
				printf '%s\n' "		elements = {" >> "$TMP_RULESET_FILE"
				printf '%s\n' "$ELEMENTS_IPV6_UDP" >> "$TMP_RULESET_FILE"
				printf '%s\n' "		}" >> "$TMP_RULESET_FILE"
			fi
			
			printf '%s\n' "	}" >> "$TMP_RULESET_FILE"
		
		fi
	
	elif [ "$TYPE" = "blacklist" ]
	then
	
		# IPv4
		if [ "$IP_VERSIONS" = 4 ] || [ "$IP_VERSIONS" = "all" ]
		then
		
			printf '%s\n' "	set ${NFT_LIST_NAME_IPV4} {" >> "$TMP_RULESET_FILE"
			printf '%s\n' "		type ipv4_addr; flags interval;" >> "$TMP_RULESET_FILE"
			
			if [ ! "$ELEMENTS_IPV4" = "" ]
			then
				printf '%s\n' "		elements = {" >> "$TMP_RULESET_FILE"
				printf '%s\n' "$ELEMENTS_IPV4" >> "$TMP_RULESET_FILE"
				printf '%s\n' "		}" >> "$TMP_RULESET_FILE"
			fi
			
			printf '%s\n' "	}" >> "$TMP_RULESET_FILE"
			
		fi
		
		# IPv6
		if [ "$IP_VERSIONS" = 6 ] || [ "$IP_VERSIONS" = "all" ]
		then
		
			printf '%s\n' "	set ${NFT_LIST_NAME_IPV6} {" >> "$TMP_RULESET_FILE"
			printf '%s\n' "		type ipv6_addr; flags interval;" >> "$TMP_RULESET_FILE"
			
			if [ ! "$ELEMENTS_IPV6" = "" ]
			then
				printf '%s\n' "		elements = {" >> "$TMP_RULESET_FILE"
				printf '%s\n' "$ELEMENTS_IPV6" >> "$TMP_RULESET_FILE"
				printf '%s\n' "		}" >> "$TMP_RULESET_FILE"
			fi
			
			printf '%s\n' "	}" >> "$TMP_RULESET_FILE"
		
		fi
	
	fi
	
	# Close table
	printf '%s\n' "}" >> "$TMP_RULESET_FILE"
	
	if [ "$ACTION" = "update" ]
	then
		if nft -f "$TMP_RULESET_FILE"
		then
			func_STDOUT "Sets for '$NFT_LIST_NAME_PREFIX' atomically updated."
		else
			cat "$TMP_RULESET_FILE"
		fi
	else
		cat "$TMP_RULESET_FILE"
	fi
	
	rm "$TMP_RULESET_FILE"
}
