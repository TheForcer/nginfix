# nginfix

The main purpose of this script is to automate the creation of nginx-vhost-files for serveral web services which need nginx as a proxy, including an easy way to create the required DNS entries when using a supported domain provider. With the arrival of LetsEncrypt wildcard certificates (+ ECC certificate support via acme.sh), the script provides a secure web server config out of the box for all your subdomain needs.

The master branch assumes that you use [INWX](https://inwx.de) as a domain provider. You may check out other branches to see if your provider is supported (I might add some in the future).

## Usage

Download and execute the nginfix.sh script (you only need the script itself, none of the other files):

```sh
wget https://raw.githubusercontent.com/TheForcer/nginfix/master/nginfix.sh
chmod u+x nginfix.sh
./nginfix.sh
```

Do not forget to enter your INWX credentials & Server IPs in the config section of the script.

## Credits

The nginx installation feature is based on the great [nginx-autoinstall script](https://github.com/angristan/nginx-autoinstall) by angristan. Thanks a lot!
