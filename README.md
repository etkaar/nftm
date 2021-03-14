# nftables-managing-script
Lightweight POSIX compatible (/bin/dash) script to manage a nftables based firewall with periodically and atomically updated whitelists and blacklists.

Tested on Debian 10 (Buster).

# Important
In the default configuration, the firewall will **drop any incoming traffic** which is not whitelisted using the `conf/whitelist.conf` file, the presets in `conf/presets` or the `conf/additional_rules.txt`.

Your server needs to use nftables instead of iptables:

```
apt install nftables
```

# How to Use

In following example, we will copy the script files to `/etc/firewall`:

```
mkdir /etc/firewall/conf/presets/enabled

chmod 0500 /etc/firewall/*.sh
chmod 0500 /etc/firewall/inc/*.sh
```

You need to enable at least **one default** preset. At this time, this will be `default ipv4-only` or `default ipv4-and-ipv6`:

```
/etc/firewall/presets.sh enable default ipv4-only
```

List all available presets:

```
/etc/firewall/presets.sh list
```

To enable `http` and `https` (ports 80 and 443), just type in:

```
/etc/firewall/presets.sh enable custom http
/etc/firewall/presets.sh enable custom https
```

After that, you may want to edit the `conf/whitelist.conf` to add your IP address for SSH access. It is a good idea to use DynDNS for that, so the firewall only allows SSH access from your IP address:

```
# <dynamic hostname|address|subnet> <enabled> <protocol> <port(s)>
dyndns.example.com 1 tcp 22
```

Once you are **sure** all is correct, do a full reload of the firewall but **do not end your SSH session** yet:

```
/etc/firewall/app.sh full-reload
```

Now, try to open a *seperate* SSH session to your server. If that works, the IP address could be successfully fetched from your DynDNS name. Of course, you can and should manually doublecheck that by listing the firewall ruleset:

```
/etc/firewall/app.sh show
```

After that, you need to make sure the firewall ruleset is always reloaded on reboot. Create a startup file and allow execution:

```
touch /etc/network/if-pre-up.d/firewall
chmod 0755 /etc/network/if-pre-up.d/firewall
```

This startup file needs following content:

```
#!/bin/sh
/etc/firewall/app.sh init
```

Finally, you need a cron job to make sure DynDNS records are periodically updated, in that case every three (3) minutes.

Run `crontab -e` as **root** user and add following line:

```
*/3 * * * * /etc/firewall/app.sh cron
```

You can also use following command:

```
(crontab -l 2>/dev/null; echo "*/3 * * * * /etc/firewall/app.sh cron") | crontab -
```
