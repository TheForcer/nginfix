# nginfix

The main purpose of this script is to automate the creation of nginx-vhost-files for serveral web services which need nginx as a proxy, including an easy way to create the required DNS entries when using a supported domain provider. With the arrival of LetsEncrypt wildcard certificates (+ ECC certificate support via acme.sh), the script provides a secure web server config out of the box for all your subdomain needs.

![Menu](https://i.imgur.com/jb9ZAJl.png)

The master branch assumes that you use [INWX](https://inwx.de) as a domain provider. You may check out other branches to see if your provider is supported (I might add some in the future).

## Usage

Download and execute the nginfix.sh script (you only need the script itself, none of the other files):

```sh
wget https://raw.githubusercontent.com/TheForcer/nginfix/master/nginfix.sh
chmod u+x nginfix.sh
./nginfix.sh
```

On the first launch you'll have the possibility to download a [sample config file](https://raw.githubusercontent.com/TheForcer/nginfix/master/.nginfix.cfg.sample). Open that file with your preferred editor and fill in your details (INWX credentials, IPS, etc.) and save the file as .nginfix.cfg in the same directory as the script. After doing so, you will be able to fully utilize the script!

Current SHA256 hash of the script in branch master:
```sh
b5d5b6d3436cef7dfe4f2d54584e159928ef0ac58403beaa8026326df24dd391  nginfix.sh
```

## Warning

Some words of advice: I assume that you have a general understanding on how nginx works and some of the security-related headers I use in my [tls.conf](https://raw.githubusercontent.com/TheForcer/nginfix/master/tls.conf). Any browser/user who caches the Strict-Transport-Security Header will only be able to visit your domain & subdomains via HTTPS, so you should make sure plain HTTP services are not required for that domain. If you are already in the [HSTS preload list](https://hstspreload.org/), then this shouldn't be an issue for you.

## Credits

The nginx installation feature is based on the great [nginx-autoinstall script](https://github.com/angristan/nginx-autoinstall) by angristan. Thanks a lot!
