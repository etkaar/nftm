# nftm: Nftables Managing Script

Lightweight script to manage a [nftables](https://en.wikipedia.org/wiki/Nftables) based firewall with periodically and atomically updated whitelists and blacklists. Written in DASH ([Debian Almquist Shell](https://wiki.archlinux.org/title/Dash)) to offer POSIX compliance.

⚠️ **Do not automatically update this script. This could result in you being locked out of your system.**

## 1.0 Introduction

This script is compatible with nftables >= 0.9.0 and was tested on Debian 10 Buster, 11 Bullseye¹ and 12 Bookworm.

In the default configuration, the firewall will **drop any incoming traffic** which is not either whitelisted using the `conf/whitelist.conf` file, the presets in `conf/presets` *or* the `conf/additional_rules.txt`.

<sub>¹ ~~**Warning:** Not compatible with nftables 0.9.8–1.0.1 (Debian 11 Bullseye) due to a [critical regression bug in nftables](https://marc.info/?l=netfilter-devel&m=164132615421568&w=2).~~<br/>
Issue fixed via [kernel patch](https://github.com/torvalds/linux/commit/23c54263efd7cb605e2f7af72717a2a951999217) in [5.10.103-1](https://metadata.ftp-master.debian.org/changelogs//main/l/linux/linux_5.10.106-1_changelog) on 7th March 2022.</sub>

---

## 2.0 Installation

### 2.1 First Steps

In the following examples, we will use `/etc/firewall` as script path. Thus, login with `root` permissions, manually download the code and move its content there:

```shell
mkdir /etc/firewall
cd /etc/firewall
wget https://github.com/etkaar/nftm/archive/refs/heads/main.tar.gz
tar -xzf main.tar.gz --strip-components=1
rm main.tar.gz
```

The configuration files end with `.sample` as a safety precaution. Remove that file extension to make the configuration files usable:

```shell
cd /etc/firewall/conf

mv additional_rules.txt.sample additional_rules.txt
mv blacklist.conf.sample blacklist.conf
mv whitelist.conf.sample whitelist.conf
```

After that, let the script automatically validate the file permissions:

```shell
chmod 0700 /etc/firewall/app.sh
/etc/firewall/app.sh update-permissions
```

---

### 2.2 Setup Startup Script and Cronjob
#### 2.2.1 Automatically

If you are using Debian, you can let the script automatically setup both the crontab and the startup script:

```shell
/etc/firewall/app.sh setup-crontab
/etc/firewall/app.sh setup-startupscript
```

The script will warn you, if the crontab or startup script is missing. To suppress that you can just append `--no-warnings`:

```shell
/etc/firewall/app.sh [...] --no-warnings
```

#### 2.2.2 Manually

Create a startup file and allow execution:

```shell
touch /etc/network/if-up.d/nftm
chmod 0755 /etc/network/if-up.d/nftm
```

This startup file needs following content:

```shell
#!/bin/sh
if [ ! "$IFACE" = "lo" ]
then
	/etc/firewall/app.sh init
fi
```

Finally, you need a crontab to make sure DynDNS records are periodically updated, the default is every three (3) minutes.

Run `crontab -e` as `root` user and add following line:

```shell
*/3 * * * * /etc/firewall/app.sh cron
```

You can also use following command:

```shell
(crontab -l 2>/dev/null; echo "*/3 * * * * /etc/firewall/app.sh cron") | crontab -
```

---

### 2.3 Presets and Whitelist

You need to enable at least **one default** preset. At this time, this will be either `default ipv4-only` or `default ipv4-and-ipv6`:

```shell
/etc/firewall/presets.sh enable default ipv4-only
```

List all available presets:

```shell
/etc/firewall/presets.sh list
```

To enable the `http` and `https` presets (ports 80 and 443), just type in:

```shell
/etc/firewall/presets.sh enable custom http
/etc/firewall/presets.sh enable custom https
```

After that, you may want to edit the `conf/whitelist.conf` to add your IP address for SSH access. It is a good idea to use DynDNS for that, so the firewall only allows SSH access from your IP address. See below the default `conf/whitelist.conf`:

```shell
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

```shell
/etc/firewall/app.sh full-reload
```

Now, try to open a *seperate* SSH session to your server. If that works, the IP address could be successfully fetched from your DynDNS name. Of course, you can and should manually doublecheck that by listing the firewall ruleset:

```shell
/etc/firewall/app.sh list
```

---

### 3.0 Logging

For debugging purposes, dropped packages may be logged.

You should disable that once all runs fine by commenting out the line in `conf/additional_rules.txt`:

```shell
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

---

### 4.0 Manual Compiling of `nftables`

nftables is the default firewall in Debian 11 Bullseye and already used as backend in Debian 10 Buster, so you don't need to compile it. Nonetheless, in case you want to compile it to the newest available version, you can use following commands (tested on Debian 11 Bullseye):

```shell
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
