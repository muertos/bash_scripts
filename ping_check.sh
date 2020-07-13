#!/usr/bin/env bash

# The purpose of this to ping a host and look for packet loss

# host is the first argument of this script
HOST=$1

# how many times to ping
COUNT=4

# how often in seconds to ping
INTERVAL=5

# ping HOST
ping -D -c ${COUNT} -i ${INTERVAL} ${HOST} >> $(pwd)/ping_results_${HOST}
