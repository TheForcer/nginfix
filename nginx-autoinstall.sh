#!/bin/bash

if [[ "$EUID" -ne 0 ]]; then
	echo -e "Sorry, you need to run this as root"
	exit 1
fi

# Define versions
NGINX_MAINLINE_VER=1.17.4
NGINX_STABLE_VER=1.16.1
LIBRESSL_VER=2.9.2
OPENSSL_VER=1.1.1c
LIBMAXMINDDB_VER=1.3.2
GEOIP2_VER=3.2
OWASP_VER=3.2.0

# Define installation paramaters for headless install (fallback if unspecifed)
if [[ "$HEADLESS" == "y" ]]; then
	OPTION=${OPTION:-1}
	NGINX_VER=${NGINX_VER:-1}
	GEOIP=${GEOIP:-n}
	FANCYINDEX=${FANCYINDEX:-n}
	CACHEPURGE=${CACHEPURGE:-n}
	WEBDAV=${WEBDAV:-n}
	VTS=${VTS:-n}
	SSL=${SSL:-1}
	RM_CONF=${RM_CONF:-y}
	RM_LOGS=${RM_LOGS:-y}
fi

# Clean screen before launching menu
if [[ "$HEADLESS" == "n" ]]; then
	clear
fi

if [[ "$HEADLESS" != "y" ]]; then
	echo ""
	echo "Welcome to the nginx-autoinstall script."
	echo ""
	echo "What do you want to do?"
	echo "   1) Install or update Nginx"
	echo "   2) Uninstall Nginx"
	echo "   3) Update the script"
	echo "   4) Install OWASP ModSecurity ruleset"
	echo "   5) Exit"
	echo ""
	while [[ $OPTION !=  "1" && $OPTION != "2" && $OPTION != "3" && $OPTION != "4" && $OPTION != "5" ]]; do
		read -rp "Select an option [1-5]: " OPTION
	done
fi

case $OPTION in
	1)
		if [[ "$HEADLESS" != "y" ]]; then
			echo ""
			echo "This script will install Nginx with some optional modules."
			echo ""
			echo "Do you want to install Nginx stable or mainline?"
			echo "   1) Stable $NGINX_STABLE_VER"
			echo "   2) Mainline $NGINX_MAINLINE_VER"
			echo ""
			while [[ $NGINX_VER != "1" && $NGINX_VER != "2" ]]; do
				read -rp "Select an option [1-2]: " NGINX_VER
			done
		fi
		case $NGINX_VER in
			1)
			NGINX_VER=$NGINX_STABLE_VER
			;;
			2)
			NGINX_VER=$NGINX_MAINLINE_VER
			;;
			*)
			echo "NGINX_VER unspecified, fallback to stable $NGINX_STABLE_VER"
			NGINX_VER=$NGINX_STABLE_VER
			;;
		esac
		if [[ "$HEADLESS" != "y" ]]; then
			echo ""
			echo "Please tell me which modules you want to install."
			echo "If you select none, Nginx will be installed with its default modules."
			echo ""
			echo "Modules to install :"
			while [[ $GEOIP != "y" && $GEOIP != "n" ]]; do
				read -rp "       GeoIP [y/n]: " -e GEOIP
			done
			while [[ $FANCYINDEX != "y" && $FANCYINDEX != "n" ]]; do
				read -rp "       Fancy index [y/n]: " -e FANCYINDEX
			done
			while [[ $CACHEPURGE != "y" && $CACHEPURGE != "n" ]]; do
				read -rp "       ngx_cache_purge [y/n]: " -e CACHEPURGE
			done
			while [[ $WEBDAV != "y" && $WEBDAV != "n" ]]; do
				read -rp "       nginx WebDAV [y/n]: " -e WEBDAV
			done
			while [[ $VTS != "y" && $VTS != "n" ]]; do
				read -rp "       nginx VTS [y/n]: " -e VTS
			done
			while [[ $MODSEC != "y" && $MODSEC != "n" ]]; do
				read -rp "       ModSecurity 3.0 [y/n]: " -e MODSEC
			done			
			echo ""
			echo "Choose your OpenSSL implementation :"
			echo "   1) System's OpenSSL ($(openssl version | cut -c9-14))"
			echo "   2) OpenSSL $OPENSSL_VER from source"
			echo "   3) LibreSSL $LIBRESSL_VER from source "
			echo ""
			while [[ $SSL != "1" && $SSL != "2" && $SSL != "3" ]]; do
				read -rp "Select an option [1-3]: " SSL
			done
		fi
		case $SSL in
			1)
			;;
			2)
				OPENSSL=y
			;;
			3)
				LIBRESSL=y
			;;
			*)
				echo "SSL unspecified, fallback to system's OpenSSL ($(openssl version | cut -c9-14))"
			;;
		esac
		if [[ "$HEADLESS" != "y" ]]; then
			echo ""
			read -n1 -r -p "Nginx is ready to be installed, press any key to continue..."
			echo ""
		fi

		# Cleanup
		# The directory should be deleted at the end of the script, but in case it fails
		rm -r /usr/local/src/nginx/ >> /dev/null 2>&1
		mkdir -p /usr/local/src/nginx/modules

		# Dependencies
		apt-get update
		apt-get install -y build-essential ca-certificates wget curl libpcre3 libpcre3-dev autoconf unzip automake libtool tar git libssl-dev zlib1g-dev uuid-dev lsb-release libxml2-dev libxslt1-dev

		# GeoIP
		if [[ "$GEOIP" = 'y' ]]; then
			cd /usr/local/src/nginx/modules || exit 1
			# install libmaxminddb
			wget https://github.com/maxmind/libmaxminddb/releases/download/${LIBMAXMINDDB_VER}/libmaxminddb-${LIBMAXMINDDB_VER}.tar.gz
			tar xaf libmaxminddb-${LIBMAXMINDDB_VER}.tar.gz
			cd libmaxminddb-${LIBMAXMINDDB_VER}/ || exit
			./configure
			make
			make install
			ldconfig

			cd ../ || exit
			wget https://github.com/leev/ngx_http_geoip2_module/archive/${GEOIP2_VER}.tar.gz
			tar xaf ${GEOIP2_VER}.tar.gz

			mkdir geoip-db
			cd geoip-db || exit 1
			wget https://geolite.maxmind.com/download/geoip/database/GeoLite2-Country.tar.gz
			wget https://geolite.maxmind.com/download/geoip/database/GeoLite2-City.tar.gz
			tar -xf GeoLite2-City.tar.gz
			tar -xf GeoLite2-Country.tar.gz
			mkdir /opt/geoip
			cd GeoLite2-City_*/ || exit
			mv GeoLite2-City.mmdb /opt/geoip/
			cd ../ || exit
			cd GeoLite2-Country_*/ || exit
			mv GeoLite2-Country.mmdb /opt/geoip/
		fi

		# Cache Purge
		if [[ "$CACHEPURGE" = 'y' ]]; then
			cd /usr/local/src/nginx/modules || exit 1
			git clone https://github.com/FRiCKLE/ngx_cache_purge
		fi

		# ModSecurity
		if [[ "$MODSEC" = 'y' ]]; then
			cd /usr/local/src/nginx/modules || exit 1
			git clone --depth 1 https://github.com/SpiderLabs/modsecurity-nginx.git
		fi

		# LibreSSL
		if [[ "$LIBRESSL" = 'y' ]]; then
			cd /usr/local/src/nginx/modules || exit 1
			mkdir libressl-${LIBRESSL_VER}
			cd libressl-${LIBRESSL_VER} || exit 1
			wget -qO- http://ftp.openbsd.org/pub/OpenBSD/LibreSSL/libressl-${LIBRESSL_VER}.tar.gz | tar xz --strip 1

			./configure \
				LDFLAGS=-lrt \
				CFLAGS=-fstack-protector-strong \
				--prefix=/usr/local/src/nginx/modules/libressl-${LIBRESSL_VER}/.openssl/ \
				--enable-shared=no

			make install-strip -j "$(nproc)"
		fi

		# OpenSSL
		if [[ "$OPENSSL" = 'y' ]]; then
			cd /usr/local/src/nginx/modules || exit 1
			wget https://www.openssl.org/source/openssl-${OPENSSL_VER}.tar.gz
			tar xaf openssl-${OPENSSL_VER}.tar.gz
			cd openssl-${OPENSSL_VER} || exit

			./config
		fi

		# Download and extract of Nginx source code
		cd /usr/local/src/nginx/ || exit 1
		wget -qO- https://nginx.org/download/nginx-${NGINX_VER}.tar.gz | tar zxf -
		cd nginx-${NGINX_VER} || exit

		# As the default nginx.conf does not work, we download a clean and working conf from my GitHub.
		# We do it only if it does not already exist, so that it is not overriten if Nginx is being updated
		if [[ ! -e /etc/nginx/nginx.conf ]]; then
			mkdir -p /etc/nginx
			cd /etc/nginx || exit 1
			wget https://raw.githubusercontent.com/theforcer/nginx-autoinstall/master/conf/nginx.conf
			if [[ "$MODSEC" = 'y' ]]; then
				sed -i "s/#load_module/load_module/g" nginx.conf
			fi
			wget https://raw.githubusercontent.com/theforcer/nginfix/master/tls.conf
		fi
		cd /usr/local/src/nginx/nginx-${NGINX_VER} || exit 1

		NGINX_OPTIONS="
		--prefix=/etc/nginx \
		--sbin-path=/usr/sbin/nginx \
		--conf-path=/etc/nginx/nginx.conf \
		--error-log-path=/var/log/nginx/error.log \
		--http-log-path=/var/log/nginx/access.log \
		--pid-path=/var/run/nginx.pid \
		--lock-path=/var/run/nginx.lock \
		--http-client-body-temp-path=/var/cache/nginx/client_temp \
		--http-proxy-temp-path=/var/cache/nginx/proxy_temp \
		--http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
		--user=nginx \
		--group=nginx \
		--with-cc-opt=-Wno-deprecated-declarations"

		NGINX_MODULES="--with-threads \
		--with-file-aio \
		--with-http_ssl_module \
		--with-http_v2_module \
		--with-http_mp4_module \
		--with-http_auth_request_module \
		--with-http_slice_module \
		--with-http_stub_status_module \
		--with-http_realip_module \
		--with-http_sub_module"

		# Optional modules
		if [[ "$LIBRESSL" = 'y' ]]; then
			NGINX_MODULES=$(echo "$NGINX_MODULES"; echo --with-openssl=/usr/local/src/nginx/modules/libressl-${LIBRESSL_VER})
		fi

		if [[ "$GEOIP" = 'y' ]]; then
			NGINX_MODULES=$(echo "$NGINX_MODULES"; echo "--add-module=/usr/local/src/nginx/modules/ngx_http_geoip2_module-${GEOIP2_VER}")
		fi

		if [[ "$OPENSSL" = 'y' ]]; then
			NGINX_MODULES=$(echo "$NGINX_MODULES"; echo "--with-openssl=/usr/local/src/nginx/modules/openssl-${OPENSSL_VER}")
		fi

		if [[ "$CACHEPURGE" = 'y' ]]; then
			NGINX_MODULES=$(echo "$NGINX_MODULES"; echo "--add-module=/usr/local/src/nginx/modules/ngx_cache_purge")
		fi

		if [[ "$FANCYINDEX" = 'y' ]]; then
			git clone --quiet https://github.com/aperezdc/ngx-fancyindex.git /usr/local/src/nginx/modules/fancyindex
			NGINX_MODULES=$(echo "$NGINX_MODULES"; echo --add-module=/usr/local/src/nginx/modules/fancyindex)
		fi
		
		if [[ "$WEBDAV" = 'y' ]]; then
			git clone --quiet https://github.com/arut/nginx-dav-ext-module.git /usr/local/src/nginx/modules/nginx-dav-ext-module
			NGINX_MODULES=$(echo "$NGINX_MODULES"; echo --with-http_dav_module --add-module=/usr/local/src/nginx/modules/nginx-dav-ext-module)
		fi
		
		if [[ "$VTS" = 'y' ]]; then
			git clone --quiet https://github.com/vozlt/nginx-module-vts.git /usr/local/src/nginx/modules/nginx-module-vts
			NGINX_MODULES=$(echo "$NGINX_MODULES"; echo --add-module=/usr/local/src/nginx/modules/nginx-module-vts)
		fi

		./configure $NGINX_OPTIONS $NGINX_MODULES
		make -j "$(nproc)"
		make install

		if [[ "$MODSEC" = 'y' ]]; then
			# Download and compile ModSecurity source code to /usr/local/modsecurity
			if [[ ! -d /usr/local/modsecurity ]]
			then
				git clone --depth 1 -b v3/master --single-branch https://github.com/SpiderLabs/ModSecurity
				cd ModSecurity || exit 1
				git submodule init
				git submodule update
				./build.sh
				./configure
				echo ""
				echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
				echo "The following steps could take a while, as the ModSecurity code has to be compiled"
				echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
				echo ""
				sleep 5
				make
				make install
				cd .. || exit
				rm -r ModSecurity
			fi
			# Compile and install the nginx ModSecurity module
			NGINX_MODULES=$(echo "$NGINX_MODULES"; echo "--add-dynamic-module=/usr/local/src/nginx/modules/modsecurity-nginx")
			./configure $NGINX_OPTIONS $NGINX_MODULES
			make modules
			if [[ ! -d /etc/nginx/modules ]]
			then
				mkdir -p /etc/nginx/modules
			fi
			if [[ ! -d /etc/nginx/modsec ]]
			then
				mkdir -p /etc/nginx/modsec
				wget -O /etc/nginx/modsec/unicode.mapping https://raw.githubusercontent.com/SpiderLabs/ModSecurity/v3/master/unicode.mapping
				wget -O /etc/nginx/modsec/modsecurity.conf https://raw.githubusercontent.com/SpiderLabs/ModSecurity/v3/master/modsecurity.conf-recommended
				sed -i "s/SecRuleEngine DetectionOnly/SecRuleEngine On/" /etc/nginx/modsec/modsecurity.conf
			fi
			cp objs/ngx_http_modsecurity_module.so /etc/nginx/modules
		fi

		# remove debugging symbols
		strip -s /usr/sbin/nginx

		# Nginx installation from source does not add an init script for systemd and logrotate
		# Using the official systemd script and logrotate conf from nginx.org
		if [[ ! -e /lib/systemd/system/nginx.service ]]; then
			cd /lib/systemd/system/ || exit 1
			wget https://raw.githubusercontent.com/theforcer/nginx-autoinstall/master/conf/nginx.service
			# Enable nginx start at boot
			systemctl enable nginx
		fi

		if [[ ! -e /etc/logrotate.d/nginx ]]; then
			cd /etc/logrotate.d/ || exit 1
			wget https://raw.githubusercontent.com/theforcer/nginx-autoinstall/master/conf/nginx-logrotate -O nginx
		fi

		# Nginx's cache directory is not created by default
		if [[ ! -d /var/cache/nginx ]]; then
			mkdir -p /var/cache/nginx
		fi

		# We add the sites-* folders as some use them.
		if [[ ! -d /etc/nginx/sites-available ]]; then
			mkdir -p /etc/nginx/sites-available
		fi
		if [[ ! -d /etc/nginx/sites-enabled ]]; then
			mkdir -p /etc/nginx/sites-enabled
		fi
		if [[ ! -d /etc/nginx/conf.d ]]; then
			mkdir -p /etc/nginx/conf.d
		fi

		# Restart Nginx
		systemctl restart nginx

		# Block Nginx from being installed via APT
		if [[ $(lsb_release -si) == "Debian" ]] || [[ $(lsb_release -si) == "Ubuntu" ]]
		then
			cd /etc/apt/preferences.d/ || exit 1
			echo -e "Package: nginx*\\nPin: release *\\nPin-Priority: -1" > nginx-block
		fi

		# Removing temporary Nginx and modules files
		rm -r /usr/local/src/nginx

		# We're done !
		echo "Installation done."
	exit
	;;
	2) # Uninstall Nginx
		if [[ "$HEADLESS" != "y" ]]; then
			while [[ $RM_CONF !=  "y" && $RM_CONF != "n" ]]; do
				read -rp "       Remove configuration files ? [y/n]: " -e RM_CONF
			done
			while [[ $RM_LOGS !=  "y" && $RM_LOGS != "n" ]]; do
				read -rp "       Remove logs files ? [y/n]: " -e RM_LOGS
			done
		fi
		# Stop Nginx
		systemctl stop nginx

		# Removing Nginx files and modules files
		rm -r /usr/local/src/nginx \
		/usr/sbin/nginx* \
		/etc/logrotate.d/nginx \
		/var/cache/nginx \
		/lib/systemd/system/nginx.service \
		/etc/systemd/system/multi-user.target.wants/nginx.service

		# Remove conf & OWASP files
		if [[ "$RM_CONF" = 'y' ]]; then
			rm -r /etc/nginx/ \
			/usr/local/owasp-modsecurity
		fi

		# Remove logs
		if [[ "$RM_LOGS" = 'y' ]]; then
			rm -r /var/log/nginx
		fi

		# Remove Nginx APT block
		if [[ $(lsb_release -si) == "Debian" ]] || [[ $(lsb_release -si) == "Ubuntu" ]]
		then
			rm /etc/apt/preferences.d/nginx-block
		fi

		# We're done !
		echo "Uninstallation done."

		exit
	;;
	3) # Update the script
		wget https://raw.githubusercontent.com/theforcer/nginx-autoinstall/master/nginx-autoinstall.sh -O nginx-autoinstall.sh
		chmod +x nginx-autoinstall.sh
		echo ""
		echo "Update done."
		sleep 2
		./nginx-autoinstall.sh
		exit
	;;
	4) # OWASP ruleset installation
		if [[ ! -d /etc/nginx/modsec ]]; then
			echo "You need to install nginx with the ModSecurity 3 module beforehand."
			exit
		fi
		wget -O owasp-modsecurity.tar.gz https://github.com/SpiderLabs/owasp-modsecurity-crs/archive/v${OWASP_VER}.tar.gz
		tar -xf owasp-modsecurity.tar.gz
		mv owasp-modsecurity-crs-${OWASP_VER} /usr/local/owasp-modsecurity
		rm owasp-modsecurity.tar.gz
		cd /usr/local/owasp-modsecurity || exit
		cp crs-setup.conf.example crs-setup.conf
		mv rules/REQUEST-910-IP-REPUTATION.conf rules/REQUEST-910-IP-REPUTATION.conf.example
		wget -O /etc/nginx/modsec/main.conf https://raw.githubusercontent.com/theforcer/nginx-autoinstall/master/conf/main.conf
		nginx -s reload
		echo ""
		echo "The ruleset has been successfully installed to /usr/local/owasp-modsecurity."
		echo "Add the following config lines to your nginx vhosts to start blocking malicious traffic!"
		echo ""
		echo "	modsecurity on;"
		echo "	modsecurity_rules_file /etc/nginx/modsec/main.conf;"
		echo ""
		echo "You can test for success with --> curl -H 'User-Agent: Nikto' http://example.com/ --> Should 403"
		echo ""
	;;
	*) # Exit
		exit
	;;

esac
