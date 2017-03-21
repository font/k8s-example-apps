#!/usr/bin/env bash
#
# Steps:
# 1. May need to first flush cache from https://developers.google.com/speed/public-dns/cache
#    but it's only for Publid DNS not Google Cloud DNS
# 2. sudo killall -HUP dnsmasq on localhost
# 3. See about enabling curl's --dns-servers feature (using c-ares) if
#    step 2 isn't enough. This appears to be feature AsyncDNS which curl
#    says is enabled...
#

URL="http://something.something.something.com/"
SLEEP_DURATION=5 # In seconds
GREP_CMD='grep -q pacman-canvas.js'
#DNS_SERVERS='ns-cloud-c1.googledomains.com,ns-cloud-c3.googledomains.com,ns-cloud-c2.googledomains.com,ns-cloud-c4.googledomains.com'
# curl manpage: The --dns-servers option requires that libcurl was built with a resolver
#               backend that supports this operation. The c-ares backend is  the
#               only such one.  (Added in 7.33.0)
#CHECK_CMD="curl -v --dns-servers ${DNS_SERVERS} -H \"Cache-Control: no-cache, no-store, must-revalidate\" ${URL} 2>&1 | ${GREP_CMD}"
CHECK_CMD="curl -v -H \"Cache-Control: no-cache, no-store, must-revalidate\" ${URL} 2>&1 | ${GREP_CMD}"
DATE='date +%Y-%m-%d_%T'
OK_STATUS="Pac-Man OK"
FAILED_STATUS="Pac-Man FAILED"

while true; do
    if eval ${CHECK_CMD}; then
        echo $(${DATE}) ${OK_STATUS}
    else
        echo $(${DATE}) ${FAILED_STATUS}
        break
    fi
    sudo killall -HUP dnsmasq
    sleep ${SLEEP_DURATION}
done
