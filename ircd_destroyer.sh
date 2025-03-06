#!/bin/bash


# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    ircd_destroyer.sh                                  :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: jmakkone <jmakkone@student.hive.fi>        +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2025/03/06 18:37:07 by jmakkone          #+#    #+#              #
#    Updated: 2025/03/06 18:37:07 by jmakkone         ###   ########.fr        #
#                                                                              #
# **************************************************************************** #
# A modular IRC server stress test script.
# WARNING: This script is designed to stress (and potentially break) your IRC server.
# Use it only in a controlled test environment!

SERVER=""
PORT=""
PASSWORD=""
TEST_MODE=""
CONN_COUNT=10
SLEEP_TIME=0.5
TIMEOUT=5

usage() {
    echo "Usage: $0 -S SERVER -P PORT -p PASSWORD [-t TEST_MODE] [-c CONNECTIONS] [-s SLEEP] [-T TIMEOUT]"
    echo "  Required:"
    echo "    -S SERVER    (e.g., localhost)"
    echo "    -P PORT      (e.g., 6667)"
    echo "    -p PASSWORD  (e.g., securepassword)"
    echo "  Optional TEST_MODE (single letter):"
    echo "    a: all, b: basic, j: join, p: part, P: privmsg, m: mode, i: invalid,"
    echo "    A: auth, x: incorrect_auth, r: re_auth, u: unfinished_auth, g: garbage"
    echo "  Optional:"
    echo "    -c CONNECTIONS   (Connection count. default: 10)"
    echo "    -s SLEEP         (Sleep time between connections. default: 0.5 seconds)"
    echo "    -T TIMEOUT       (Netcat timeout. default: 5 seconds)"
    exit 1
}

while getopts "S:P:p:t:c:s:T:" opt; do
    case $opt in
        S) SERVER="$OPTARG" ;;
        P) PORT="$OPTARG" ;;
        p) PASSWORD="$OPTARG" ;;
        t) TEST_MODE="$OPTARG" ;;
        c) CONN_COUNT="$OPTARG" ;;
        s) SLEEP_TIME="$OPTARG" ;;
        T) TIMEOUT="$OPTARG" ;;
        *) usage ;;
    esac
done

if [ -z "$SERVER" ] || [ -z "$PORT" ] || [ -z "$PASSWORD" ]; then
    usage
fi

TEST_MODE=${TEST_MODE:-a}

random_string() {
    local length=${1:-10}
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$length"
}

#####################################
# Global Arrays for Info Gathering
#####################################
declare -a G_CHANNELS
declare -a G_USERS
G_USER_MODES=""
G_CHANNEL_MODES=""

#####################################
# Info Test Module
#####################################
# This module gathers information about channels, users, and supported modes.
get_info() {
    local tmp_cmd=$(mktemp)
    local tmp_out=$(mktemp)

    cat <<EOF > "$tmp_cmd"
PASS $PASSWORD
NICK infoBot
USER infoBot 0 * :InfoTest
NAMES
QUIT :Info gathering done
EOF

    nc -C "$SERVER" "$PORT" < "$tmp_cmd" > "$tmp_out"

    G_CHANNELS=()
    G_USERS=()
    G_USER_MODES=""
    G_CHANNEL_MODES=""

    # Check if a value is in an array
    is_in_array() {
      local item
      for item in "${@:2}"; do
        [[ "$item" == "$1" ]] && return 0
      done
      return 1
    }

    while IFS= read -r line; do
        # Look for RPL_NAMREPLY (353) lines.
        if [[ "$line" =~ ^:.*\ 353\ .* ]]; then
            local ch
            ch=$(echo "$line" | awk '{print $5}')

            # Only store if it starts with '#'
            if [[ "$ch" == \#* ]]; then
                if ! is_in_array "$ch" "${G_CHANNELS[@]}"; then
                    G_CHANNELS+=("$ch")
                fi
            fi

            # Extract the user list (text after the last colon).
			local userlist
			userlist=$(
			echo "$line" | sed 's/.*://')

			for user in $userlist; do
				# Remove leading operator symbols
				user=$(echo "$user" | sed 's/^[*@]//')
				# Remove whitespace
				user=$(echo "$user" | sed -r '/^\s*$/d')

			# Skip empty nick
			[[ -z "$user" ]] && continue

			if ! is_in_array "$user" "${G_USERS[@]}"; then
				G_USERS+=("$user")
				echo "Adding user: $user"
			fi
			done

        # Look for RPL_MYINFO (004) lines.
        elif [[ "$line" =~ ^:.*\ 004\ .* ]]; then
            G_USER_MODES=$(echo "$line" | awk '{print $6}')
            G_CHANNEL_MODES=$(echo "$line" | awk '{print $7}')
        fi
    done < "$tmp_out"

    echo "Server info gathered:"
    echo "  Channels: ${G_CHANNELS[@]}"
    echo "  Users: ${G_USERS[@]}"
    echo "  User modes: $G_USER_MODES"
    echo "  Channel modes: $G_CHANNEL_MODES"

    rm "$tmp_cmd" "$tmp_out"
}

#####################################
# Test Modules
#####################################

test_basic() {
    local RAND=$((RANDOM % 100000))
    local RNICK="bot$RAND"
    local RUSER="user$RAND"
    local RCHANNEL="#chan$RAND"
    local LONG_MSG=$(random_string 600)
    cat <<EOF
PASS $PASSWORD
NICK $RNICK
USER $RUSER 0 * :RandomUser
JOIN $RCHANNEL
PRIVMSG $RCHANNEL :$LONG_MSG
MODE $RCHANNEL +l $((RANDOM % 200 + 1))
MODE $RCHANNEL +b bad!*@*
PRIVMSG $RCHANNEL,$RNICK,$RUSER :Spam message: $(random_string 50)
TOPIC $RCHANNEL :Topic update: $(random_string 30)
WHOIS $RNICK
NAMES
INVALIDCOMMAND $(random_string 10)
PRIVMSG $RCHANNEL :$(random_string 100)
:$(random_string 10) $(random_string 20) $(random_string 30)
QUIT :Goodbye
EOF
}

# Joins available channels.
# Tries to join invalid channels and double join already joined channels.
test_join() {
    local RAND=$((RANDOM % 100000))
    local RNICK="jbot$RAND"
    local RUSER="joinuser$RAND"
    local channels=""
    if [ ${#G_CHANNELS[@]} -gt 0 ]; then
        channels=$(IFS=,; echo "${G_CHANNELS[*]}")
    fi
	channels+=",#Validchannel$RAND,inVal\%idchannel$RAND,invaliDch#@nnel$RAND,#inval\r\nChannel$RAND"
    cat <<EOF
PASS $PASSWORD
NICK $RNICK
USER $RUSER 0 * :JoinTest
JOIN $channels
JOIN $channels
QUIT :Join test done
EOF
}

# Joins and parts existing and invalid channels
test_part() {
    local RAND=$((RANDOM % 100000))
    local RNICK="pbot$RAND"
    local RUSER="partuser$RAND"
    local channels=""
    if [ ${#G_CHANNELS[@]} -gt 0 ]; then
        channels=$(IFS=,; echo "${G_CHANNELS[*]}")
    fi
	channels+=",#Validchannel$RAND,inVal\%idchannel$RAND,invaliDch#@nnel$RAND,#inval\r\nChannel$RAND"
    cat <<EOF
PASS $PASSWORD
NICK $RNICK
USER $RUSER 0 * :PartTest
JOIN $channels
PART $channels :It was a test, I'll be back
PART $channels
QUIT :Part test done
EOF
}

# Send a PRIVMSG to all available users and channels.
# First tries to message channel without joining, then joins the channel and message again.
test_privmsg() {
    local RAND=$((RANDOM % 100000))
    local RNICK="Pbot$RAND"
    local RUSER="privuser$RAND"
    local MSG=$(random_string 150)
    local user_targets=""
    local channel_targets=""
	# Send to valid users on server
    if [ ${#G_USERS[@]} -gt 0 ]; then
        user_targets=$(IFS=,; echo "${G_USERS[*]}")
    fi
	# Send to valid channels on server
    if [ ${#G_CHANNELS[@]} -gt 0 ]; then
        channel_targets=$(IFS=,; echo "${G_CHANNELS[*]}")
    fi
	# Send to invalid targets
	user_targets+=",iNvalidnick$RAND,inValidnick$RAND,invaliDnick$RAND,invalidNick$RAND"
	channel_targets+=",#Validchannel$RAND,inVal\%idchannel$RAND,invaliDch#@nnel$RAND,#inval\r\nChannel$RAND"
	# Send to self
	user_targets+=",$RNICK"
    cat <<EOF
PASS $PASSWORD
NICK $RNICK
USER $RUSER 0 * :PrivMsgTest
PRIVMSG $user_targets :$MSG
PRIVMSG $channel_targets :$MSG
JOIN $channel_targets
PRIVMSG $channel_targets :$MSG
QUIT :Privmsg test done
EOF
}

# For each available channel, try various mode changes.
test_mode() {
    local RAND=$((RANDOM % 100000))
    local RNICK="mbot$RAND"
    local RUSER="modeuser$RAND"
    local cmd=""
    if [ ${#G_CHANNELS[@]} -gt 0 ]; then
		for chan in "${G_CHANNELS[@]}"; do
			cmd+="JOIN $chan"$'\n'
			cmd+="MODE $chan "$'\n'
			cmd+="MODE $chan +i"$'\n'
			cmd+="MODE $chan -i"$'\n'
			cmd+="MODE $chan i"$'\n'
			cmd+="MODE $chan -i"$'\n'
			cmd+="MODE $chan +t"$'\n'
			cmd+="MODE $chan -t"$'\n'
			cmd+="MODE $chan t"$'\n'
			cmd+="MODE $chan -k $(random_string 5)"$'\n'
			cmd+="MODE $chan +k $(random_string 5)"$'\n'
			cmd+="MODE $chan +k $(random_string 480)"$'\n'
			cmd+="MODE $chan +l $((RANDOM % 100 + 1))"$'\n'
			cmd+="MODE $chan -l $((RANDOM % 100 + 1))"$'\n'
			cmd+="MODE $chan -l "$'\n'
			cmd+="MODE $chan -ASFASF "$'\n'
			cmd+="MODE $chan -++ "$'\n'
			cmd+="MODE $chan % "$'\n'
			cmd+="MODE $chan * "$'\n'
			cmd+="MODE $chan ? "$'\n'
			cmd+="MODE $chan +o"$'\n'
			cmd+="MODE $chan -o $RNICK"$'\n'
			cmd+="MODE $chan +o $RNICK"$'\n'
		done
	fi

	cmd+="JOIN #test$RAND"$'\n'
	cmd+="MODE #test$RAND "$'\n'
	cmd+="MODE #test$RAND +i"$'\n'
	cmd+="MODE #test$RAND -i"$'\n'
	cmd+="MODE #test$RAND i"$'\n'
	cmd+="MODE #test$RAND -i"$'\n'
	cmd+="MODE #test$RAND +t"$'\n'
	cmd+="MODE #test$RAND -t"$'\n'
	cmd+="MODE #test$RAND t"$'\n'
	cmd+="MODE #test$RAND -k $(random_string 5)"$'\n'
	cmd+="MODE #test$RAND +k $(random_string 5)"$'\n'
	cmd+="MODE #test$RAND +k $(random_string 480)"$'\n'
	cmd+="MODE #test$RAND +l $((RANDOM % 100 + 1))"$'\n'
	cmd+="MODE #test$RAND -l $((RANDOM % 100 + 1))"$'\n'
	cmd+="MODE #test$RAND -l "$'\n'
	cmd+="MODE #test$RAND -ASFASF "$'\n'
	cmd+="MODE #test$RAND -++ "$'\n'
	cmd+="MODE #test$RAND % "$'\n'
	cmd+="MODE #test$RAND * "$'\n'
	cmd+="MODE #test$RAND ? "$'\n'
	cmd+="MODE #test$RAND +o"$'\n'
	cmd+="MODE #test$RAND -o $RNICK"$'\n'
	cmd+="MODE #test$RAND +o $RNICK"$'\n'
    cat <<EOF
PASS $PASSWORD
NICK $RNICK
USER $RUSER 0 * :ModeTest
$cmd
QUIT :Mode test done
EOF
}

# Send entirely invalid commands.
test_invalid_cmd() {
    local RAND=$((RANDOM % 100000))
    local RNICK="abot$RAND"
    local RUSER="legituser$RAND"
    cat <<EOF
PASS $PASSWORD
NICK $RNICK
USER $RUSER 0 * :CorrectAuth
INVALIDCOMMAND $(random_string 10)
FOOBAR $(random_string 10)
:$(random_string 10) $(random_string 20)
QUIT :Invalid test done
EOF
}

# Auth
test_auth() {
    local RAND=$((RANDOM % 100000))
    local RNICK="abot$RAND"
    local RUSER="legituser$RAND"
    cat <<EOF
PASS $PASSWORD
NICK $RNICK
USER $RUSER 0 * :CorrectAuth
QUIT :Auth test done
EOF
}

# Send auth commands in the wrong order.
test_incorrect_auth() {
    local RAND=$((RANDOM % 100000))
    local RNICK="iabot$RAND"
    local RUSER="incoruser$RAND"
    local RCHANNEL="#incor$RAND"
    cat <<EOF
NICK $RNICK
USER $RUSER 0 * :IncorrectAuth
PASS wrongpassword
JOIN $RCHANNEL
PRIVMSG $RCHANNEL :This should fail
QUIT :Incorrect auth test done
EOF
}

#  Authenticate correctly then attempt to re-authenticate.
test_re_auth() {
    local RAND=$((RANDOM % 100000))
    local RNICK="rabot$RAND"
    local RUSER="reauthuser$RAND"
    local RCHANNEL="#reauth$RAND"
    cat <<EOF
PASS $PASSWORD
NICK $RNICK
USER $RUSER 0 * :ReAuthTest
JOIN $RCHANNEL
PRIVMSG $RCHANNEL :Initial message
NICK newnick
USER newuser 0 * :Extra
PASS extraPass
PRIVMSG $RCHANNEL :This should trigger ERR_ALREADYREGISTRED
QUIT :ReAuth test done
EOF
}

#  Provide PASS and USER, but no NICK.
test_unfinished_auth() {
    local RAND=$((RANDOM % 100000))
    local RUSER="unfinuser$RAND"
    local RCHANNEL="#unfin$RAND"
    cat <<EOF
PASS $PASSWORD
USER $RUSER 0 * :UnfinishedAuth
PRIVMSG $RCHANNEL :Attempting command before nick
EOF
}

# Send completely random garbage input.
test_garbage() {
    local RAND=$((RANDOM % 100000))
    local RNICK="gbot$RAND"
    local RUSER="garbageuser$RAND"
    local RCHANNEL="#garbage$RAND"
    cat <<EOF
$(random_string 50)
$(random_string 100)
$(random_string 150)
$(random_string 250)
$(random_string 450)
$(random_string 508)
$(random_string 509)
$(random_string 510)
$(random_string 511)
$(random_string 512)
$(random_string 513)
$(random_string 650)
$(random_string 1650)
INVALID $(random_string 20)
:$(random_string 30) $(random_string 40)
PASS $PASSWORD
$(random_string 50)
$(random_string 100)
$(random_string 150)
$(random_string 250)
$(random_string 450)
$(random_string 508)
$(random_string 509)
$(random_string 510)
$(random_string 511)
$(random_string 512)
$(random_string 513)
$(random_string 650)
$(random_string 1650)
NICK $RNICK
$(random_string 50)
$(random_string 100)
$(random_string 150)
$(random_string 250)
$(random_string 450)
$(random_string 508)
$(random_string 509)
$(random_string 510)
$(random_string 511)
$(random_string 512)
$(random_string 513)
$(random_string 650)
$(random_string 1650)
USER $RUSER 0 * :garbageTest
$(random_string 50)
$(random_string 100)
$(random_string 150)
$(random_string 250)
$(random_string 450)
$(random_string 508)
$(random_string 509)
$(random_string 510)
$(random_string 511)
$(random_string 512)
$(random_string 513)
$(random_string 650)
$(random_string 1650)
JOIN $RCHANNEL
$(random_string 50)
$(random_string 100)
$(random_string 150)
$(random_string 250)
$(random_string 450)
$(random_string 508)
$(random_string 509)
$(random_string 510)
$(random_string 511)
$(random_string 512)
$(random_string 513)
$(random_string 650)
$(random_string 1650)
QUIT :Very much garbage
EOF
}

# Full set of test modes:
ALL_TESTS=(b j p P m i A x r u g)

run_test() {
    case "$1" in
        b)  test_basic ;;
        j)  test_join ;;
        p)  test_part ;;
        P)  test_privmsg ;;
        m)  test_mode ;;
        i)  test_invalid_cmd ;;
        A)  test_auth ;;
        x)  test_incorrect_auth ;;
        r)  test_re_auth ;;
        u)  test_unfinished_auth ;;
        g)  test_garbage ;;
        *)  echo "Error: Invalid test mode '$1'" >&2; exit 1 ;;
    esac
}

# Gather server info once before everything
echo "Gathering server information..."
get_info

if [ "$TEST_MODE" = "a" ]; then
    MODES_TO_RUN=("${ALL_TESTS[@]}")
else
    MODES_TO_RUN=("$TEST_MODE")
fi

echo "Starting stress test with modes: ${MODES_TO_RUN[*]}"
echo "Connections: $CONN_COUNT, Sleep time: $SLEEP_TIME, Timeout: $TIMEOUT"

for mode in "${MODES_TO_RUN[@]}"; do
    for ((i=0; i<CONN_COUNT; i++)); do
        CMD=$(run_test "$mode")
        echo "$CMD" | nc -C -w "$TIMEOUT" "$SERVER" "$PORT" &
        sleep "$SLEEP_TIME"
    done
done

wait
