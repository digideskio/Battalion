#!/bin/bash

DOMAIN_SCAN_SCRIPTS=$SCRIPT_DIRECTORY/domain-scan/scripts

# 
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Part 1 - dnsrecon domain scan
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# 
echo "> Executing domain scan on ${DOMAIN_TARGET} using subdomain list ${DOMAIN_SUBDOMAIN_LIST}"

BASE_DOMAIN_REPORT=${DOMAIN_DIRECTORY}/base-domain-report.txt
A_RECORD_LIST=${DOMAIN_DIRECTORY}/a-records.txt
IP_ADDRESS_LIST=${DOMAIN_DIRECTORY}/a-record-ip-addresses.txt
SUBDOMAIN_LIST=${DOMAIN_DIRECTORY}/subdomains.txt
CNAME_LIST=${DOMAIN_DIRECTORY}/cnames.txt
HTTP_SUBDOMAIN_LIST=${DOMAIN_DIRECTORY}/http-subdomains.txt

${DOMAIN_SCAN_SCRIPTS}/run-domain-scan.sh \
    "${DOMAIN_TARGET}" 15 ${DOMAIN_SUBDOMAIN_LIST} \
    > ${BASE_DOMAIN_REPORT}

echo -e "\t- Successfully identified $(cat ${BASE_DOMAIN_REPORT} | wc -l) records."

# Produce a list of only the A records
${DOMAIN_SCAN_SCRIPTS}/filter-a-records.sh "${BASE_DOMAIN_REPORT}" \
    | tr '[:upper:]' '[:lower:]' \
    | uniq -i \
    > ${A_RECORD_LIST}

echo -e "\t- Filtered $(cat ${A_RECORD_LIST} | wc -l) unique A records."

# Produce a list of all IP Addresses of A records that match our primary domain name.
${DOMAIN_SCAN_SCRIPTS}/filter-ip-addresses.sh "${BASE_DOMAIN_REPORT}" "${DOMAIN_TARGET}" \
    | uniq -i \
    > ${IP_ADDRESS_LIST}

# Identify all valid subdomains that match our primary domain name.
${DOMAIN_SCAN_SCRIPTS}/filter-subdomains.sh "${BASE_DOMAIN_REPORT}" "${DOMAIN_TARGET}" \
    | tr '[:upper:]' '[:lower:]' \
    | uniq -i \
    > ${SUBDOMAIN_LIST}

echo -e "\t- Filtered $(cat ${SUBDOMAIN_LIST} | wc -l) unique subdomains."

# Map CNAME records back to IP addresses
${DOMAIN_SCAN_SCRIPTS}/map-cname-records.py "${DOMAIN_TARGET}" ${BASE_DOMAIN_REPORT} \
    > ${CNAME_LIST}

echo -e "\t- Mapped $(cat ${CNAME_LIST} | wc -l) CNAME records to IP addresses."

# Identify all subdomains that support HTTP(s) connections.
echo ""
echo "> Identifying domains that support HTTP(s) connections for additional scanning"

cat ${SUBDOMAIN_LIST} | ${DOMAIN_SCAN_SCRIPTS}/find-http-domains.sh "${DOMAIN_HTTP_SCAN_TIMEOUT}" \
    > ${HTTP_SUBDOMAIN_LIST}

echo -e "\t- Identified $(cat ${HTTP_SUBDOMAIN_LIST} | wc -l) subdomains that support HTTP(s)"

# 
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Part 2a - EyeWitness
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# 
echo ""
echo "> Using EyeWitness to visually inspect all HTTP(s) subdomains."

$DOMAIN_SCAN_SCRIPTS/eyewitness.sh $BATTALION_EYEWITNESS_HOME \
    $SCAN_DIRECTORY/eyewitness-report \
    $HTTP_SUBDOMAIN_LIST \
    $EYEWITNESS_TIMEOUT &

EYEWITNESS_PID=$!

# 
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Part 2b - WhatWeb
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# 
echo "> Using WhatWeb to analyze all HTTP(s) subdomains."

$DOMAIN_SCAN_SCRIPTS/whatweb.sh $WHATWEB_DIRECTORY $HTTP_SUBDOMAIN_LIST &
WHATWEB_PID=$!

#
# Part 2 - Wait for processes to complete.
#
echo ""
echo "> Waiting for EyeWitness and WhatWeb to complete..."
echo -e "\t+ EyeWitness abort:(kill $EYEWITNESS_PID)"
echo -e "\t+ WhatWeb    abort:(kill $WHATWEB_PID)"
echo ""

wait ${EYEWITNESS_PID}
wait ${WHATWEB_PID}

# 
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Part 3 - WhatWeb Filtering
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# 

WORDPRESS_LIST=$HTTP_DIRECTORY/wordpress-domains
$DOMAIN_SCAN_SCRIPTS/find-wordpress-domains.sh $WHATWEB_DIRECTORY \
    | uniq -i \
    > $WORDPRESS_LIST

echo "> Extracted $(cat $WORDPRESS_LIST | wc -l) domains using WordPress from WhatWeb results"

# 
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Part 4 - Nmap (If Enabled)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# 
if $NMAP_ENABLED ; then
    echo ""
    echo "> Executing Nmap scan on all subdomains."

    cat $SUBDOMAIN_LIST | uniq -i | $DOMAIN_SCAN_SCRIPTS/nmap-basic.sh $NMAP_DIRECTORY

    echo -e "\t- Produced $(ls -1 ${NMAP_DIRECTORY} | wc -l) NMap reports."
else
    echo ""
    echo "! Nmap disabled for this scan"
fi

# 
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Part 5 - WPScan for WordPress Domains
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# 
echo ""
echo "> Scanning $(cat ${WORDPRESS_LIST} | wc -l) domains for WordPress information and vulnerabilities."
$DOMAIN_SCAN_SCRIPTS/wpscan.sh $WORDPRESS_DIRECTORY $WORDPRESS_LIST

echo -e "\t- Executed $(ls -1 $WORDPRESS_DIRECTORY | wc -l) WordPress scans."


# 
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Part 6 - WHOIS 
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# 
echo ""
echo "> Parsing WHOIS report for ${DOMAIN_TARGET}"

${DOMAIN_SCAN_SCRIPTS}/whois.sh "${DOMAIN_TARGET}" $WHOIS_DIRECTORY


# 
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Part 7 - Shodan (If Enabled)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# 

if $SHODAN_ENABLED ; then
    echo ""
    echo "> Executing Shodan scan on $(cat $IP_ADDRESS_LIST | wc -l) IP addresses."

    cat $IP_ADDRESS_LIST | $DOMAIN_SCAN_SCRIPTS/shodan.sh $SHODAN_DIRECTORY "${SHODAN_API_KEY}"

    echo -e "\t- Produced $(ls -1 $SHODAN_DIRECTORY | wc -l) Shodan reports."
else
    echo ""
    echo "! Shodan disabled for this scan"
fi
