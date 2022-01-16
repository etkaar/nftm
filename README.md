# nftables Managing Script

Lightweight script to manage a [nftables](https://en.wikipedia.org/wiki/Nftables) based firewall with periodically and atomically updated whitelists and blacklists. Written in DASH ([Debian Almquist Shell](https://wiki.archlinux.org/title/Dash)) to offer POSIX compliance.

## 1.0 Introduction

This script is compatible with nftables >= 0.9.0 and was tested on Debian 10 Buster¹.

In the default configuration, the firewall will **drop any incoming traffic** which is not either whitelisted using the `conf/whitelist.conf` file, the presets in `conf/presets` *or* the `conf/additional_rules.txt`.

---

¹ **Warning:** Not compatible with nftables 0.9.8–1.0.1 (Debian 11 Bullseye) due to a [critical regression bug in nftables](https://marc.info/?l=netfilter-devel&m=164132615421568&w=2).

---

## 2.0 Compiling

nftables is the default firewall in Debian 11 Bullseye and already used as backend in Debian 10 Buster, so you don't need to compile it. Nonetheless, in case you want to compile it to the newest available version, you can use following commands (tested on Debian 11 Bullseye):

```
apt install git autoconf autogen libtool make pkg-config
apt install bison flex asciidoc libgmp-dev libedit-dev python3-distutils

git clone git://git.netfilter.org/libmnl
cd libmnl
sh autogen.sh
./configure
make
make install

git clone git://git.netfilter.org/libnftnl
cd libnftnl
sh autogen.sh
./configure
make
make install

git clone git://git.netfilter.org/nftables
cd nftables
sh autogen.sh
./configure
make
make install

reboot
nft --version
```

---

## 3.0 How to Use

In the following examples, we will use `/etc/firewall` as script path. Thus, login with `root` permissions, manually download the code and move its content there:

```
mkdir /etc/firewall
cd /etc/firewall
wget https://github.com/etkaar/nftm/archive/refs/heads/main.tar.gz
tar -xzf main.tar.gz --strip-components=1
rm main.tar.gz
```

After that, let the script automatically validate the file permissions:

```
chmod 0700 /etc/firewall/app.sh
/etc/firewall/app.sh update-permissions
```

⛔️ Do **not** automatically update this script. In case you need to update it, make sure that it won't break your system.

---

### 3.1 Presets and Whitelist

You need to enable at least **one default** preset. At this time, this will be either `default ipv4-only` or `default ipv4-and-ipv6`:

```
/etc/firewall/presets.sh enable default ipv4-only
```

List all available presets:

```
/etc/firewall/presets.sh list
```

To enable the `http` and `https` presets (ports 80 and 443), just type in:

```
/etc/firewall/presets.sh enable custom http
/etc/firewall/presets.sh enable custom https
```

After that, you may want to edit the `conf/whitelist.conf` to add your IP address for SSH access. It is a good idea to use DynDNS for that, so the firewall only allows SSH access from your IP address. See below the default `conf/whitelist.conf`:

```
# <dynamic hostname|address|subnet(*)>                      <enabled>           <protocol>              <port(s)>

# IPv4 or IPv6 addresses:
# 127.0.0.1                                                  1                   tcp                     22,587
# 2001:0DB8:7654:0010:FEDC:0000:0000:3210                    1                   udp                     27015

# You can use hostnames which are associated
# with an IPv4 and/or IPv6 address:
#
# client-dyndns.example.com                                  1                   tcp                     22,587

# (*) To use subnets, you need nftables >= 0.9.4:
# 127.0.0.1/8                                                1                   tcp                     22
```

Once you are **sure** all is correct, do a full reload of the firewall but **do not end your SSH session** yet:

```
/etc/firewall/app.sh full-reload
```

Now, try to open a *seperate* SSH session to your server. If that works, the IP address could be successfully fetched from your DynDNS name. Of course, you can and should manually doublecheck that by listing the firewall ruleset:

```
/etc/firewall/app.sh show
```

---

### 3.2 Startup Script and Cronjob
#### 3.2.1 Automatically

If you are using Debian, you can let the script automatically setup both the crontab and the startup script:

```
/etc/firewall/app.sh setup-crontab
/etc/firewall/app.sh setup-startupscript
```

The script will warn you, if the crontab or startup script is missing. To suppress that you can just append `--no-warnings`:

```
/etc/firewall/app.sh [...] --no-warnings
```

#### 3.2.2 Manually

Create a startup file and allow execution:

```
touch /etc/network/if-pre-up.d/firewall
chmod 0755 /etc/network/if-pre-up.d/firewall
```

This startup file needs following content:

```
#!/bin/sh
/etc/firewall/app.sh init
```

Finally, you need a crontab to make sure DynDNS records are periodically updated, the default is every three (3) minutes.

Run `crontab -e` as `root` user and add following line:

```
*/3 * * * * /etc/firewall/app.sh cron
```

You can also use following command:

```
(crontab -l 2>/dev/null; echo "*/3 * * * * /etc/firewall/app.sh cron") | crontab -
```

---

### 3.3 Logging

For debugging purposes, dropped packages may be logged.

You should disable that once all runs fine by commenting out the line in `conf/additional_rules.txt`:

```
...

#
# Enables logging of dropped packages for debugging purposes
#
# You will find the logs in:
#   /var/log/kern.log
#   /var/log/syslog
#
#add rule inet filter default_input log prefix "nft dropped: "
```
