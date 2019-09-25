#!/bin/bash

# Colors ##########################################################################
CSI="\\033["
CEND="${CSI}0m"
CRED="${CSI}1;31m"
CGREEN="${CSI}1;32m"
###################################################################################

# Check for config file ###########################################################
if [ -f "./.nginfix.cfg" ]; then
	source ./.nginfix.cfg
else
	clear
	echo "No config file found."
	read -rp "Do you want to download a sample config file? [y/n] " REPLY_CONFIG
	if [[ $REPLY_CONFIG =~ ^[Yy]$ ]]; then
		wget https://raw.githubusercontent.com/TheForcer/nginfix/master/.nginfix.cfg.sample
		echo "Please edit the just downloaded .nginfix.cfg.sample file and fill in your details."
		echo "Rename/move the file to .nginfix.cfg afterwards, so that it can be used."
		exit 1
	else
		exit 1
	fi
fi
###################################################################################

# Menu ############################################################################
clear
echo ""
echo -e "${CGREEN}Welcome to nginfix! (INWX version)${CEND}"
echo ""
echo "What do you want to do?"
echo "   1) Add a new A+AAAA record to INWX"
echo "   2) Remove a A+AAAA record from INWX"
echo "   3) Add a new NGINX virtual host"
echo "   4) Remove a NGINX virtual host"
echo "   5) Install a LetsEncrypt Wildcard certificate via acme.sh"
echo "   6) Force LetsEncrypt Wildcard certificate renewal"
echo "   7) Install / Update NGINX"
echo "   9) Exit"
echo ""

while [[ $OPTION !=  "1" && $OPTION !=  "2" && $OPTION !=  "3" && $OPTION !=  "4" && $OPTION !=  "5" && $OPTION !=  "6" && $OPTION !=  "7" && $OPTION !=  "9" ]]; 
do
	read -rp "Select an option [1-9]: " OPTION
done
###################################################################################

# General functions ###############################################################
function domainCheck {
	# Check if input is a domain/subdomain and set variable accordingly
	if [[ ! "$FQDN" =~ (^[A-Za-z0-9._%+-]*\.*[A-Za-z0-9.-]+\.[A-Za-z]{2,10}$) ]]; then
		FQDNVALID=false
	else
		FQDNVALID=true
	fi
}

function domainRegex {
	# Separate input into subdomain and domain. Subdomain is empty if domain only
	DOMAIN=$(echo "$FQDN" | grep -E -o '([-\_0-9a-z]+\.[a-z0-9]+)$')
	SUBDOMAIN=$(echo "$FQDN" | sed -e "s/.$DOMAIN//")
	if [[ "$DOMAIN" = "$SUBDOMAIN" ]]; then
		SUBDOMAIN=""
	fi
}

function rootCheck {
	# Check if script is run as root user
	if [[ "$EUID" -ne 0 ]] ; then
		echo -e "${CRED}Sorry, for this module you need to run the script as root/sudo${CEND}"
		exit 1
	fi
}

function createRecords {
	# API call to INWX to create A/AAAA records
	XMLDATA=$(curl -s -N https://raw.githubusercontent.com/TheForcer/nginfix/master/createA.api | sed "s/%PASSWD%/$PASSWORD/g;s/%USER%/$USERNAME/g;s/%DOMAIN%/$DOMAIN/g;s/%SUBDOMAIN%/$SUBDOMAIN/g;s/%IPV4%/$IPV4/g;")
	RET=$(curl -s -X POST -d "$XMLDATA" "$APIHOST" --header "Content-Type:text/xml")
	# check success of record creation
	if ! grep -q "Command completed successfully" <<< "$RET"; then
		echo -e "${CRED}Something went wrong with the record creation. Please double-check your credentials and the FQDN you entered.${CEND}"
		exit 1
	else
		echo "Your new A record has been successfully created. Creating AAAA record now..."
		XMLDATA=$(curl -s -N https://raw.githubusercontent.com/TheForcer/nginfix/master/createAAAA.api | sed "s/%PASSWD%/$PASSWORD/g;s/%USER%/$USERNAME/g;s/%DOMAIN%/$DOMAIN/g;s/%SUBDOMAIN%/$SUBDOMAIN/g;s/%IPV6%/$IPV6/g;")
		RET=$(curl -s -X POST -d "$XMLDATA" "$APIHOST" --header "Content-Type:text/xml")
		if grep -q "Command completed successfully" <<< "$RET"; then
			echo -e "${CGREEN}Finished creating the DNS records! Exiting now...${CEND}"
		exit
		fi
	fi
}

function deleteRecords {
	# API call to INWX to delete A/AAAA records
	XMLDATA=$(curl -s -N https://raw.githubusercontent.com/TheForcer/nginfix/master/getInfo.api | sed "s/%PASSWD%/$PASSWORD/g;s/%USER%/$USERNAME/g;s/%DOMAIN%/$DOMAIN/g;s/%SUBDOMAIN%/$SUBDOMAIN/g;")
	RET=$(curl -s -X POST -d "$XMLDATA" "$APIHOST" --header "Content-Type:text/xml")
	#check success of domain lookup
	if ! grep -q "Command completed successfully" <<< "$RET"; then
		echo -e "${CRED}Something went wrong with the domain lookup. Please double-check your credentials and the FQDN you entered.${CEND}"
		exit 1
	else
		IDS=($(echo "$RET" | grep -E -o '<int>[0-9]+<\/int><\/value><\/member><member><name>name<\/name><value><string>[A-Za-z.-]*<\/string><\/value><\/member><member><name>type<\/name><value><string>(A|AAAA)<\/string>' | grep -E -o '[0-9]+'))
		for id in ${IDS[*]}
		do
			echo "Deleting record $id ..."
			XMLDATA=$(curl -s -N https://raw.githubusercontent.com/TheForcer/nginfix/master/deleteRecord.api | sed "s/%PASSWD%/$PASSWORD/g;s/%USER%/$USERNAME/g;s/%ID%/$id/g;")
			RET=$(curl  -s -X POST -d "$XMLDATA" "$APIHOST" --header "Content-Type:text/xml")
		done
		echo -e "${CGREEN}Finished removing the INWX records. Exiting now...${CEND}"	
	fi
}

function createVhost {
	# Create new nginx virtual host config + required directories
	# define location variables
	ROOTDIR="/var/www/$FQDN/html"
	CONF="/etc/nginx/sites-available/$FQDN"
	mkdir -p "$ROOTDIR"
	chown -R $NGINXUSER:$NGINXUSER "$ROOTDIR"
	# create NGINX block
	curl -s -N https://raw.githubusercontent.com/TheForcer/nginfix/master/nginx_default.conf | sed "s/%FQDN%/$FQDN/g;s/%DOMAIN%/$DOMAIN/g;s!%ROOTDIR%!$ROOTDIR!g" > "$CONF"
	ln -s "$CONF" /etc/nginx/sites-enabled/"$FQDN"
	if ! nginx -t; then
		echo -e "${CRED}Something is wrong with the NGINX configuration. Please double-check your config in /etc/nginx.${CEND}"
		rm -rf /var/www/"$FQDN" && rm -f "$CONF" && rm -f /etc/nginx/sites-enabled/"$FQDN"
		exit 1
	else
		nginx -s reload
		echo -e "${CGREEN}Finished creating the new NGINX vhost. NGINX has been reloaded as well. Exiting now...${CEND}"
		exit
	fi
}

function deleteVhost {
	# Delete existing nginx virtual host config + related directories
	if ! grep -q "proxy_pass" /etc/nginx/sites-available/"$FQDN"; then
		rm -rf /var/www/"$FQDN" && rm -f /etc/nginx/sites-available/"$FQDN" && rm -f /etc/nginx/sites-enabled/"$FQDN"
	else
		rm -f /etc/nginx/sites-available/"$FQDN" && rm -f /etc/nginx/sites-enabled/"$FQDN"
	fi
	nginx -s reload
	echo -e "${CGREEN}Finished removing the subdomain. Exiting...${CEND}"
}

function createProxyVhost {
	# Create a new proxy nginx virtual host config
	CONF="/etc/nginx/sites-available/$FQDN"
	curl -s -N https://raw.githubusercontent.com/TheForcer/nginfix/master/nginx_proxy.conf | sed "s/%FQDN%/$FQDN/g;s/%DOMAIN%/$DOMAIN/g;s!%PORT%!$PORT!g;s!%APPNAME%!$APPNAME!g" > "$CONF"
	ln -s "$CONF" /etc/nginx/sites-enabled/"$FQDN"
	if ! nginx -t; then
		echo -e "${CRED}Something is wrong with the NGINX configuration. Please double-check your config in /etc/nginx.${CEND}"
		rm -f "$CONF" && rm -f /etc/nginx/sites-enabled/"$FQDN"
		exit 1
	else
		nginx -s reload
		echo -e "${CGREEN}Finished creating the new NGINX vhost. NGINX has been reloaded as well. Exiting now...${CEND}"
	fi
}

function installAcme {
	# download & install acme.sh and enable automatic upgrades
	cd /root/ || exit
	echo -e "${CGREEN}Downloading acme.sh ...${CEND}"
	(git clone https://github.com/Neilpang/acme.sh.git) 2> /dev/null
	echo -e "${CGREEN}Installing acme.sh ...${CEND}"
	cd ./acme.sh || exit
	(./acme.sh --install) 2> /dev/null
	echo -e "${CGREEN}Setting up automatic updates for acme.sh ...${CEND}"
	(./acme.sh --upgrade --auto-upgrade --force) 2> /dev/null
}

function checkCertReceival {
	# Check if certifcates were requested successfully
	if ! grep -q "Cert success." <<< "$RET"; then
		echo -e "${CRED}Something went wrong with the certificate creation. Please double-check your credentials and the domain you entered.${CEND}"
		exit 1
	fi
	case "$1" in
        ecc)
            echo -e "${CGREEN}Your ECC wildcard certificate has been successfully created. You will find your files here:${CEND}"
			echo ""
			echo -e "	Certificate:  /root/.acme.sh/${DOMAIN}_ecc/$DOMAIN.cer"
			echo -e "	Private Key:  /root/.acme.sh/${DOMAIN}_ecc/$DOMAIN.key"
			echo -e "	Intermediate Certificate:  /root/.acme.sh/${DOMAIN}_ecc/ca.cer"
			echo -e "	Full Chain Certificate:  /root/.acme.sh/${DOMAIN}_ecc/fullchain.cer"
			echo ""
            ;;
        rsa)
            echo -e "${CGREEN}Your RSA wildcard certificate has been successfully created. You will find your files here:${CEND}"
			echo ""
			echo -e "	Certificate:  /root/.acme.sh/${DOMAIN}/$DOMAIN.cer"
			echo -e "	Private Key:  /root/.acme.sh/${DOMAIN}/$DOMAIN.key"
			echo -e "	Intermediate Certificate:  /root/.acme.sh/${DOMAIN}/ca.cer"
			echo -e "	Full Chain Certificate:  /root/.acme.sh/${DOMAIN}/fullchain.cer"
			echo ""
            ;;
	esac
}

function issueWildcardECC {
	# Issue a Wildcard ECC certificate via acme.sh
	#TYPE="ecc"
	echo -e "${CGREEN}Requesting ECC certificate ...${CEND}"
	echo "The following process takes about 30 seconds, as acme.sh has to wait before verifying the created domain entries. Please stand by..."
	RET=$(./acme.sh --issue --dns dns_inwx --dnssleep 30 -d "$DOMAIN" -d "*.$DOMAIN" --keylength ec-384 --ocsp)
	checkCertReceival "ecc"
}

function issueWildcardRSA {
	# Issue a Wildcard RSA certificate via acme.sh
	#TYPE="rsa"
	echo -e "${CGREEN}Requesting RSA certificate ...${CEND}"
	RET=$(./acme.sh --issue --dns dns_inwx --dnssleep 30 -d "$DOMAIN" -d "*.$DOMAIN" --keylength 4096 --ocsp)
	checkCertReceival "rsa"
}

function forceRenewal {
	# Force acme.sh to renew existing RSA/ECC certificates
	cd /root/.acme.sh || exit
	echo -e "${CGREEN}Renewing ECC certificate ...${CEND}"
	echo "The following process can take about 30 seconds, as acme.sh has to wait before verifying the newly created domain entries. Please stand by..."
	RET=$(./acme.sh --renew --dnssleep 30 -d "$DOMAIN" -d "*.$DOMAIN" --force --ecc)
	checkCertReceival "ecc"
	if [[ -d /root/.acme.sh/$DOMAIN/ ]]; then
		echo -e "${CGREEN}Renewing RSA certificate ...${CEND}"
		echo "The following process can take about 30 seconds, as acme.sh has to wait before verifying the newly created domain entries. Please stand by..."
		RET=$(./acme.sh --renew --dnssleep 30 -d "$DOMAIN" -d "*.$DOMAIN" --force)
		checkCertReceival "rsa"
	fi
}
###################################################################################

# Switch case #####################################################################
case $OPTION in
	1)  # add INWX subdomain
		while [[ $FQDNVALID == false ]] || [[ -z "$FQDNVALID" ]];
		do
			read -rp "Please enter the FQDN of the new record (eg. example.com, sub.example.com): " FQDN
			domainCheck
		done
		domainRegex
		createRecords
	exit
    ;;

	2)  # remove INWX subdomain
		while [[ $FQDNVALID == false ]] || [[ -z "$FQDNVALID" ]];
		do
			read -rp "Please enter the FQDN of the record you want to remove (eg. example.com, sub.example.com): " FQDN
			domainCheck
		done
		domainRegex
		deleteRecords
	exit
	;;

	3)  # add virtual host
		rootCheck
		if ! [[ -d /root/.acme.sh/ ]] 
		then
			echo -e "${CRED}It seems that you do not have the acme.sh client installed. Please complete step 5 in the script first.${CEND}"
			exit 1
		fi
		read -rp "Do you want to create a virtual host that proxies to another service/port? [y/n] " REPLY_PROXY
		while [[ $FQDNVALID == false ]] || [[ -z "$FQDNVALID" ]];
		do
			read -rp "Please enter the new complete FQDN (eg. example.com, sub.example.com): " FQDN
			domainCheck
		done
		if [[ $REPLY_PROXY =~ ^[Yy]$ ]]; then
			read -rp "On which port is the application listening? (eg. 8080): " PORT
			read -rp "What is the name of the application (for nginx logs): " APPNAME
			domainRegex
			createProxyVhost
		else
			domainRegex
			createVhost
		fi
	exit
	;;

	4)  # remove virtual host
		rootCheck
		echo -e "${CRED}WARNING: This will delete the NGINX config file as well as the content of the FQDN's root directory, if one exists.${CEND}"
		while [[ $FQDNVALID == false ]] || [[ -z "$FQDNVALID" ]];
		do
			read -rp "Please enter the FQDN you want to remove (eg. example.com, sub.example.com): " FQDN
			domainCheck
		done
		read -rp "Please enter the FQDN again: " FQDN2
		if [[ "$FQDN" == "$FQDN2" ]]; then
			deleteVhost
		else
			echo -e "${CRED}It seems you misstyped one of the domains. Please try again.${CEND}"
			exit 1
		fi
	exit
	;;

	5)  # install acme.sh
		rootCheck
		while [[ $FQDNVALID == false ]] || [[ -z "$FQDNVALID" ]];
		do
			read -rp "Please enter the domain you want to issue the wildcard certificate to (eg. example.com): " FQDN
			domainCheck
			domainRegex
		done
		# define INWX credentials for acme.sh
		export INWX_User=$USERNAME && export INWX_Password=$PASSWORD
		installAcme
		issueWildcardECC
		read -rp "Do you want to install a RSA wildcard certificate as well? [y/n] " REPLY
		if [[ $REPLY =~ ^[Yy]$ ]]; then
			issueWildcardRSA
		fi
	exit
	;;
	
	6)  # force certificate renewal
		rootCheck
		while [[ $FQDNVALID == false ]] || [[ -z "$FQDNVALID" ]];
		do
			read -rp "Please enter the domain of the certificate you want to renew (eg. example.com): " FQDN
			domainCheck
			domainRegex
		done
		forceRenewal
	exit
	;;	
	
	7)  # nginx installer script
		rootCheck
		read -rp "Do you want to automatically install nginx with my preferred settings? [y/n] " REPLY
		if [[ $REPLY =~ ^[Yy]$ ]]; then
			wget -N https://raw.githubusercontent.com/Angristan/nginx-autoinstall/master/nginx-autoinstall.sh
			chmod +x nginx-autoinstall.sh
			sed -i "2a HEADLESS=y" nginx-autoinstall.sh
			sed -i "s/NGINX_VER=\${NGINX_VER:-1}/NGINX_VER=2/g" nginx-autoinstall.sh
			sed -i "s/SSL=\${SSL:-1}/SSL=2/g" nginx-autoinstall.sh
			sed -i "s/RM_CONF=\${RM_CONF:-y}/RM_CONF=\"n\"/g" nginx-autoinstall.sh
			sed -i "s/RM_CONF=\${RM_LOGS:-y}/RM_LOGS=\"n\"/g" nginx-autoinstall.sh
			sudo bash nginx-autoinstall.sh
			sudo wget -N https://raw.githubusercontent.com/TheForcer/nginfix/master/tls.conf -O /etc/nginx/tls.conf
			sudo wget -N https://raw.githubusercontent.com/TheForcer/nginfix/master/nginx.conf -O /etc/nginx/nginx.conf
			sudo nginx -s reload
		fi
	exit
	;;
	
	9)
		clear
		exit
	;;
esac
###################################################################################