## jaildk - a FreeBSD jail development kit

This is  the README for the  FreeBSD jail utility `jaildk`.  It can be
used to build, update, manage and run jails in a versioned environment.

Every jail  consists of layers of  directories mounted on top  of each
other using  nullfs mounts. Some  of them  can be shared  among jails,
some are versioned.

## Installation

Execute the following command:
```
./jaildk setup <directory>
```

This will create the directory structure required for the tool install
the tool itself, create a template jail and build a base directory.

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
    exec.prestart = "/jail/bin/jaildk install $name all start";
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
ifconfig_em0_alias0="inet 144.76.67.168/32"
jail_enable="YES"
```

You may need to replace the interface name `em0` with the one in use on your system.


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

# jaildk startus myjail
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
# jaildk jlogin myjail
```

You can use this to login into a database or execute commands inside the jail.


### Updating a jail

The very first thing to do is to update the host system using `freebsd-update`.

Next create a new base version:
```
jaildk base `uname -r`
```

Now you can create clone of your jail with a new version:
```
jaildk clone myjail myjail 20201106 20210422
```

Mount the build chroot for the new version:
```
jaildk build myjail start `uname -r` 20210422
```

And finally chroot into the new jail and update it:
```
blogin myjail
pkg update
...
```

The last step is to remove the current running jail, change the version in `etc/myjail.conf`, install and start the new version.

If there's anything wrong you can always go back to the previous version using the above steps.


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

## Project homepage

https://github.com/TLINDEN/jaildk

