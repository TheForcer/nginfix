#!/bin/bash

# Configuration INWX credentials / Server IPs #####################################
USERNAME=""
PASSWORD=""
APIHOST="https://api.domrobot.com/xmlrpc/"
IPV4=""
IPV6=""
NGINXUSER="www-data"
###################################################################################

# Colors ##########################################################################
CSI="\033["
CEND="${CSI}0m"
CRED="${CSI}1;31m"
CGREEN="${CSI}1;32m"
###################################################################################

# Menu ############################################################################
clear
echo ""
echo -e "${CGREEN}Welcome to nginfix! (INWX version)${CEND}"
echo ""
echo "What do you want to do?"
echo "   1) Add a new subdomain to INWX"
echo "   2) Remove a subdomain from INWX"
echo "   3) Add a new NGINX vhost/subdomain"
echo "   4) Remove a NGINX vhost/subdomain"
echo "   5) Install a LetsEncrypt Wildcard certificate via acme.sh"
echo "   6) Force LetsEncrypt Wildcard certificate renewal"
echo "   7) Install / Update / Remove NGINX"
echo "   8) Add a new NGINX proxy vhost/subdomain"
echo "   9) Exit"
echo ""

while [[ $OPTION !=  "1" && $OPTION !=  "2" && $OPTION !=  "3" && $OPTION !=  "4" && $OPTION !=  "5" && $OPTION !=  "6" && $OPTION !=  "7" && $OPTION !=  "8" && $OPTION !=  "9" ]]; 
do
	read -p "Select an option [1-9]: " OPTION
done
###################################################################################

# General functions ###############################################################
function domainRegex {
	DOMAIN=$(echo $FQDN | egrep -o '([-\_0-9a-z]+\.[a-z0-9]+)$')
	SUBDOMAIN=$(echo $FQDN | egrep -o '^[a-z0-9]+')
}

function rootCheck {
	if [[ "$EUID" -ne 0 ]] 
	then
		echo -e "${CRED}Sorry, for this module you need to run the script as root/sudo${CEND}"
		exit 1
	fi
}

function createRecords {
	XMLDATA=$(curl -s -N https://raw.githubusercontent.com/TheForcer/nginfix/master/createA.api | sed "s/%PASSWD%/$PASSWORD/g;s/%USER%/$USERNAME/g;s/%DOMAIN%/$DOMAIN/g;s/%SUBDOMAIN%/$SUBDOMAIN/g;s/%IPV4%/$IPV4/g;")
	RET=$(curl  -s -X POST -d "$XMLDATA" "$APIHOST" --header "Content-Type:text/xml")
	# check success of record creation
	if ! grep -q "Command completed successfully" <<< "$RET";
	then
		echo -e "${CRED}Something went wrong with the record creation. Please double-check your credentials and the FQDN you entered.${CEND}"
		exit 1
	else
		echo "Your new A record has been successfully created. Creating AAAA record now..."
		XMLDATA=$(curl -s -N https://raw.githubusercontent.com/TheForcer/nginfix/master/createAAAA.api | sed "s/%PASSWD%/$PASSWORD/g;s/%USER%/$USERNAME/g;s/%DOMAIN%/$DOMAIN/g;s/%SUBDOMAIN%/$SUBDOMAIN/g;s/%IPV6%/$IPV6/g;")
		RET=$(curl  -s -X POST -d "$XMLDATA" "$APIHOST" --header "Content-Type:text/xml")
		if grep -q "Command completed successfully" <<< "$RET";
		then
			echo -e "${CGREEN}Finished creating the DNS records! Exiting now...${CEND}"
		exit
		fi
	fi
}

function deleteRecords {
	XMLDATA=$(curl -s -N https://raw.githubusercontent.com/TheForcer/nginfix/master/getInfo.api | sed "s/%PASSWD%/$PASSWORD/g;s/%USER%/$USERNAME/g;s/%DOMAIN%/$DOMAIN/g;s/%SUBDOMAIN%/$SUBDOMAIN/g;")
	RET=$(curl  -s -X POST -d "$XMLDATA" "$APIHOST" --header "Content-Type:text/xml")
	# check success of domain lookup
	if ! grep -q "Command completed successfully" <<< "$RET";
	then
		echo -e "${CRED}Something went wrong with the domain lookup. Please double-check your credentials and the FQDN you entered.${CEND}"
		exit 1
	else
		IDS=($(echo $RET | egrep -o '<name>id</name><value><int>[0-9]+' | egrep -o '[0-9]+'))
		for id in ${IDS[*]}
		do
			echo "Deleting record $id ..."
			XMLDATA=$(curl -s -N https://raw.githubusercontent.com/TheForcer/Scripts/master/inwx_nginx/deleteRecord.api | sed "s/%PASSWD%/$PASSWORD/g;s/%USER%/$USERNAME/g;s/%ID%/$id/g;")
			RET=$(curl  -s -X POST -d "$XMLDATA" "$APIHOST" --header "Content-Type:text/xml")
		done
		echo -e "${CGREEN}Finished removing the INWX records. Exiting now...${CEND}"	
	fi
}

function createVhost {
	# define location variables
	ROOTDIR="/var/www/$FQDN/html"
	CONF="/etc/nginx/sites-available/$FQDN"
	mkdir -p $ROOTDIR
	chown -R $NGINXUSER:$NGINXUSER $ROOTDIR
	# create NGINX block
	curl -s -N https://raw.githubusercontent.com/TheForcer/nginfix/master/nginx_default.conf | sed "s/%FQDN%/$FQDN/g;s/%DOMAIN%/$DOMAIN/g;s!%ROOTDIR%!$ROOTDIR!g" > $CONF
	ln -s $CONF /etc/nginx/sites-enabled/$FQDN
	if ! nginx -t
	then
		echo -e "${CRED}Something is wrong with the NGINX configuration. Please double-check your config in /etc/nginx.${CEND}"
		rm -rf /var/www/$FQDN && rm -f $CONF $$ rm -f /etc/nginx/sites-enabled/$FQDN
		exit 1
	else
		nginx -s reload
		echo -e "${CGREEN}Finished creating the new NGINX vhost. NGINX has been reloaded as well. Exiting now...${CEND}"
		exit
	fi
}

function deleteVhost {
	rm -rf /var/www/$FQDN && rm -f /etc/nginx/sites-available/$FQDN $$ rm -f /etc/nginx/sites-enabled/$FQDN
	nginx -s reload
	echo -e "${CGREEN}Finished removing the subdomain. Exiting...${CEND}"
}

function createProxyVhost {
	CONF="/etc/nginx/sites-available/$FQDN"
	curl -s -N https://raw.githubusercontent.com/TheForcer/nginfix/master/nginx_proxy.conf | sed "s/%FQDN%/$FQDN/g;s/%DOMAIN%/$DOMAIN/g;s!%PORT%!$PORT!g;s!%APPNAME%!$APPNAME!g" > $CONF
	ln -s $CONF /etc/nginx/sites-enabled/$FQDN
	if ! nginx -t
	then
		echo -e "${CRED}Something is wrong with the NGINX configuration. Please double-check your config in /etc/nginx.${CEND}"
		rm -f $CONF $$ rm -f /etc/nginx/sites-enabled/$FQDN
		exit 1
	else
		nginx -s reload
		echo -e "${CGREEN}Finished creating the new NGINX vhost. NGINX has been reloaded as well. Exiting now...${CEND}"
	fi
}

function installAcme {
	# download & install acme.sh
	cd /root/
	echo -e "${CGREEN}Downloading acme.sh ...${CEND}"
	(git clone https://github.com/Neilpang/acme.sh.git) 2> /dev/null
	echo -e "${CGREEN}Installing acme.sh ...${CEND}"
	cd ./acme.sh 
	(./acme.sh --install) 2> /dev/null
}

function checkCertReceival {
	if ! grep -q "Cert success." <<< "$RET";
	then
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
	TYPE="ecc"
	echo -e "${CGREEN}Requesting ECC certificate ...${CEND}"
	echo "The following process takes about 2+ minutes, as acme.sh has to wait before verifying the created domain entries. Please stand by..."
	RET=$(./acme.sh --issue --dns dns_inwx -d $DOMAIN -d *.$DOMAIN --keylength ec-384)
	checkCertReceival "ecc"
}

function issueWildcardRSA {
	TYPE="rsa"
	echo -e "${CGREEN}Requesting RSA certificate ...${CEND}"
	RET=$(./acme.sh --issue --dns dns_inwx -d $DOMAIN -d *.$DOMAIN --keylength 4096)
	checkCertReceival "rsa"
}

function forceRenewal {
	cd /root/.acme.sh
	echo -e "${CGREEN}Renewing ECC certificate ...${CEND}"
	echo "The following process can take about 2+ minutes, as acme.sh has to wait before verifying the newly created domain entries. Please stand by..."
	RET=$(./acme.sh --renew -d $DOMAIN -d *.$DOMAIN --force --ecc)
	checkCertReceival "ecc"
	if [[ -d /root/.acme.sh/$DOMAIN/ ]]
	then
		echo -e "${CGREEN}Renewing RSA certificate ...${CEND}"
		echo "The following process can take about 2+ minutes, as acme.sh has to wait before verifying the newly created domain entries. Please stand by..."
		RET=$(./acme.sh --renew -d $DOMAIN -d *.$DOMAIN --force)
		checkCertReceival "rsa"
	fi
}
###################################################################################

# Switch case #####################################################################
case $OPTION in
	1)  # add INWX subdomain
		read -p "Please enter the new complete FQDN (eg. test.example.com): " FQDN
		domainRegex
		createRecords
	exit
    ;;

	2)  # remove INWX subdomain
		read -p "Please enter the FQDN you want to remove (eg. test.example.com): " FQDN
		domainRegex
		deleteRecords
	exit
	;;

	3)  # add vhost
		rootCheck
		if ! [[ -d /root/.acme.sh/ ]] 
		then
			echo -e "${CRED}It seems that you do not have the acme.sh client installed. Please complete step 5 in the script first.${CEND}"
			exit 1
		fi
		read -p "Please enter the new complete FQDN (eg. test.example.com): " FQDN
		domainRegex
		createVhost
	exit
	;;

	4)  # remove vhost
		rootCheck
		echo -e "${CRED}WARNING: This will delete the NGINX config files as well as the content of the FQDN's root directory.${CEND}"
		read -p "Please enter the FQDN you want to remove (eg. test.example.com): " FQDN
		read -p "Please enter the FQDN again: " FQDN2
		if [[ "$FQDN" == "$FQDN2" ]]
		then
			deleteVhost
		else
			echo -e "${CRED}It seems you misstyped one of the domains. Please try again.${CEND}"
			exit 1
		fi

	exit
	;;

	5)  # install acme.sh
		rootCheck
		read -p "Please enter the domain you want to issue the wildcard certificate to (eg. example.com): " DOMAIN
		# define INWX credentials for acme.sh
		export INWX_User=$USERNAME && export INWX_Password=$PASSWORD
		installAcme
		issueWildcardECC
		read -p "Do you want to install a RSA wildcard certificate as well? [y/n] " REPLY
		if [[ $REPLY =~ ^[Yy]$ ]]
		then
			issueWildcardRSA
		fi
	exit
	;;
	
	6)  # force certificate renewal
		rootCheck
		read -p "Please enter the domain of the certificate you want to renew (eg. example.com): " DOMAIN
		forceRenewal
	exit
	;;	
	
	7)  # nginx installer script
		wget -N https://raw.githubusercontent.com/Angristan/nginx-autoinstall/master/nginx-autoinstall.sh
		chmod +x nginx-autoinstall.sh
		sudo bash nginx-autoinstall.sh
		sed -i "s/\.conf//g;" /etc/nginx/nginx.conf
	exit
	;;

	8)  # add proxy vhost
		rootCheck
		if ! [[ -d /root/.acme.sh/ ]]
		then
			echo -e "${CRED}It seems that you do not have the acme.sh client installed. Please complete step 5 in the script first.${CEND}"
			exit 1
		fi
		read -p "Please enter the new complete FQDN (eg. test.example.com): " FQDN
		read -p "On which port is the application listening? (eg. 8080): " PORT
		read -p "What is the name of the application (for nginx logs): " APPNAME
		domainRegex
		createProxyVhost
	exit
	;;	
	
	9)
		clear
		exit
	;;
esac
###################################################################################