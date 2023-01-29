#!/bin/bash

if [ "$DEBUG" == "1" ]; then
  set -x
fi

set -e

CLOAK_CONFIG_FILE='/data/cloak.json'

# check to see if this file is being run or sourced from another script
_is_sourced() {
	# https://unix.stackexchange.com/a/215279
	[ "${#FUNCNAME[@]}" -ge 2 ] \
		&& [ "${FUNCNAME[0]}" = '_is_sourced' ] \
		&& [ "${FUNCNAME[1]}" = 'source' ]
}

# check if the required environment variables are provided if run in server mode
docker_verify_server_env() {
	if [ ! -f "$CLOAK_CONFIG_FILE" ]; then
        if [ -z "$CLOAK_PROXY_METHOD" ]; then
            echo 'Proxy method (CLOAK_PROXY_METHOD) is missing. (example: shadowsocks)'
            exit 1
        fi
        if [ -z "$CLOAK_PROXY_PROTOCOL" ]; then
            echo 'Proxy protocol (CLOAK_PROXY_PROTOCOL) is missing. (example: tcp)'
            exit 1
        fi
        if [ -z "$CLOAK_PROXY_ADDRESS" ]; then
            echo 'Proxy address and port (CLOAK_PROXY_ADDRESS) is missing. (example: 127.0.0.1:8080)'
            exit 1
        fi
        if [ -z "$CLOAK_BIND_ADDRESS" ]; then
            echo 'No bind address provided (CLOAK_BIND_ADDRESS). Will bind to ports 80 and 443.'
        fi
        if [ -z "$CLOAK_REDIR_ADDRESS" ]; then
            echo 'No redirect address provided (CLOAK_REDIR_ADDRESS). Will redirect the requests to www.bing.com.'
        fi
        if [ -z "$CLOAK_PRIVATE_KEY" ]; then
            echo 'No private key provided (CLOAK_PRIVATE_KEY). Will generate a random one.'
        fi
	fi
}

# check if the required environment variables are provided if run in client mode
docker_verify_client_env() {
    if [ -z "$CLOAK_REMOTE_HOST" ]; then
        echo 'No IP or host provided for the remote (CLOAK_REMOTE_HOST).'
        exit 1
    fi
    if [ -z "$CLOAK_REMOTE_PORT" ]; then
        echo 'No proxy remote port provided (CLOAK_REMOTE_PORT). Will use 443.'
    fi
    if [ -z "$CLOAK_LISTEN_IP" ]; then
        echo 'No listen IP provided (CLOAK_LISTEN_IP). Will use 0.0.0.0.'
    fi
    if [ -z "$CLOAK_LISTEN_PORT" ]; then
        echo 'No listen port provided (CLOAK_LISTEN_PORT). Will use 1984.'
    fi

	if [ ! -f "$CLOAK_CONFIG_FILE" ]; then
        if [ -z "$CLOAK_PROXY_METHOD" ]; then
            echo 'Proxy method (CLOAK_PROXY_METHOD) is missing. (example: shadowsocks)'
            exit 1
        fi
        if [ -z "$CLOAK_UUID" ]; then
            echo 'UUID (CLOAK_UUID) is missing.'
            exit 1
        fi
        if [ -z "$CLOAK_PUBLIC_KEY" ]; then
            echo 'No private key provided (CLOAK_PRIVATE_KEY).'
            exit 1
        fi
        if [ -z "$CLOAK_TRANSPORT" ]; then
            echo 'No transport method provided (CLOAK_TRANSPORT). Will use direct.'
        fi
        if [ -z "$CLOAK_ENCRYPTION_METHOD" ]; then
            echo 'No encryption method provided (CLOAK_ENCRYPTION_METHOD). Will use plain (no encryption).'
        fi
        if [ -z "$CLOAK_NUMBER_OF_CONNECTIONS" ]; then
            echo 'No value for number of connections provided (CLOAK_NUMBER_OF_CONNECTIONS). Will use 4 as default.'
        fi
        if [ -z "$CLOAK_BROWSER_SIGNATURE" ]; then
            echo 'No browser signature chosen (CLOAK_BROWSER_SIGNATURE). Will use chrome.'
        fi
        if [ -z "$CLOAK_SERVER_NAME" ]; then
            echo 'No server name provided (CLOAK_SERVER_NAME). Will use www.bing.com.'
        fi
        if [ -z "$CLOAK_STREAM_TIMEOUT" ]; then
            echo 'No stream timeout value provided (CLOAK_STREAM_TIMEOUT). Will use 300.'
        fi
	fi
}

# get the bind address from env variable or set to a default
get_bind_addr() {
    if [ -z "$CLOAK_BIND_ADDRESS" ]; then
        bind_addr_array=(":80" ":443")
    else
        IFS=',' read -r -a bind_addr_array <<< "$CLOAK_BIND_ADDRESS"
    fi
    printf -v bind_addr "\"%s\"," "${bind_addr_array[@]}"
     # remove the final character of bind_addr
    bind_addr=${bind_addr%?}

    echo $bind_addr
}

# generate a random UUID to use with the configuration
generate_uuid() {
    echo "$( ck-server -u )"
}

# generate a random public key and private key to use with the configuration
generate_keypair() {
    echo "$( ck-server -k )"
}

# generate a simple configuration file for the server mode
generate_server_config() {
    # read bind addresses
    bind_addr=$( get_bind_addr )

    # read UUID
    if [ -z "$CLOAK_UUID" ]; then
        # generate a random uuid
        CLOAK_UUID=$"\"$( generate_uuid )\""
        echo "Generated UUID: $CLOAK_UUID"
    fi

    # read private key
    if [ -z "$CLOAK_PRIVATE_KEY" ]; then
        # generate random public and private keys
        IFS=',' read -r -a keys <<< "$( generate_keypair )"
        echo "Generated keys. Public key: ${keys[0]}"
        CLOAK_PRIVATE_KEY=${keys[1]}
    fi

    cat <<- EOF > "$CLOAK_CONFIG_FILE"
{
  "ProxyBook": {
    "$CLOAK_PROXY_METHOD": [
      "$CLOAK_PROXY_PROTOCOL",
      "$CLOAK_PROXY_ADDRESS"
    ]
  },
  "BindAddr": [$bind_addr],
  "BypassUID": [
    $CLOAK_UUID
  ],
  "RedirAddr": "${CLOAK_REDIR_ADDRESS:-www.bing.com}",
  "PrivateKey": "$CLOAK_PRIVATE_KEY"
}
EOF
}

# generate a simple configuration file for the client mode
generate_client_config() {
    cat <<- EOF > "$CLOAK_CONFIG_FILE"
{
  "Transport": "${CLOAK_TRANSPORT:-direct}",
  "ProxyMethod": "$CLOAK_PROXY_METHOD",
  "EncryptionMethod": "${CLOAK_ENCRYPTION_METHOD:-plain}",
  "UID": "$CLOAK_UUID",
  "PublicKey": "$CLOAK_PUBLIC_KEY",
  "ServerName": "${CLOAK_SERVER_NAME:-www.bing.com}",
  "NumConn": ${CLOAK_NUMBER_OF_CONNECTIONS:-4},
  "BrowserSig": "${CLOAK_BROWSER_SIGNATURE:-chrome}",
  "StreamTimeout": ${CLOAK_STREAM_TIMEOUT:-300}
}
EOF
}

# check arguments for an option that would cause cloak to stop
# return true if there is one
_cloak_has_helper_options() {
	local arg
	for arg; do
		case "$arg" in
			-h|-k|-key|-u|-uid|-v)
				return 0
				;;
		esac
	done
	return 1
}

# check arguments for a config option specifying the config file
# return true if there is one
_cloak_has_config_option() {
	local arg
	for arg; do
        if [ "$arg" == '-c' ]; then
            return 0
        fi
	done
	return 1
}

_main() {
	# if command starts with an option, prepend ck-server
	if [ "${1:0:1}" = '-' ]; then
		set -- ck-server "$@"
	fi

    if ( [ "$1" = 'ck-server' ] || [ "$1" = 'ck-client' ] ) && ! _cloak_has_helper_options "$@" && ! _cloak_has_config_option "$@"; then
        if [ "$1" = 'ck-server' ]; then
            docker_verify_server_env

            # generate a config file for the server using the values from environment variables if no config is provided
            if [ ! -f "$CLOAK_CONFIG_FILE" ]; then
                echo "Generating simple config file at $CLOAK_CONFIG_FILE!"
                generate_server_config
            fi
        elif [ "$1" = 'ck-client' ]; then
            docker_verify_client_env

            set -- "$@" '-i' "${CLOAK_LISTEN_IP:-'0.0.0.0'}"
            set -- "$@" '-l' "${CLOAK_LISTEN_PORT:-1984}"
            set -- "$@" '-p' "${CLOAK_REMOTE_PORT:-443}"
            set -- "$@" '-s' "${CLOAK_REMOTE_HOST}"

            # generate a config file for the client using the values from environment variables if no config is provided
            if [ ! -f "$CLOAK_CONFIG_FILE" ]; then
                echo "Generating simple config file at $CLOAK_CONFIG_FILE!"
                generate_client_config
            fi
        fi

        set -- "$@" '-c' "$CLOAK_CONFIG_FILE"

    fi

    exec "$@"
}

# If the script is sourced from elsewhere, don't perform any further actions
if ! _is_sourced; then
	_main "$@"
fi