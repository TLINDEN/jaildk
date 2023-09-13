## jaildk - a FreeBSD jail development kit v2.0.0

This is  the README for the  FreeBSD jail utility `jaildk`.  It can be
used to build, update, manage and run jails in a versioned environment.

Every jail  consists of layers of  directories mounted on top  of each
other using  nullfs mounts. Some  of them  can be shared  among jails,
some are versioned. By using shared  and versioned layers of mounts it
is easy to update jails in a  new version while the current version is
still running, you can switch back to an older version of a jail.

Most of the layers are mounted read-only for security reasons.

Let's take a look at the layers of a typical running jail built with `jaildk`:
```
     1  /jail/base/12.1-RELEASE-p10      /jail/run/db                       read-only
     2  /dev/md12                        /jail/run/db/tmp
     3  devfs                            /jail/run/db/dev
     4  /jail/log/db-20201026            /jail/run/db/var/log
     5  /jail/appl/db-20201026           /jail/run/db/usr/local             read-only
     6  /jail/etc/db/etc-20201026        /jail/run/db/etc                   read-only
     7  /jail/etc/db/local-etc-20201026  /jail/run/db/usr/local/etc         read-only
     8  /jail/etc/db/cron-20201026       /jail/run/db/var/cron
     9  /jail/home/db/root-20201026      /jail/run/db/root
    10  /jail/data/db/mysql-20201026     /jail/run/db/usr/local/data/mysql
    11  /backup/db                       /jail/run/db/var/backups
                                                     |
                                                     +--- root of the jail
```

As can be easily deduced this is a database jail with the following layers:

1. **base layer**: This is basically the same as a FreeBSD base, which
   contains all biinaries, libraries and  other files required to boot
   up a FreeBSD system. Our base  doesn't contain a kernel by default,
   but  you could  add one,  required  if you  want to  use the  ports
   collection and  compile `lsof` yourself.<br/>
   This  particular base  is  based on  12.1-RELEASE-p10,  that is,  I
   created it  while I had this  release installed and running  on the
   host system.
2. **tmp layer**: Just a ramdisk for `/tmp`, the size can be tuned.
3. **dev layer**: Contains /dev/null and friends, required by every jail.
4. **log layer**:  Here  we  have our  first  versioned layer  for
   `/var/log`. Notice how all other layers are using the same version,
   this  is done  by purpose  (but can  be changed  if you  like). The
   version is a jail variable (see  below) which is being used for all
   layers.
5. **application  layer**: As  you know if  you're using  FreeBSD, any
   additional software,  wether installed from  a port or  as package,
   will be  installed to  `/usr/local`.  In our  case it  contains the
   mysql   server  software,   bash   and  a   couple  of   supporting
   utilities. It is being mounted read-only, so no new software can be
   installed in the running jail.  This might sound annoying at first,
   because you  can't just install  stuff inside the jail  anytime you
   like. But it  forces you to work more disciplined.  Once a jail has
   been completely  built you can  be sure, all components  match with
   each other. Read below how to install or update software in a jail.
6. **/etc layer**: this just contains  the normal etc, it is basically
   a stripped copy of the host `/etc`.  We do not use it at all inside
   a  jail, but  it's required  nontheless. There  are some  exceptions
   however, like `/etc/resolv.conf`.
7. **/usr/local/etc layer**:  This  is the  place  we configure  all
   aspects of the jail, all configs  reside here (like in our case the
   mysql config). It  is also being mounted  read-only, just like
   the etc layer.
8. **cron layer**:  A writable mount for the crontabs  of users inside
   the  jail.  That   way  one  can  modify   crontabs  with  `crontab
   -e`. However, if you don't want or need this, just remove the layer
   and add cronjobs to `/etc/crontab`.
9. **/root layer**: most of the administrative work inside a jail must
   be done  as the  root user and  it would  be a pity  not to  have a
   writable  history. So,  `/root`  is mounted  writable  to add  more
   comfort.
10. **a data layer**: A versioned data layer which contains the binary
    data of our mysql server. This  is very jail specific and you have
    to add such layers yourself. Variants  of such a layer include the
    document root of a webserver or the repositories of a git server.
11.  **backup layer**:  Another  custom layer,  here  we've mounted  a
    global backup directory of our host which contains all backups.
    
All layers  are configured  in a `mount.conf`  file specific  for each
jail. The one for this jail looks like this:
```
base/$base                    $name                       nullfs  ro
md                            $name/tmp                   mfs     rw,nosuid,async  500m 1777
dev                           $name/dev                   devfs
log/$name-$version            $name/var/log               nullfs  rw
appl/db-$version              $name/usr/local             nullfs  ro
etc/$name/etc-$version        $name/etc                   nullfs  ro
etc/$name/local-etc-$version  $name/usr/local/etc         nullfs  ro
etc/$name/cron-$version       $name/var/cron              nullfs  rw
home/$name/root-$version      $name/root                  nullfs  rw
data/$name/mysql-$version     $name/usr/local/data/mysql  nullfs  rw
/backup/db                    $name/var/backups           nullfs  rw
```

Now, as you can see, we're  using variables here. Those are defined in
the  `jail.conf` (not  to  be confused  with  `/etc/jail.conf` on  the
host!):
```
name=db
version=20201026
base=12.1-RELEASE-p10
```

You might wonder  how the other aspects of a  jail are configured like
ip  addresses, routing,  jail  parameters, sysctls  etc. Well,  that's
beyond the  purpose of  `jaildk`.  You just  use the  standard FreeBSD
mechanism for these things,  that is `/ect/rc.conf`, `/etc/jail.conf`,
`service  jail ...`,  `jexec`,  etc. However,  `jaildk` provides  some
handy wrappers to make live easier.

For an overview of the provided commands, here's the usage screen:
```
Usage: ./jaildk <command> <command-args>

Building Jails:
base -b <name> [-w]                               - build a new base
build <jail> -m <mode> [-b <base>] [-v <version>] - install a build chroot of a jail
create                                            - create a new jail from a template
clone -s <src> -d <dst> [-o <v>] [-n <v>]         - clone an existing jail or jail version
fetchports [-v <version>]                         - fetch current port collection

(Un)installing Jails:
install <jail> -m <mode> [-r function]            - install a jail (prepare mounts, devfs etc)
uninstall <jail> [-w]                             - uninstall a jail
remove <jail>                                     - remove a jail or a jail version
reinstall <jail> [-b <base>] [-v <version>]       - stop, remove, install and start a jail, if
                                                    -b and/or -v is set, update the jail config
prune [-b | -a | -j <jail>                        - display unused directories

Maintaining Jails:
start <jail>                                      - start a jail
stop <jail>                                       - stop a jail
restart <jail>                                    - restart a jail
status [<jail>] [-v]                              - display status of jails or <jail>
rc <jail> -m <mode> [-r <rc.d script>]            - execute an rc-script inside a jail
ipfw <jail> -m <mode>                             - add or remove ipfw rules

Managing Jails:
login <jail> [<user>]                             - login into a jail
blogin <jail>                                     - chroot into a build jail

Transferring Jails:
freeze <jail> [-a -b -v <version>]                - freeze (build an image of) a jail
thaw <image>                                      - thaw (install) an image of a jail

Getting help and internals:
completion                                        - print completion code. to use execute in a bash:
                                                    source <(jaildk completion)
help <command>                                    - request help on <command>
version                                           - print program version
update [-f]                                       - update jaildk from git repository
```

## Installation

Clone this repository to your FreeBSD server and execute the following command:
```
make
make install
```

This will create the directory structure required for the tool itself,
create a  template jail and build  a base directory. The  default base
directory is `/jail`. You can modify this by issuing:
```
make install JAILDIR=/another/dir
```

Be aware,  that the `jaildk` script  itself will only be  installed to
`$JAILDIR/bin/jaildk`.  Either put  this directory  into your  `$PATH`
variable or create a symlink to the script in some bin dir.

## Bash Completion

If you want to use `jaildk` with bash completion, put this line into your `.bashrc`:
```
source <(jaildk completion)
```

## Basic usage

Let's say you installed *jaildk* into `/jail` and you want to create a
new jail with  the name 'myjail' and the ip  address '172.16.1.1'.

The following steps need to be done:

### Configure /etc/jail.conf

Create the file `/etc/jail.conf` with the following innitial contents:
```
* {
    exec.start = "/bin/sh /etc/rc";
    exec.stop = "/bin/sh /etc/rc.shutdown";
    allow.raw_sockets = "false";
    sysvmsg = "new";
    sysvsem = "new";
    sysvshm = "new";
    host.hostname = $name;
    path = "/jail/run/$name"; 
    exec.prestart = "/jail/bin/jaildk install $name start";
    exec.clean = "true";
}

myjail {
    ip4.addr = "172.16.1.1";
}
```

Refer to [jail(8)](https://www.freebsd.org/cgi/man.cgi?query=jail&sektion=8) for more possible settings.

### Configure /etc/rc.conf

Next add the following lines to your `/etc/rc.conf`:
```
ifconfig_em0_alias0="inet 172.16.1.1/32"
jail_enable="YES"
```

You may need to replace the interface name `em0` with the one in use on your system.
You might need to restart the interface to apply the alias: `/etc/rc.d/netif restart`.

### Create the jail
```
# jaildk create myjail

- cpdup -x /jail/log/.template-20201106 /jail/test/log/myjail-20201106
- cpdup -x /jail/home/.template/root-20201106 /jail/test/home/myjail/root-20201106
- cpdup -x /jail/etc/.template/etc-20201106 /jail/test/etc/myjail/etc-20201106
- cpdup -x /jail/etc/.template/local-etc-20201106 /jail/test/etc/myjail/local-etc-20201106
/jail/data/.template/www doesn't exist, ignored
/jail/data/.template/spool doesn't exist, ignored
- cp -pRp /jail/etc/.template/mount.conf /jail/test/etc/.template/ports.conf /jail/test/etc/.template/mtree.conf /jail/test/etc/myjail/
cp: /jail/etc/.template/ports.conf: No such file or directory
Creating /jail/etc/.template/jail.conf
Creating run and build dirs
- mkdir -p /jail/run/myjail
- mkdir -p /jail/build/myjail
DONE.
Consider adding the jail myjail to /etc/jail.conf!

To mount the build chroot of the new jail, execute:
jaildk build myjail

To login into the build chroot
jaildk blogin myjail

To mount the production chroot of the new jail, execute:
jaildk install myjail

To login into the build chroot
jaildk login myjail

To start the jail, execute:
jaildk start myjail
```

### Mount the build chroot of the jail

```
# jaildk build myjail

Installing jail myjail
mount - mount -t nullfs -o rw /jail/base/12.1-RELEASE-p10 /jail/build/myjail
mount - mdmfs -o rw,nosuid,async -s 128m -p 1777 md /jail/build/myjail/tmp
mount - mount -t devfs dev /jail/build/myjail/dev
mount - mount -t nullfs -o rw /jail/log/myjail-20201106 /jail/build/myjail/var/log
mount - mount -t nullfs -o rw /jail/appl/default-20201106 /jail/build/myjail/usr/local
mount - mount -t nullfs -o rw /jail/etc/myjail/etc-20201106 /jail/build/myjail/etc
mount - mount -t nullfs -o rw /jail/etc/myjail/local-etc-20201106 /jail/build/myjail/usr/local/etc
mount - mount -t nullfs -o rw /jail/home/myjail/root-20201106 /jail/build/myjail/root
```

### Chroot into the build dir and install software

```
jaildk blogin myjail
pkg install bash nginx curl ...
vi /usr/local/etc/rc.conf
vi /usr/local/etc/nginx/nginx.conf
```

Since  the build  chroot  is  writable you  can  install packages  and
configure everything as needed.

### Using the ports collection

There might be cases when using pre build binary packages are not your
thing. In such a case you want to use the [FreeBSD Ports Collection](https://www.freebsd.org/ports/).

*jaildk* supports this, here are the steps required:

#### Create a buildbase

A  normal base  directory cannot  be  used with  the ports  collection
because  jaildk removes  libraries and  binaries for  security reasons
from normal bases. To create a build base, execute:

`jaildk base -b 12-RELEASE-build -w`

Next, add  the following entry  to the  configuration of you  jail. To
stay with our example, edit `/jail/etc/myjail/jail.conf` and add:

`buildbase=12-RELEASE-build`

Then install the build jail as usual:

`jaildk build myjail`

Install the current ports collection:

`jaildk fetch`

In case the  ports version created does not match  the version of your
jail, you need  to configure the different ports version  in your jail
config `/jail/etc/myjail/jail.conf` like this:

`ports=20201127`

Now you can enter the build jail and install ports the traditional way:

```
jaildk blogin myjail
cd /usr/ports/shells/bash
make config-recursive install clean
```

### When done, install and start the jail

```
# jaildk install myjail 
Installing jail myjail
mount - mount -t nullfs -o ro /jail/base/12.1-RELEASE-p10 /jail/run/myjail
mount - mdmfs -o rw,nosuid,async -s 128m -p 1777 md /jail/run/myjail/tmp
mount - mount -t devfs dev /jail/run/myjail/dev
mount - mount -t nullfs -o rw /jail/log/myjail-20201106 /jail/run/myjail/var/log
mount - mount -t nullfs -o ro /jail/appl/default-20201106 /jail/run/myjail/usr/local
mount - mount -t nullfs -o ro /jail/etc/myjail/etc-20201106 /jail/run/myjail/etc
mount - mount -t nullfs -o ro /jail/etc/myjail/local-etc-20201106 /jail/run/myjail/usr/local/etc
mount - mount -t nullfs -o rw /jail/home/myjail/root-20201106 /jail/run/myjail/root

# jaildk start myjail
Jail myjail start:
Starting jails: myjail.

# jaildk status myjail
Jail scipown status:
 JID             IP Address      Hostname                      Path
 myjail          172.16.1.1      myjail                        /jail/run/myjail
Jail myjail rc status:
syslogd is running as pid 28180.
cron is running as pid 52130.
php_fpm is running as pid 45558.
nginx is running as pid 63975.
===> fcgiwrap profile: mediawiki
fcgiwrap is running as pid 37682.
```

### Login into the running jail for administration
```
# jaildk login myjail
```

You can use this to login into a database or execute commands inside the jail.


### Updating a jail

The very first thing to do is to update the host system using `freebsd-update`.

Next create a new base version:
```
jaildk base -b `uname -r`
```
But of course you can update a jail with the current base as well.

Now you can clone of your jail with a new version:
```
jaildk clone -s myjail -d myjail -o 20201106 -n 20210422
```

Mount the build chroot for the new version:
```
jaildk build myjail -m start -b `uname -r` -v 20210422
```

And finally chroot into the new jail and update it:
```
jaildk blogin myjail
pkg update
...
```

The  last step  is  to remove  the current  running  jail, change  the
version in `etc/myjail.conf`, install and  start the new version. This
can be easily done with the following command:
```
jaildk reinstall myjail -b `uname -r` -v 20210422
```

This command also creates a copy of the current jail.conf.

If  there's anything  wrong you  can always  go back  to the  previous
version using the following command (using the previous base and version):
```
jaildk reinstall myjail -b 12.2-RELEASE-p1 -v 20201106
```

## Advanced Features

Jaildk also  offers some advanced features  like automatically setting
up and deleting ipfw rules or freezing  and thawing a jail (to make it
easily portable).

### Using the IPFW

To use  the IPFW on your  host you first  have to enable ipfw  in your
hosts rc.conf  `firewall_enable="YES"`.  You probably want  to set the
default    firewalling-type    there    aswell,    check    out    the
[FreeBSD handbook](https://www.freebsd.org/doc/handbook/firewalls-ipfw.html)
for further information.

Once enabled you also need to start ipfw by executing the rc script:

`/etc/rc.d/ipfw start`.

Be aware that inter-jail communication  is transfered via the loopback
interface (normally lo0) for which there  is a high priority allow any
to any rule by default:

`allow ip from any to any via lo`

In order  to control the  inter-jail communication you have  to delete
this rule first.

If an  ipfw.conf exists  for a jail  (e.g. /jail/etc/myjail/ipfw.conf)
the rules inside that config file are added when starting, and deleted
when stopping  the jail.   E.g. allowing  HTTP/HTTPS traffic  for that
jail (webserver):

`allow tcp from any to $ip setup keep-state`

As  demonstrated   in  the  previous   rule  `$ip`  is   reserved  and
automatically  replaced  with  the  jails   own  ip  (as  reported  by
`jls`). The same  applies to the ipv6 address which  will be available
as variable `$ip6`.  Also, all variables in the  jails `jail.conf` can
be used.

In order to make  these ipfw rules available on boot,  you need to add
the  following line  to `/etc/jail.conf`  in the  section of  the jail
which uses custom ipfw rules:

`exec.prestart = "/jail/bin/jaildk ipfw $name"`

Be aware, that  the ipfw module will  only be executed if  the jail is
running so  that we  can properly  determine the  ip addresses  of the
running jail. **Note**: this might change in the future.

### Using pf

Beside                ipfw,               Free                supports
[pf](https://www.freebsd.org/doc/de_DE.ISO8859-1/books/handbook/firewalls-pf.html)
as well.  You  can use pf with `jaildk`.  Unlike  the ipfw module (see
above) it is a normal `install` module. That is it can be installed or
reloaded before the jail is running (i.e. like the mount module).

In order to use `pf` with a jail, enable and configure it according to
the  FreeBSD  handbook linked  above.  It  is recommended  to  include
general block, scrup, state rules,  communication to and fro localhost
etc and just leave everything which is related to your jail.

Just so that you know how such a global `/etc/pf.conf` file might look
like, here's a simple one:
```shell
# variables
ext        = "em0"
me         = "your ipv4 address here"
me5        = "your ipv6 address here/64"
loginports = "{ 22, 5222, 443 }"
icmp_types = "echoreq"

# tables. look at the contents of a table:
#    pfctl -t bad_hosts -T show
# remove an entry from a table:
#    pfctl -t bad_hosts -T delete $ip
table <bad_hosts> persist

# default policy
set block-policy drop

# optimize according to rfc's
set optimization aggressive

# normalisation
scrub in all
antispoof for $ext

# allow localhost
pass quick on $local

# additional default block rules w/ logging. to view the log:
#    tcpdump -n -e -ttt -r /var/log/pflog
# to view live log:
#    tcpdump -n -e -ttt -i pflog0
block in log on $ext
block in log on $ext inet6

# whoever makes it into those tables: you loose
block quick from <bad_hosts>

# allow outgoing established sessions
pass out keep state
pass out inet6 keep state

# allow troubleshooting
pass in on $ext inet proto icmp all icmp-type $icmp_types keep state
pass in on $ext inet proto udp from any to any port 33433 >< 33626 keep state

# allow all icmpv6
pass in quick inet6 proto icmp6 all keep state

# allow login but punish offenders
block quick from <bad*hosts>
pass in quick on $ext inet proto tcp from any to $me port $loginports \
     flags S/SAFR keep state \
     (max-src-conn-rate 10/60, \
      overload <bad*hosts> flush global) label ServicesTCP
pass in quick on $ext inet6 proto tcp from any to $me6 port $loginports \
     flags S/SAFR keep state \
     (max-src-conn-rate 10/60, \
     overload <bad_hosts> flush global) label ServicesTCP
```

Install the ruleset with `service pf start`.

Now that everything is prepared you can create a `/jail/etc/myjail/pf.conf` file for your
jail. Here's an  example I use for a webserver  jail, which includes a
git server:
```shell
ip         = "jail ip4 addr"
ip6        = "jail ip6 addr"
loginports = "{ 22 }"
prodports  = "{ 80, 443 }"
ext        = "em0"

# dynamic block list
table <blocked>

# restrict foreigners
block quick from <blocked>
pass in quick on $ext inet proto tcp from any to $ip port $loginports \
     flags S/SAFR keep state \
     (max-src-conn-rate 10/60, \
      overload <blocked> flush global) label ServicesTCP

# allow production traffic v4
pass in quick on $ext proto tcp from any to $ip port $prodports keep state

# allow production traffic v6
pass in quick inet6 proto tcp from any to $ip6 port $prodports keep state
```

That's it already. Now install the jail as usual. You can also install
the pf ruleset for the jail separately:

`jaildk install myjail start -r pf`

To take look at the rules, execute:

`jaildk install myjail status -r pf`

You can of  course manipulate the ruleset  manually. `jaildk` installs
rulesets  into  a jail  specific  anchor  using the  following  naming
scheme: `/jail/<jail name>`. So, for example to view the rules, execute:

`pfctl  -a /jail/myjail -s rules`

Manipulate a jail specific table:

`pfctl  -a /jail/myjail -t blocked -T show`

## Getting help

Although I'm happy to hear from jaildk users in private email,
that's the best way for me to forget to do something.

In order to report a bug, unexpected behavior, feature requests
or to submit a patch, please open an issue on github:
https://github.com/TLINDEN/jaildk/issues.

## Copyright and license

This software is licensed under the BSD license.

## Authors

T.v.Dein <tom AT vondein DOT org>

F.Sass (Culsu)

## Project homepage

https://github.com/TLINDEN/jaildk

