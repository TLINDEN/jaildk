#!/bin/sh

version=2.0.3

# this will  be completed during  build. Don't touch it,  just execute
# make and use the resulting script!
JAILDK_COMPLETION=$(
cat<<'EOF'
# will be modified during installation (jaildk setup)
JAILDIR=/jail

COMPLETIONCODE
EOF
)

usage_jaildk() {
    beg=`tput -T ${TERM:-cons25} md`
    end=`tput -T ${TERM:-cons25} me`
    usage=$(cat <<EOF
This is jaildk version $version, a jail management toolkit.

Usage: $0 <command> <command-args>

${beg}Building Jails:${end}
base -b <name> [-w]                               - build a new base
build <jail> -m <mode> [-b <base>] [-v <version>] - install a build chroot of a jail
create                                            - create a new jail from a template
clone -s <src> -d <dst> [-o <v>] [-n <v>]         - clone an existing jail or jail version
fetchports [-v <version>]                         - fetch current port collection

${beg}(Un)installing Jails:${end}
install <jail> -m <mode> [-r function]            - install a jail (prepare mounts, devfs etc)
uninstall <jail> [-w]                             - uninstall a jail
remove <jail>                                     - remove a jail or a jail version
reinstall <jail> [-b <base>] [-v <version>]       - stop, remove, install and start a jail, if
                                                    -b and/or -v is set, update the jail config
prune [-b | -a | -j <jail>                        - display unused directories

${beg}Maintaining Jails:${end}
start <jail>                                      - start a jail
stop <jail>                                       - stop a jail
restart <jail>                                    - restart a jail
status [<jail>] [-v]                              - display status of jails or <jail>
rc <jail> -m <mode> [-r <rc.d script>]            - execute an rc-script inside a jail
ipfw <jail> -m <mode>                             - add or remove ipfw rules

${beg}Managing Jails:${end}
login <jail> [<user>]                             - login into a jail
blogin <jail>                                     - chroot into a build jail

${beg}Transferring Jails:${end}
freeze <jail> [-a -b -v <version>]                - freeze (build an image of) a jail
thaw <image>                                      - thaw (install) an image of a jail

${beg}Getting help and internals:${end}
completion                                        - print completion code. to use execute in a bash:
                                                    source <(jaildk completion)
help <command>                                    - request help on <command>
version                                           - print program version
update [-f]                                       - update jaildk from git repository

EOF
)
    echo "$usage"
    exit 1
}

usage_help() {
    command=$1

    usage="usage_${command}"
    if ! type "$usage" > /dev/null 2>&1; then
        die "Unknown command $command!"
    else
        $usage
    fi
}

ex() {
    echo $rcscript - $*
    logger -p local0.notice -t jaildk "$rcscript $*"
    $*
}

err () {
   echo "$@" >&2
}

bold() {
    if [ -z "$NO_BOLD" ]; then
        if [ -z "$BOLD_ON" ]; then
            BOLD_ON=`tput -T ${TERM:-cons25} md`
            export BOLD_ON
            BOLD_OFF=`tput -T ${TERM:-cons25} me`
            export BOLD_OFF
        fi
        echo -n "$BOLD_ON"
        echo "$@"
        echo -n "$BOLD_OFF"
    else
        echo "$@"
    fi
}

fin() {
    echo "$*" >&2
    exit
}

die() {
    bold "$*" >&2
    exit 1
}

load_jail_config() {
    local jail=$1
    if test -d $j/etc/$jail; then
        # everything inside gets global
        . $j/etc/$jail/jail.conf
    else
        die "Jail $jail is not configured!"
    fi
}

die_if_not_exist() {
    local jail which jailversion

    jail=$1
    which=$2
    jailversion=$3

    if test -z "$which"; then
        which="Jail"
    fi

    if ! test -d $j/etc/$jail; then
        die "$which $jail doesn't exist!"
    fi

    if test -n "$jailversion"; then
        if ! test -d $j/etc/$jail/etc-$jailversion; then
            die "$which $jail $jailversion doesn't exist!"
        fi
    fi
}

parse_jail_conf() {
    #
    # just  in  case  we  want  or have  to  fetch  variables  out  of
    # /etc/jail.conf, this is the way to go. Call it like this:
    #
    # ip=`parse_jail_conf $jail ip4.addr`
    #
    # Output may be  empty, so check before  using. Multiple variables
    # of the same  type (like multiple ip addresses)  will be returned
    # comma separated.

    local jail=$1
    local search=$2
    local JAIL list

    # fetch 20 lines after "^$jail {", ignore comments
    egrep -A20 "^$jail" jail.conf | egrep -v "^ *#" | \
        # turn each line into an evaluable shell expression \
        sed -e 's/ *{//g' -e 's/}//g' -e 's/ *= */=/g' -e 's/;$//' | \
        # ignore empty lines \
        egrep -v '^$' | while read LINE; do
        if echo "$LINE" | egrep -q "="; then
            case $JAIL in
                $jail)
                    var=`echo "$LINE" | cut -d= -f1`
                    opt=`echo "$LINE" | cut -d= -f2 | sed -e 's/^"//' -e 's/"$//'`
                    case $var in
                        $search)
                            if test -z "$list"; then
                                list="$opt"
                            else
                                list="$list,$opt"
                            fi
                            ;;
                    esac
                    ;;
                *)
                    echo $list
                    return
                    ;;
            esac
        else
            case $LINE in
                \*) JAIL=any;;
                *)  JAIL="$LINE";;
            esac
        fi
    done
}



usage_build() {
    fin "Usage: $0 build <jail> [-m <start|stop|status>] [-b <base>] [-v <version>]
Mount <jail> to $j/build read-writable for maintenance. Options:
-b <base>     Use specified <base>. default: use configured base.
-v <version>  Mount <version> of <jail>.
-m <mode>     One of start, stop or status. default: start."
}

jaildk_build() {
    local jail mode BASE VERSION base version

    jail=$1
    mode=start
    shift
    
    BASE=''
    VERSION=''

    OPTIND=1; while getopts "b:v:m:" arg; do
        case $arg in
            b) BASE=${OPTARG};;
            v) VERSION=${OPTARG};;
            m) mode=${OPTARG};;
            *) usage_build;;
        esac
    done

    if test -z "$jail" -o "$jail" = "-h"; then
        usage_build
    fi

    die_if_not_exist $jail $VERSION

    load_jail_config $jail

    if test -n "$VERSION"; then
        # overridden with -v
        version=$VERSION
    fi

    if test -n "$BASE"; then
        # dito
        base=$BASE
    else
        if test -n "$buildbase"; then
            base="$buildbase"
        elif test -z "$base"; then
            # nothing configured, use default: latest
            base=`ls $j/base | tail -1`
        fi
    fi

    # install the jail to build/
    jaildk_install $jail -m $mode -r all -w -b $base -v $version

    case $mode in
        start)
            # make it usable
            ex chroot $j/build/$jail /etc/rc.d/ldconfig onestart
            ex chroot $j/build/$jail pkg-static bootstrap -f
            ex mkdir -p $j/build/$jail/usr/local/db
            ;;
    esac
}

pf_ruleset() {
    # internal helper to [un]install a pf ruleset
    local conf mode anchor jail
    conf=$1
    mode=$2
    anchor=$3
    jail=$4

    case $mode in
        start)
            bold "Installing PF rules for jail $jail:"
            pfctl -a /jail/$anchor -f $conf -v
            ;;
        status)
            bold "PF NAT rules for jail $jail:"
            pfctl -a /jail/$anchor -s nat -v
            echo
            bold "PF rules for jail $jail:"
            pfctl -a /jail/$anchor -s rules -v
            ;;
        stop)
            bold "Removing PF rules for jail $jail:"
            pfctl -a /jail/$anchor -v -F all
            ;;
        restart)
            pf_ruleset $conf stop  $anchor $jail
            pf_ruleset $conf start $anchor $jail
            ;;
    esac
}

pf_map() {
    local extif proto eip eport mport ip v6

    extif=$1
    proto=$2
    eip=$3
    eport=$4
    mport=$5
    ip=$6
    from=$7
    v6=${8:-inet}

    echo "rdr pass on $extif $v6 proto ${proto} from ${from} to ${eip} port ${eport} -> ${ip} port ${mport}"
}

pf_rule() {
    local extif proto eip eport v6

    extif=$1
    proto=$2
    eip=$3
    eport=$4
    v6=$5

    echo "pass in quick on $extif $v6 proto ${proto} from any to ${eip} port ${eport}"
}

pf_nat() {
    local extif srcip dstip v6

    extif=$1
    srcip=$2
    dstip=$3
    v6=$4

    echo "nat on $extif $v6 from $srcip to any -> $dstip"
}

rc_pf() {
    local jail mode conf ruleset extif ipv4 anchor proto eport mport eports eip allowfrom port

    jail=$1
    mode=$2
    conf=$j/etc/$jail/pf.conf
    ruleset=$j/etc/$jail/pf-ruleset.conf
    
    load_jail_config $jail

    if test -z "$ip" -a -z "$ip6"; then
        echo "PF not supported without configured ip address!" >&2
        return
    fi
    
    # TODO:
    # - put this into a separate function
    # - clean up if generation of pf-ruleset.conf fails somehow
    # - make a syntax check of the generated rules, if possible
    case $mode in
        start|restart)
            if test -n "$masq_ip" -o -n "$rules" -o -n "$maps"; then
                # generate a pf.conf based on config variables
                echo "# generated pf ruleset for jail, generated on ` date`" > $ruleset
                extif=$(netstat -rnfinet | grep default | cut -f4 -w)

                # we need to make sure the ip address doesn't contain a mask which
                # is not required for these rules
                ipv4=$(dirname $ip)
                ipv6=$(dirname $ip6)
            
                if test -n "$ipv4" -a -n "$maps"; then
                    # nat and rdr come first
                
                    # SAMPLE ruleset
                    # maps="web ntp kjk"
                    # map_web_proto="tcp"
                    # map_web_exposed_port=80
                    # map_web_mapped_port=8080
                    # map_web_exposed_ip="123.12.12.3"
                    # map_web_allow_from="any" # | ip | ip list | table
                    # map_ntp_proto="udp"
                    # map_ntp_exposed_port=123
                    # map_ntp_mapped_port=1234
                    # map_ntp_exposed_ip="123.12.12.33"
                    # map_kjk_proto="tcp"
                    # map_kjk_exposed_port="1501 1502 1502}" # maped 1:1
                    # map_kjk_exposed_ip="123.12.12.33"

                    for map in $maps; do
                        # slurp in the values for this map
                        eval proto=\${map_${map}_proto:-tcp}
                        eval eport=\${map_${map}_exposed_port}
                        eval mport=\${map_${map}_mapped_port:-"${eport}"}
                        eval eip=\${map_${map}_exposed_ip:-$extif}
                        eval allowfrom=\${map_${map}_allow_from:-any} # == from any|ips
                        
                        if test -z "${eport}" -o -z "${eip}"; then
                            echo "Warning: ignoring incomplete map: $map!"
                            continue
                        fi

                        if test -n "${eport}"; then
                            echo "# from map $map" >> $ruleset
                            for port in $eport; do
                                if echo "${eport}" | grep -q " "; then
                                    # multiple eports, map 1:1
                                    mport=${port}
                                elif test -z "${mport}"; then
                                    mport=${port}
                                fi
                                pf_map "$extif" "${proto}" "${eip}" "${port}" "${mport}" "${ipv4}" "${allowfrom}" >> $ruleset
                            done
                        fi
                    done
                fi

                # masq_ip="123.12.12.33"
                if test -n "$ipv4" -a -n "${masq_ip}"; then
                    pf_nat $extif $ipv4 ${masq_ip} >> $ruleset
                fi
            
                if test -n "$ip6" -a -n "$rules"; then
                    # only required for ipv6, ipv4 is already opened with exposed ports
                    # rules="open web"
                    # rule_open="any"
                    # rule_web_proto="tcp"
                    # rule_web_port="80,443"
                    for rule in $rules; do
                        eval proto=\${rule_${rule}_proto:-tcp}
                        eval eport=\${rule_${rule}_port}

                        if test -n "${eport}"; then
                            echo "# from rule $rule" >> $ruleset
                            pf_rule $extif ${proto} ${ipv6} ${eport} inet6 >> $ruleset
                        else
                            echo "Warning: incomplete rule: $rule!"
                            continue
                        fi
                    done
                fi
            fi
            ;;
    esac

    if test -s $ruleset; then
        anchor="${jail}-jaildk"
        pf_ruleset $ruleset $mode $anchor $jail
    fi
    
    if test -s $conf; then
        anchor="${jail}-custom"
        pf_ruleset $conf $mode $anchor $jail
    fi
}

rc_mtree() {
    local jail mode base version rw conf

    jail=$1
    mode=$2
    base=$3
    version=$4
    rw=$5
    rcscript=mtree

    conf=$j/etc/$jail/$rcscript.conf

    if test -s $conf; then
        case $mode in
            start|restart)
                if test -n "$rw"; then
                    run=$j/build/$jail/
                else
                    run=$j/run/$jail/
                fi

                # needs to run inside jail
                echo "cat $j/etc/$jail/mtree.conf | chroot $run mtree -p / -Ue | grep -v extra:"
                cat $j/etc/$jail/mtree.conf | chroot $run mtree -p / -Ue | grep -v "extra:"
                ;;
        esac
    fi
}

rc_rcoff() {
    # avoid starting services inside the build chroot
    # + rc_rcoff db start 12.1-RELEASE-p10 20201026
    local jail mode base VERSION BASE rw

    jail=$1
    mode=$2
    BASE=$3
    VERSION=$4
    rw=$5
    rcscript=rcoff

    if test -n "$rw"; then
        # not required in run mode
        case $mode in
            start)
                if mount | egrep -q "rcoff.*build/$jail"; then
                    bold "union mount $j/build/jail/etc already mounted"
                else
                    if ! test -d $j/etc/rcoff; then
                        # in order to be backwards compatible to older jaildk
                        # create the rcoff directory on the fly
                        mkdir -p $j/etc/rcoff
                        ( echo "#!/bin/sh"
                          echo 'echo "$0 disabled in build chroot!"' ) > $j/etc/rcoff/rc
                    fi

                    ex mount -t unionfs $j/etc/rcoff $j/build/$jail/etc
                fi
                ;;
            stop)
                # might fail if executed on a yet not union'ed etc
                if mount | egrep -q "rcoff.*build/$jail"; then
                    ex umount $j/build/$jail/etc
                fi
                ;;
        esac
    fi
}

rc_ports() {
    local jail mode BASE VERSION rw

    jail=$1
    mode=$2
    BASE=$3
    VERSION=$4
    rw=$5
    rcscript=ports

    load_jail_config $jail

    if test -z "$ports"; then
        # ports not configured, abort
        return
    fi

    if ! test -d "$j/ports/$VERSION"; then
        die "Ports tree $j/ports/$VERSION doesn't exist yet. Consider creating it with 'jaildk fetchports [-v <version>]'"
    fi

    if test -n "$buildbase" -a -n "$rw"; then
        # we only support ports if a buildbase is configured
        case $mode in
            start)
                if mount -v | grep -q " $j/build/$jail/usr/ports "; then
                    bold "$j/build/$jail/usr/ports already mounted!"
                else
                    ex mount -t nullfs -o rw $j/ports/$version $j/build/$jail/usr/ports
                fi
                ;;
            stop)
                if mount -v | grep -q " $j/build/$jail/usr/ports "; then
                    ex umount $j/build/$jail/usr/ports
                else
                    bold "$j/build/$jail/usr/ports not mounted!"
                fi
                ;;
        esac
    fi
}

rc_mount() {
    local jail mode BASE VERSION rw conf run base version \
          src dest fs opts size perm source

    jail=$1
    mode=$2
    BASE=$3
    VERSION=$4
    rw=$5
    rcscript=mount

    load_jail_config $jail

    conf=$j/etc/$jail/$rcscript.conf

    if ! test -e "$conf"; then
        return
    fi

    if test -n "$rw"; then
        run=$j/build
        if test -n "$BASE"; then
            base=$BASE
        fi
        if test -n "$VERSION"; then
            version=$VERSION
        fi
    else
        run=$j/run
    fi

    die_if_not_exist $jail

    # parse the config and (u)mount
    case $mode in
        stop)
            tail -r $conf | grep -v "#"
            ;;        
        *)
            grep -v "#" $conf
            ;;
    esac | while read LINE; do
        # This command expands variables and performs field-splitting:
        set -- $(eval echo \""$LINE"\")

        # Skip empty lines:
        case "$1" in
            "")    continue ;;
        esac

        src=$1
        dest=$2
        fs=$3
        opts=$4
        size=$5
        perm=$6

        if test -n "$rw"; then
            if ! echo $src | grep -q base/; then
              opts=`echo "$opts" | sed 's/ro/rw/g'`
            fi
        fi

        case $mode in
            start)
                if mount -v | grep " $run/$dest " > /dev/null ; then
                    bold "$run/$dest already mounted!"
                else
                    case $fs in
                        mfs)
                            ex mdmfs -o $opts -s $size -p $perm md $run/$dest
                            ;;
                        nullfs|unionfs)
                            source=$j/$src
                            if echo $src | egrep -q "^/"; then
                              source=$src
                            fi

                            if ! test -d "$source"; then
                                die "Source dir $source doesn't exist!"
                            fi

                            if ! test -d "$run/$dest"; then
                                die "Dest dir $run/$dest doesn't exist!"
                            fi

                            ex mount -t $fs -o $opts $source $run/$dest
                            ;;
                        devfs)
                            ex mount -t devfs dev $run/$dest
                            ;;
                        *)
                            bold "unknown filesystem type $fs!"
                            ;;
                    esac
                fi
                ;;
            stop)
                if mount -v | grep " $run/$dest " > /dev/null ; then
                    ex umount $run/$dest
                    if mount -v | grep " $run/$dest " > /dev/null ; then
                        # still mounted! forcing
                        ex umount -f $run/$dest
                    fi
                else
                    bold "$run/$dest not mounted!"
                fi
                ;;
            status)
                if mount -v | grep " $run/$dest " > /dev/null ; then
                    echo "$run/$dest mounted"
                else
                    bold "$run/$dest not mounted"
                fi
                ;;
            *)
                bold "Usage: $0 install <jail> mount {start|stop|status|restart}"
                ;;
        esac
    done
}



usage_install() {
    fin "Usage: $0 install <jail> [-m <mode>] [-r rc-function]
Install <jail> according to its config. Options:
-m <mode>       Mode can either be start, stop or status. default: start
-r <function>   Only execute function with <mode> parameter. default: all.

Available rc.d-scripts: $RCSCRIPTS_START"
}
        
jaildk_install() {
    local jail mode rcd rw base version rcscripts type

    jail=$1
    mode=start
    shift
    rcd=''

    # options -b -w -v are undocumented, used by jaildk_build() only
    rw=''
    base=''
    version=''

    OPTIND=1; while getopts "r:b:v:wm:" arg; do
        case $arg in
            w) rw=1;;
            b) base=${OPTARG};;
            v) version=${OPTARG};;
            r) rcd=${OPTARG};;
            m) mode=${OPTARG};;
            *) usage_install;;
        esac
    done

    if test -z "$jail" -o "$jail" = "-h"; then
        usage_install
    fi

    if test -z "$rcd"; then
        # default just install everything
        rcd=all
    fi
    
    case $mode in
        start|stop|restart|status) :;;
        *) usage_install;;
    esac

    die_if_not_exist $jail

    if test "$rcd" = "all"; then
        if test -n "$rw"; then
            case $mode in
                start) rcscripts="$RW_RCSCRIPTS_START";;
                stop)  rcscripts="$RW_RCSCRIPTS_STOP";;
            esac
        else
            case $mode in
                start) rcscripts="$RCSCRIPTS_START";;
                stop)  rcscripts="$RCSCRIPTS_STOP";;
            esac
        fi
    else
        rcscripts="rc_${rcd}"
        if ! type "$rcscripts" > /dev/null 2>&1; then
            die "rc function $rcd doesn't exist!"
        fi
    fi

    type="jail"
    if test -n "$rw"; then
        type="build chroot"
    fi

    case $mode in
        start)
            bold "Installing $type $jail"
            ;;
        stop)
            bold "Unstalling $type $jail"
            ;;
    esac

    for rcscript in $rcscripts; do
        $rcscript $jail $mode $base $version $rw || exit 1
    done
}

usage_uninstall() {
    fin "Usage: $0 uninstall <jail> [-w]
Uninstall <jail>. Options:
-w      Uninstall writable build chroot.
-a      Uninstall jail and build chroot."
}

jaildk_uninstall() {
    # wrapper around _install
    local jail mode base version all rw

    jail=$1
    shift
    rw=''
    all=''
    base=''
    version=''

    OPTIND=1; while getopts "wa" arg; do
        case $arg in
            w) rw="-w";;
            a) all=1; rw="-w";;
            *) usage_uninstall;;
        esac
    done

    if test -z "$jail" -o "$jail" = "-h"; then
        usage_uninstall
    fi

    die_if_not_exist $jail

    if jls | egrep -q "${jail}"; then
        die "Jail $jail($version) is still running, stop it before removing!"
    fi

    if test -n "$rw"; then
        # we need to find out base and version of actually
        # mounted jail, but cannot just use the jail config
        # since the user might have mounted another version
        base=$(mount | egrep "/base/.*/$jail " | cut -d' ' -f1 | sed 's|.*/||')
        version=$(mount | egrep "/appl/.*/$jail/" | cut -d' ' -f1 | sed 's/.*\-//')
    fi

    if test -z "$base"; then
        # no base no umount!
        rw=''
        all=''
    fi

    if test -n "$all"; then
        jaildk_install $jail -m stop -r all
        jaildk_install $jail -m stop -r all -b $base -v $version -w
    else
        jaildk_install $jail -m stop -r all -b $base -v $version $rw
    fi
}


usage_base() {
    fin "Usage: $0 base [-f] -b <basename|basedir> [-w]
Build a base directory from bsd install media. Options:
-b <name>     <name> can be the name of a base (e.g. 12.2-RELEASE)
              or a directory where it shall be created
-w            Create a writable base, including compiler and other
              build stuff. Use this if you want to use the ports
              collection.
-f            force mode, remove any old dist files.
-s <script>   install additional scripts to /usr/bin, separate multiple
              scripts with whitespace.
"
}

jaildk_base() {
    local jail mode base force removelist basedir clean file rw

    base=""
    force=""
    rw=""
    scripts=""

    OPTIND=1; while getopts "b:wfs:" arg; do
        case $arg in
            w) rw=1;;
            b) base=${OPTARG};;
            s) scripts="${OPTARG}";;
            f) force=1;;
            *) usage_base;;
        esac
    done

    if test -z "$base"; then
        usage_base
    fi

    removelist="tests
usr/bin/objdump
usr/bin/llvm-profdata
usr/bin/ranlib
usr/bin/ar
usr/bin/as
usr/bin/llvm-tblgen
usr/bin/llvm-symbolizer
usr/bin/llvm-cov
usr/bin/llvm-objdump
usr/bin/ld.lld
usr/bin/lldb
usr/bin/cpp
usr/bin/clang-cpp
usr/bin/clang++
usr/bin/clang
usr/bin/cc
usr/bin/c++
usr/bin/lex
usr/bin/lex++
usr/bin/flex
usr/bin/flex++
usr/bin/telnet
usr/bin/kadmin
usr/bin/kcc
usr/bin/kdestroy
usr/bin/kdump
usr/bin/keylogin
usr/bin/keylogout
usr/bin/kf
usr/bin/kgetcred
usr/bin/kinit
usr/bin/klist
usr/bin/kpasswd
usr/bin/krb5-config
usr/bin/ksu
usr/bin/kswitch
usr/bin/ktrace
usr/bin/ktrdump
usr/bin/finger
usr/bin/crunch*
usr/bin/ibv*
usr/bin/nc
usr/bin/pftp
usr/bin/ssh*
usr/bin/scp
usr/bin/sftp
usr/bin/svn*
usr/bin/yacc
usr/include
usr/lib/*.a
usr/lib32/*.a
usr/share/doc
usr/share/dict
usr/share/examples
usr/share/man
rescue
media
mnt
boot
var/run
var/cache
var/tmp"

    if echo "$base" | egrep -vq "^/"; then
        basedir=$j/base/$base
    else
        basedir=$base
    fi

    if test -d "$basedir"; then
        echo "base $basedir already exist!"
        exit 1
    fi

    ex mkdir -p $basedir

    if test -e /usr/freebsd-dist/MANIFEST; then
        clean=''
        if test -n "$force"; then
            clean=1
        else
            echo "Found old dist files:"
            ls -l /usr/freebsd-dist
            echo -n "Want to remove them [nY]? "
            read yesno
            case $yesno in
                y|Y) clean=1;;
                *)   clean='';;
            esac
        fi

        if test -n "$clean"; then
            ex rm -f /usr/freebsd-dist/*
        fi
    fi

    bsdinstall jail $basedir || exit 1

    if test -z "$rw"; then
        # run base
        for file in $removelist; do
            ex rm -rf $basedir/$file
        done
    else
        # build base with ports support
        ex mkdir -p $basedir/usr/ports
    fi
    
    ex mkdir $basedir/home
    ex rm -rf $basedir/var/db
    ex ln -s /usr/local/db $basedir/var/db

    # add some symlinks from /var to /tmp to make pkg work properly 
    ex rm -rf $basedir/var/tmp $basedir/var/cache $basedir/var/run
    ex ln -s /tmp $basedir/var/tmp
    ex ln -s /tmp $basedir/var/cache
    ex ln -s /tmp $basedir/var/run

    # any scripts?
    for script in $scripts; do
        ex install -m 755 $script -o root -g wheel $basedir/usr/bin/$script
    done
    
    if test -n "$rw"; then
        echo "You have choosen to create a build base with ports support"
        echo -n "Want to fetch the ports collection now [Yn]? "
        read yesno
        case $yesno in
            y|Y|yes|YES)
                jaildk_fetchports
                ;;
        esac
    fi
}

clone() {
    local srcdir dstdir

    srcdir=$1
    dstdir=$2

    if test -d $srcdir; then
        if ! test -d $dstdir; then
            mkdir -p $dstdir
        fi

        if test $srcdir = $dstdir; then
            echo "$srcdir == $dstdir, ignored"
        else
            if test "$(ls -l $dstdir)" = "total 0"; then
                ex cpdup -x $srcdir $dstdir
            else
                echo "$dstdir already exists, ignored"
            fi
        fi
    else
        echo "$srcdir doesn't exist, ignored"
    fi
}

usage_clone() {
    fin "Usage: $0 clone -s <jail> -d <jail> [-o <version>] [-n <version>]
-s <jail>        Source jail to clone from
-d <jail>        Destionation jail to create from source
-o <version>     Old version
-n <version>     New version

Hints:
- if no source version has been given, tha latest version will be used.
- if no new version has been given, source version will be used.
- if source and new jail are the same, both versions must be given
  and a new version of the same jail will be created (update)"
}

jaildk_clone() {
    local src new srcversion newversion update cloneto clonefrom fs srcmount dstmount opts size perm

    OPTIND=1; while getopts "s:d:o:n:" arg; do
        case $arg in
            o) srcversion=${OPTARG};;
            n) newversion=${OPTARG};;
            s) src=${OPTARG};;
            d) new=${OPTARG};;
            *) usage_clone;;
        esac
    done

    if test -z "$new"; then
        usage_clone
    fi

    if test "$src" = "$new"; then
        # same jail, expect different versions
        if test -z "$newversion" -o -z "$srcversion"; then
            die "source and new version required!"
        fi

        if test "$srcversion" = "$newversion"; then
            die "new version must be different from source version!"
        fi
        update=1
    fi

    die_if_not_exist $src "Source jail"
    load_jail_config $src

    if test -z "$srcversion"; then
        srcversion=$version
    fi

    if test -z "$newversion"; then
        newversion=$version
    fi

    if ! test -d $j/etc/$src/etc-$srcversion; then
        die "Version $srcversion of source jail $src doesn't exist!"
    fi

    if test -e "$j/etc/$src/mount.conf"; then
        grep -v "#" $j/etc/$src/mount.conf | while read srcmount dstmount fs opts size perm; do
            # we are  not automatically interpolating  variables here,
            # because it's much more easier to replace \$name with the
            # jail name than an already  resolved $name which might be
            # part of the  path and cause confusion what  to clone and
            # what not.
            if test -z "$srcmount"; then
                continue
            fi

            cloneto=$(echo "$srcmount" | sed -e "s/\$version/$newversion/g" -e "s/\$name/$new/g")
            clonefrom=$(echo "$srcmount" | sed -e "s/\$version/$srcversion/g" -e "s/\$name/$src/g")

            case $fs in
                nullfs)
                    if ! echo "$srcmount" | egrep -q "^/"; then
                        # only clone mounts relative  to $j, which are
                        # either versioned  or have the src  jail name
                        # in it
                        if echo "$srcmount" | egrep -q '\$version|\$name'; then
                            # srcversion versioned nullfs mount at $j/
                            clone $j/$clonefrom $j/$cloneto
                        fi
                    fi
                    ;;
            esac
        done
    else
        die "Error: $j/etc/$src/mount.conf doesn't exist, cannot clone!"
    fi

    if test -z "$update"; then
        echo "Copying configs"
        ex cp -pRp $j/etc/$src/*.conf $j/etc/$new/

        echo "Creating $j/etc/$src/jail.conf"
        cat $j/etc/$src/jail.conf | egrep -v "^(name|version)=" >  $j/etc/$new/jail.conf
        (echo "name=$new"; echo "version=$newversion")          >> $j/etc/$new/jail.conf

        echo "Creating run and build dirs"
        ex mkdir -p $j/run/$new
        ex mkdir -p $j/build/$new
    fi

    echo "DONE."

    if test -z "$update"; then
        if ! egrep -q "^$new" /etc/jail.conf; then
            bold "Consider adding the jail $new to /etc/jail.conf!"
            echo
        fi

        bold "To mount the build chroot of the new jail, execute:"
        echo "jaildk build $new -m start"
        echo
        bold "To login into the build chroot"
        echo "jaildk blogin $new"
        echo
        bold "To mount the production chroot of the new jail, execute:"
        echo "jaildk install $new"
        echo
        bold "To login into the build chroot"
        echo "jaildk login $new"
        echo
        bold "To start the jail, execute:"
        echo "jaildk start $new"
        echo
    else
        . $j/etc/$src/jail.conf
        # FIXME: possibly not needed! see comment in jaildk_create()
        # jail=$new
        bold "To mount the build chroot of the new jail, execute:"
        echo "jaildk build $new start -b $base -v $newversion"
    fi
}

usage_create() {
    fin "Usage: $0 create <jail>
Create a new jail from template."
}

jaildk_create() {
    local jail newjail src srcversion newversion jailhostname
    jail=$1
    # $jail gets overwritten in jaildk_clone or some subcall to .template :-( ...
    newjail=$jail
    
    src=.template
    
    if test -z "$jail" -o "$jail" = "-h"; then
        usage_create
    fi

    . $j/etc/$src/jail.conf
    srcversion=$version
    newversion=`date +%Y%m%d`

    mkdir -p $j/etc/$jail
    
    jaildk_clone -s $src -d $jail -o $srcversion -n $newversion
    jailhostname=$(cat /etc/jail.conf | grep -E "^$jail" -A50 | sed '/\}/q' | grep hostname | cut -d\" -f2)
    if [ -n "$jailhostname" ]; then
        echo "new name: $jailhostname"
        echo "in path $j/etc/$jail/local-etc-$newversion/rc.conf"
        sed -iE 's/^hostname.*$/hostname="'"$jailhostname"'"/' $j/etc/$newjail/local-etc-$newversion/rc.conf
    fi     
}

remove() {
    local dir=$1

    if test -d $dir; then
        ex rm -rf $dir
    else
        echo "$dir doesn't exist anymore"
    fi
}

usage_remove() {
    fin "Usage: $0 remove <jail> [-v <version>]
Remove <jail> from disk."
}

jaildk_remove() {
    local jail version
    jail=$1
    shift
    version=''

    OPTIND=1; while getopts "v:" arg; do
        case $arg in
            v) version=${OPTARG};;
            *) usage_remove;;
        esac
    done

    if test -z "$jail" -o "$jail" = "-h"; then
        usage_remove
    fi

    if jls | egrep -q "${jail}"; then
        die "Jail $jail($version) is still running, stop it before removing!"
    fi

    if mount | egrep -q "${jail}.*${version}"; then
        die "Jail $jail($version) is still mounted, umount it before removing!"
    fi

    die_if_not_exist $jail

    if test -n "$version"; then
        if ! test -d $j/etc/$jail/etc-$version; then
            die "Jail $jail $version doesn't exist!"
        fi

        remove $j/etc/$jail/etc-$version
        remove $j/etc/$jail/local-etc-$version
        remove $j/home/$jail/root-$version
        remove $j/log/$jail-$version
        remove $j/data/$jail/www
        remove $j/data/$jail/spool
    else
        remove $j/etc/$jail
        remove $j/home/$jail
        remove $j/log/$jail-*
        remove $j/data/$jail
    fi
}

jaildk_jail_usage() {
    fin "Usage: $0 <start|stop|restart|status> <jail> | status"
}

usage_start() {
    fin "Usage $0 start <jail>
Start <jail>."
}

usage_stop() {
    fin "Usage $0 stop <jail>
Stop <jail>."
}

usage_restart() {
    fin "Usage $0 restart <jail>
Restart <jail>."
}

usage_status() {
    fin "Usage $0 status [<jail>]
Show status of <jail>. Without <jail>, show status of all jails."
}


jaildk_jail() {
    # reversed argument order here so that $jail is optional, in which
    # case the command works on all jails
    local jail mode jid ip path runs build base _eip ip4addr osrelease path build lookup

    mode=$1
    jail=$2

    if test "x$mode" = "xstatus"; then
        (
            if test -z "$jail" -o "$jail" = "-h"; then
                bold "Running jails:"
                lookup='*'
            else
                bold "Status $jail:"
                lookup=$jail
            fi

            echo "Jail IP-Address Path Is-Running RW-mounted Current-Version Base"
            grep -h "name=" $j/etc/$lookup/jail.conf | cut -d= -f2 | while read jail; do
                jid=''
                ip=''
                path=''
                runs=''
                build='no'
                base=''

                load_jail_config $jail

                _eip=''
                for map in $maps; do
                    eval _eip=\${map_${map}_exposed_ip}
                    if test -n "${_eip}"; then
                        # we only display the first exposed ip we find, if any
                        break
                    fi
                done

                if jls -j $jail > /dev/null 2>&1; then
                    # jail is running, get some data about jail
                    eval $(jls -j v6 -qn ip4.addr ip6.addr jid)
                    if test -n "$ip4addr"; then
                        ip=$ip4addr
                    else
                        if test -z "$ip"; then
                            ip="n/a"
                        else
                            # ip configured
                            if test -n "${_eip}"; then
                                ip="${_eip}->${ip}"
                            fi
                        fi
                    fi
                    jid="yes,jid=$jid"
                else
                    jid="no"
                    path=$j/run/$jail
                    if test -z "$ip"; then
                        ip="n/a"
                    fi
                fi

                if mount | egrep "$j/build/$jail" > /dev/null 2>&1; then
                    build='yes'
                fi

                echo "$jail $ip $path $jid $build $version $base"
            done
        ) | column -t

        if test -n "$jail"; then
            jaildk_rc $jail -m status
        fi
    elif test -z "$jail" -o "$jail" = "-h"; then
        usage_$mode
    else
        bold "Jail $jail $mode:"
        case $mode in
            *)
                service jail $mode $jail
                jaildk_ipfw $jail -m $mode
                ;;
        esac
    fi
}

get_rc_scripts() {
    local jail jailpath files rcvar name
    jail="$1"
    jailpath=`get_jail_path $jail`

    files=$(ls $j/run/$jailpath/usr/local/etc/rc.d/* $j/run/$jailpath/etc/rc.d/* 2>/dev/null)

    rcorder $files 2>/dev/null | while read SCRIPT; do
        # we need to fetch the rcvar variable. sometimes these scripts
        # use ${name}_enable, so we also  fetch the $name variable and
        # interpolate $rcvar accordingly
        rcvar=`egrep "^rcvar=" $SCRIPT | cut -d= -f2 | sed 's/"//g' | tail -1`
        name=`egrep "^name=" $SCRIPT | cut -d= -f2 | sed 's/"//g' | tail -1`
        rcvar=$(eval echo "$rcvar")
        if egrep -iq "^${rcvar}=.*yes" $j/run/$jailpath/usr/local/etc/rc.conf; then
            echo $SCRIPT | sed "s|$j/run/$jailpath||"
        fi
    done
}

usage_rc() {
    fin "Usage: $0 rc <jail> [-m <mode>] [-r <rc.d script]
Execute an rc.d script inside <jail> with parameter <mode>. Options:
-r <rc.d script>    Execute <rc.d script>. default: execute all enabled scripts."
}

jaildk_rc() {
    local jail mode rcd jailpath ok script jid

    jail=$1
    shift
    
    rcd=''

    OPTIND=1; while getopts "r:m:" arg; do
        case $arg in
            r) rcd=${OPTARG};;
            m) mode=${OPTARG};;
            *) usage_rc;;
        esac
    done

    if test -z "$rcd"; then
        rcd='all'
    fi

    if test -z "$jail" -o "$jail" = "-h" -o -z "$mode"; then
        usage_rc
    fi

    if ! jls | egrep -q "${jail}"; then
        die "Jail $jail is not running."
    fi
  
    rcs=`get_rc_scripts $jail`
    
    jid=`get_jid $jail`
    jailpath=`get_jail_path $jail`
    if test $rcd = "all"; then
        if [ "$jail" == "$jailpath" ]; then
            bold "Jail $jail rc status:"
        else
            bold "Jail $jail/$jailpath rc status:"
        fi
        for script in $rcs; do
            jexec $jid $script $mode
        done
    else
        ok=''
        for script in $rcs; do
            if echo "$script" | egrep -q "/${rcd}\$"; then
                jexec $jid $script $mode
                ok=1
            fi
        done

        if test -z "$ok"; then
            die "Script $rc doesn't exist in $jail or is not enabled."
        fi
    fi
}

get_jail_path() {
    local jail="$1"
    echo "$(jls |grep -E " ${jail} " | awk '{print $NF}' | xargs basename)"
}

get_jid() {
    local jail="$1"
    echo "$(jls | grep -E  " ${jail} " | awk '{print $1}' | xargs basename)"
}

usage_blogin() {
    err "Usage: $file <jail>
Chroot into a build jail.

Mounted build chroot's:"
    mount|egrep "base.*build" | awk '{print $3}' | cut -d/ -f 4
    exit 1
}

jaildk_blogin() {
    local jail chroot file shell term home path

    jail=$1

    if test -z "$jail" -o "$jail" = "-h"; then
        file=`basename $0`
        if test "$file" = "jaildk"; then
            file="$0 blogin"
        else
            file="$0"
        fi
        usage_blogin
    fi

    chroot="$j/build/$jail"

    if ! test -d $chroot/root; then
	    echo "build jail $jail not mounted!"
	    echo "Mount it with jaildk build $jail start"
	    exit 1
    fi

    shell=/bin/csh
    term=vt100
    home=/root
    path=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin

    if test -e $chroot/root/.bashrc; then
        shell=/usr/local/bin/bash
    fi

    chroot $chroot /etc/rc.d/ldconfig onestart > /dev/null 2>&1
    env - HOME=$home TERM=$term SHELL=$shell PATH=$path chroot $chroot $shell
}

usage_login() {
    err "Usage: $file <jail-name|jail-domain|jail-ip> [<user>]
Login into a jail by name, ip or domain. If <user> has not been
specified, login as root. 

Available jails:"
    jls
    exit 1
}

jaildk_login() {
    local jail user chroot file shell term home path me

    jail=$1
    user=$2
    me=`id -u` 
    jexec="jexec"

    if test -z "$jail" -o "$jail" = "-h"; then
        file=`basename $0`
        if test "$file" = "jaildk"; then
            file="$0 jlogin"
        else
            file="$0"
        fi
        usage_login
    fi

    jid=""
    jid=`jls | grep "$jail" | awk '{print $1}'`

    if test -z "$jid"; then
        echo "jail $jail doesn't run!"
        exit 1
    fi

    shell=/bin/csh
    home=/home/$user
    term=vt100
    path=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
    chroot="$j/run/$jail"

    if test -z "$user"; then
        user=root
        home=/root
    fi

    if test -e $chroot/$home/.bashrc; then
        shell=/usr/local/bin/bash
    fi

    if test "$me" != "0"; then
        jexec="sudo $jexec"
    fi

    echo "# Logging into jail $jail with jid $jid #"
    env - JAIL=$jail HOME=$home TERM=$term SHELL=$shell PATH=$path $jexec -U $user $jid $shell
}

usage_reinstall() {
    fin "Usage: $0 reinstall <jail> [-b <base>] [-v <version>]
Stop, uninstall, install and start <jail>. If <base> and/or
<version> is given, modify the jail config before reinstalling.
"
}

jaildk_reinstall() {
    local jail NEWBASE NEWVERSION ts change base version
    
    jail=$1
    shift

    OPTIND=1; while getopts "b:v:" arg; do
        case $arg in
            b) NEWBASE=${OPTARG};;
            v) NEWVERSION=${OPTARG};;
            *) usage_reinstall;;
        esac
    done

    if test -z "$jail" -o "$jail" = "-h"; then
        usage_reinstall
    fi

    die_if_not_exist $jail

    if jls | egrep -q "${jail}"; then
        jaildk_jail stop $jail
    fi

    jaildk_uninstall $jail

    sleep 0.2
    sync

    if test -n "$NEWBASE" -o -n "$NEWVERSION"; then
        load_jail_config $jail
        ts=`date +%Y%m%d%H%M`
        change=''
        if test $NEWBASE != $base; then
            base=$NEWBASE
            change=1
        fi

        if test $NEWVERSION != $version; then
            version=$NEWVERSION
            change=1
        fi

        if test -n "$change"; then
            bold "Saving current $jail config"
            ex cp -p $j/etc/$jail/jail.conf $j/etc/$jail/jail.conf-$ts

            bold "Creating new $jail config"
            cat $j/etc/$jail/jail.conf-$ts \
                | sed -e "s/^base=.*/base=$base/" -e "s/^version=.*/version=$version/" \
                > $j/etc/$jail/jail.conf
        fi
    fi

    jaildk_install $jail -m start
    jaildk_jail start $jail

    sleep 0.2

    jaildk_jail status $jail
}

_install_jaildk() {
    realj=`cd $j; pwd`
    sed "s|^JAILDIR=.*|JAILDIR=$realj|" $0 > $j/bin/jaildk
    ex chmod 755 $j/bin/jaildk
}

jaildk_setup() {
    local j version subdir
    
    j=$1

    if test -z "$j"; then
        fin "Usage: $0 setup <base dir for jail environment>"
    fi

    if test -e "$j/bin/jaildk"; then
        bold "$j/bin/jaildk aleady exists, updating..."
        _install_jaildk $j
        return
    fi
    
    bold "preparing directories"
    ex mkdir -p $j
    for subdir in etc bin appl base data home log run ports; do
        ex mkdir -p $j/$subdir
    done

    version=`date +%Y%m%d`

    for subdir in appl/default-$version/db/ports \
                      appl/default-$version/etc \
                      etc/.template/etc-$version \
                      etc/.template/local-etc-$version \
                      home/.template/root-$version log/.template-$version; do
        ex mkdir -p $j/$subdir
    done

    bold "building jail template"
    ex cpdup /etc $j/etc/.template/etc-$version
    echo "creating $j/etc/.template/etc-$version/rc.conf"
    rm -f $j/etc/.template/etc-$version/rc.conf
    echo 'rc_conf_files="/etc/rc.conf /etc/rc.conf.local /usr/local/etc/rc.conf"' > $j/etc/.template/etc-$version/rc.conf

    echo "creating $j/etc/.template/local-etc-$version/rc.conf"
    echo 'hostname="TEMPLATE"
sendmail_enable="NO"
sendmail_submit_enable="NO"
sendmail_outbound_enable="NO"
sendmail_msp_queue_enable="NO"' > $j/etc/.template/local-etc-$version/rc.conf

    bold "creating template config $j/etc/.template/jail.conf"
    os=`uname -r`
    (echo "base=$os"; echo "version=$version"; name=template) > $j/etc/.template/jail.conf

    bold "creating template config $j/etc/.template/mount.conf"
    echo 'base/$base                     $name                               nullfs  ro
md                             $name/tmp                           mfs     rw,nosuid,async  128m 1777
dev                            $name/dev                           devfs
log/$name-$version             $name/var/log                       nullfs  rw
appl/default-$version          $name/usr/local                     nullfs  ro
etc/$name/etc-$version         $name/etc                           nullfs  ro
etc/$name/local-etc-$version   $name/usr/local/etc                 nullfs  ro
home/$name/root-$version       $name/root                          nullfs  rw' > $j/etc/.template/mount.conf

    bold "creating template config $j/etc/.template/ports.conf"
    (echo bash; echo ca_root_nss) > $j/etc/.template/ports.conf

    bold "creating template config $j/etc/.template/ipfw.conf"
    touch $j/etc/.template/ipfw.conf

    bold "creating template config $j/etc/.template/mtree.conf"
    echo '/set type=dir uid=0 gid=0 mode=01777
.       type=dir mode=0755
tmp
var
cache
pkg
..
..
run
..
tmp' > $j/etc/.template/mtree.conf

    bold "installing jaildk"
    _install_jaildk $j

    bold "configuring root shell template"
    echo "# root shell inside jail
alias h         history 25
alias j         jobs -l
alias la        ls -a
alias lf        ls -FA
alias ll        ls -lA
alias l         ls -laF
alias ..        cd ..
alias ...       cd ../..
alias ....      cd ../../../
umask 22
set path = (/sbin /bin /usr/sbin /usr/bin /usr/local/sbin /usr/local/bin)
setenv  EDITOR  vi
setenv  PAGER   less
setenv  BLOCKSIZE       K
if (\$?prompt) then
 set chroot=`ps axu|grep /sbin/init | grep -v grep | awk '{print $1}'`
 if("\$chroot" == \"\") then
   set prompt = \"(jail) %N@%m:%~ %# \"
 else
   set prompt = \"(build chroot) %N@%m:%~ %# \"
 endif
 set promptchars = \"%#\"
 set filec
 set history = 1000
 set savehist = (1000 merge)
 set autolist = ambiguous
 # Use history to aid expansion
 set autoexpand
 set autorehash
endif
" > $j/home/.template/root-$version/.cshrc

    bold "building base"
    echo -n "Do you want to build a base directory [Yn]? "
    read yesno
    case $yesno in
        y|Y|yes|YES)
            jaildk_base -b $j/base/$os
            ;;
    esac
}

jaildk_version() {
    # parser friendly output
    echo "This is jaildk.
version=$version
jailbase=$j
"
}

usage_update() {
    die "Usage $0 update [f]
Update jaildk via git, needs internet access and git.
Use -f to force the update ignoring the version check.
"
}

jaildk_update() {
    local repo gitversion force
    rcscript=update
    force=''

    repo="https://github.com/TLINDEN/jaildk.git"
    mustberoot

    OPTIND=1; while getopts "f" arg; do
        case $arg in
            f) force=1;;
            *) usage_update;;
        esac
    done
    
    if test -w $j; then
        if ! test -d $j/git/jaildk; then
            ex mkdir -p $j/git || die "Could not mkdir $j/git"
            cd $j/git && ex git clone $repo || die "Could not clone $repo!"
        else
            cd $j/git/jaildk && ex git pull || die "Could not pull from $repo!"
        fi

        gitversion=$(egrep "^version=" $j/git/jaildk/jaildk | head -1 | cut -d= -f2)
        if test -n "$gitversion"; then
            if test 1 -eq $(echo "$gitversion > $version" | bc) -o -n "$force"; then
                echo "Updating jaildk from $version to version $gitversion..."
                ex make -C $j/git/jaildk
                ex install -o root -g wheel $j/git/jaildk/jaildk $j/bin/jaildk || die "Failed to update self!"
            else
                die "jaildk git version unchanged, aborting"
            fi
        else
            die "git version of jaildk in $j/git/jaildk/jaildk has no version!"
        fi
    else
        die "directory $j must be writable!"
    fi
}

usage_fetchports() {
    die "Usage $0 fetchports [-v <version>]
Fetch current portscollection, use <version> or todays timestamp as new version"
}

jaildk_fetchports() {
    local version=`date +%Y%m%d`

    OPTIND=1; while getopts "v:" arg; do
        case $arg in
            v) version=${OPTARG};;
            *) usage_fetchports;;
        esac
    done

    if test -d "$j/ports/$version"; then
        echo -n "Ports dir $version already exist. Do you want to recreate it [y/N]? "
        read yesno
        case $yesno in
            y|Y|yes|YES)
                ex rm -rf $j/ports/$version
                fetch_ports
                ;;
        esac
    else
        fetch_ports
    fi
}

fetch_ports() {
    ex mkdir -p $j/ports/tmp
    ex fetch -o $j/ports/tmp/ports.tar.gz http://ftp.freebsd.org/pub/FreeBSD/ports/ports/ports.tar.gz
    ex tar xzfC $j/ports/tmp/ports.tar.gz $j/ports/tmp
    ex mv $j/ports/tmp/ports $j/ports/$version
    ex rm -rf $j/ports/tmp/ports*
}

usage_freeze() {
    echo "Usage: $0 freeze <jail> [options]
Options:
 -v <version>   freeze <version> of <jail>
 -b             include the base layer (default: no)
 -a             include the application layer (default: no)"
    exit 1
}

freeze_dir() {
    local dstdir src srcdir layer layerfile

    dstdir=$1
    src=$2
    srcdir=$(echo $src | cut -d/ -f1)
    layer=$(echo $src | sed "s|$srcdir/||")
    layerfile=$(echo $layer | sed 's|/|-|g')

    ex tar -C $j/$srcdir -cpf $dstdir/$srcdir-$layerfile.tar $layer
}

jaildk_freeze() {
    local jail VERSION ADDBASE ADDAPPL version host freeze tmp mountconf \
          src dest fs opts size perm files
    
    jail=$1
    shift

    VERSION=""
    ADDBASE=""
    ADDAPPL=""

    OPTIND=1; while getopts "abv:" arg; do
        case $arg in
            a) ADDAPPL=1;;
            b) ADDBASE=1;;
            v) VERSION=${OPTARG};;
            *) usage_freeze;;
        esac
    done
    
    if test -z "$jail" -o "$jail" = "-h"; then
        usage_freeze
    fi

    die_if_not_exist $jail "Jail to freeze" $VERSION

    if jls | egrep -q "${jail}"; then
        echo    "The jail $jail is actually running. It's recommended"
        echo -n "to stop it before freezing. Stop the jail now [Ny]? "
        read yesno
        case $yesno in
            y|Y|yes|YES|Yes)
                service jail stop $jail
            ;;
        esac
    fi

    load_jail_config $jail

    if test -n "$VERSION"; then
        version=$VERSION
    fi

    bold "Freezing jail $jail $version"

    host=$(hostname | cut -d\. -f1)
    freeze=$j/images/$host-$jail-$version.tgz
    tmp=$j/images/tmp/$jail-$version
    ex mkdir -p $tmp

    mountconf=$j/etc/$jail/mount.conf

    if ! test -e "$mountconf"; then
        die "$mountconf doesn't exist!"
    fi

    # create sub tarballs from every layer
    grep -v "#" $mountconf | while read LINE; do
        # this is a copy of the code in rc_mount()
        # FIXME: put this into a function somehow
        set -- $(eval echo \""$LINE"\")

        # Skip empty lines:
        case "$1" in
            "")    continue ;;
        esac

        src=$1
        dest=$2
        fs=$3
        opts=$4
        size=$5
        perm=$6

        case $fs in
            nullfs)
                if ! echo $src | egrep -q "^/"; then
                    # only freeze nullfs mounts relative to $j
                    if echo $src | egrep -q "^base/"; then
                        if test -n "$ADDBASE"; then
                            freeze_dir $tmp $src
                        fi
                    elif echo $src | egrep -q "^appl/"; then
                        if test -n "$ADDAPPL"; then
                            freeze_dir $tmp $src
                        fi
                    else
                        freeze_dir $tmp $src
                    fi
                fi
                ;;
        esac
    done

    # add the jail config
    files=$(find $j/etc/$jail -type f -maxdepth 1)
    for file in $files; do
        cp -pP $file $tmp/
    done

    # build the final image file
    ex tar -C $j/images/tmp -cpf $freeze $jail-$version

    # cleaning up
    ex rm -rf $j/images/tmp

    bold "Done, jail $jail frozen to $freeze."
}

thaw_tarball() {
    local srcdir tarball layer

    srcdir=$1
    tarball=$2

    # etc-test-local-etc-20201128.tar
    layer=$(echo $tarball | cut -d\- -f1)

    if ! test -d $j/$layer; then
        ex mkdir -p $j/$layer
    fi

    ex tar -C $j/$layer -xf $srcdir/$tarball
    ex rm -f $srcdir/$tarball
}

usage_thaw() {
    fin "Usage: $0 thaw <image>"
}

jaildk_thaw() {
    local image j version jail tmp files bak

    image=$1

    if test -n "$J"; then
        j=$J
    fi

    jail=$(echo $image | cut -d\- -f2)
    version=$(echo $image | cut -d\- -f3 | cut -d\. -f1)

    if ! test -n "$version" -o -n "$jail"; then
        usage_thaw
    fi

    if test -d $j/etc/$jail/etc-$version; then
        bold -n "Jail $jail $version already exists, overwrite [Ny]? "
        read yesno
        case $yesno in
            y|Y|yes|YES|Yes)
                :;;
            *)
                echo "abort.";;
        esac
    fi

    bold "Thawing jail $image"

    tmp=$j/images/tmp
    ex mkdir -p $tmp

    # too many things can go wrong from here, so better abort on error
    set -e

    ex tar -C $tmp -xf $image

    if ! test -d $tmp/$jail-$version; then
        die "Invalid image format!"
        ex rm -rf $tmp
    fi

    for tarball in `cd $tmp/$jail-$version && ls *.tar`; do
        thaw_tarball $tmp/$jail-$version $tarball
    done

    files=$(find $tmp -type f)

    bak=""
    if test -e $j/etc/$jail/jail.conf; then
        bold -n "$j/etc/$jail/jail.conf already exist. Overwrite configs [Ny]? "
        read yesno
        case $yesno in
            y|Y|yes|YES|Yes)
                :;;
            *)
                bold "Copying configs with extension -$version"
                bak="-$version"
                ;;
        esac
    fi
        
    for file in $files; do
        filename=$(basename $file)
        ex cp -Pp $file $j/etc/$jail/$filename$bak
    done

    bold "Done. Thawed jail $jail $version from $image."
}

usage_ipfw() {
    echo "Usage: $0 ipfw <jail> -m <mode>
[Un]install ipfw rules. <mode> can be start or stop.
The jail needs to have a ipfw.conf file, containing
ipfw rules. You can use variables like \$ip and \$ip6
and you need to omit the 'ipfw add' of the command."
    exit 1
}

jaildk_ipfw() {
    local jail mode

    jail=$1

    if ! test -f "$j/etc/$jail/ipfw.conf"; then
        # dont do anything in non-ipf shells
        return
    fi

    OPTIND=1; while getopts "m:" arg; do
        case $arg in
            m) mode=${OPTARG};;
            *) usage_ipfw;;
        esac
    done

    if test -z "$mode"; then
        usage_ipfw
    fi

    echo
    bold "Managing IPFW Rules..."
    case $mode in
        start)
            ipfw_delete $jail "y"
            ipfw_add $jail
            ;;
        stop)
            ipfw_delete $jail                
            ;;
    esac
    bold "... done"
    echo
}

ipfw_add() {
    local jail ipv4 ipv6 rule

    jail=$1

    # support jail variables as well
    load_jail_config $jail

    if test -z $ip; then
        # Getting current jails IP..
        ipv4=`jls -n -j $jail ip4.addr | cut -d= -f2`
    else
        ipv4=$ip
    fi
    
    if test -z "$ipv4"; then
        die "Jail $jail doesn't have an ipv4 address!"
    fi

    if test -z $ip6; then
        ip6=`jls -n -j $jail ip6.addr | cut -d= -f2` # optional, no checks
    else
        ipv6=$ip6
    fi
    
    # Adding rules
    egrep "^[a-z]" $j/etc/$jail/ipfw.conf | while read LINE; do
        rule=$(eval echo "ipfw add $LINE // $jail")
        echo $rule
        $rule
    done
}

ipfw_delete() {
    local jail noout

    jail=$1
    noout=$2

    ipfw show | grep -E "// $jail\$" | while read rule; do [ -z "$2" ] && bold "Deleting rule $rule"; sh -c "ipfw delete $(echo $rule| awk '{print $1}')"; done

}

usage_vnet() {
    echo "$0 vnet <jail> <mode> -b <bridge>
Configure VIMAGE (vnet) networking for a jail. Usually called from
jail.conf. You need to configure the bridge manually in advance.

You need the following in your /etc/rc.conf:
cloned_interfaces=\"bridge0\"
  ifconfig_bridge0=\"inet 172.20.20.1/24 up\"
  ifconfig_bridge0_ipv6=\"2a01:...:1e::1/80 auto_linklocal\"
  ipv6_gateway_enable=\"YES\"

And something like this in your jail.conf:
  billa {
   vnet;
   exec.poststart = \"/jail/bin/jaildk vnet $name start -b jailsw0\";
   exec.prestop   = \"/jail/bin/jaildk vnet $name stop  -b jailsw0\";
  }

Finally, the jail.conf for a vnet jail needs to contain these parameters:
  ip=172.20.20.10/24
  gw=172.20.20.1

and if using v6 v6 address in bridge subet, gw6 is default gw => bridge interface
  ip6=2a01:.....ff
  gw6=2a01:.....1

You'll also need PF nat rules in order to be able to reach the outside
from the jail or vice versa."

    exit
}

jaildk_vnet() {
    #
    # This is no rc.d subcommand, but a standalone command, because it must
    # be executed by jail(8) via exec.created hook.
    local jail mode BRIDGE vnethost vnetjail epairA epairB
    jail=$1
    mode=$2
    shift
    shift

    BRIDGE=''

    OPTIND=1; while getopts "b:i:r:" arg; do
        case $arg in
            b) BRIDGE=${OPTARG};;
            *) usage_vnet;;
        esac
    done

    if test -z "$mode"; then
        usage_vnet
    fi

    die_if_not_exist $jail

    load_jail_config $jail

    if test -z "$ip" -a -z "$gw"; then
        usage_vnet
    fi

    vnethost="ep${jail}.h"
    vnetjail="ep${jail}.j"
    epairA=''
    epairB=''

    case $mode in
        start)
            if ! ifconfig $vnethost > /dev/null 2>&1; then
                # setup epair
                epairA=$(ifconfig epair create)
                epairB="${epairA%?}b"

                ex ifconfig $epairA name $vnethost || true
                ex ifconfig $epairB name $vnetjail || true

                ex ifconfig $vnetjail up
                ex ifconfig $vnethost up
            fi

            if ! ifconfig $BRIDGE | egrep member:.$vnethost > /dev/null 2>&1; then
                # add the host to the bridge
                ex ifconfig $BRIDGE addm $vnethost up || true

                # add the jail to the bridge (gets invisible from host)
                ex ifconfig $vnetjail vnet $jail || true
            fi

            if ! jexec $jail ifconfig $vnetjail inet | grep netmask > /dev/null 2>&1; then
                # configure the jail v4 network stack inside the jail
                ex jexec $jail ifconfig $vnetjail $ip up || true
                ex jexec $jail route add default $gw || true
            fi

            if test -n "$ip6" -a -n "$gw6"; then
                if ! jexec $jail ifconfig $vnetjail inet6 | grep -v fe80 | grep prefixlen > /dev/null 2>&1; then
                    # configure the jail v6 network stack inside the jail
                    ex jexec $jail ifconfig $vnetjail inet6 $ip6 || true
                    ex jexec $jail ifconfig $vnetjail inet6 -ifdisabled accept_rtadv auto_linklocal|| true
                    ex jexec $jail route -6 add default $gw6 || true
                fi
            fi
            ;;
        stop)
            # remove vnet from the jail
            ifconfig $vnetjail -vnet $jail || true

            # remove interfaces (removes jail interface as well, since this is an epair)
            ifconfig $vnethost destroy || true
            ;;
        *)
            usage_vnet;;
    esac    
}

usage_prune() {
    echo "$0 prune [-b | -a | -j]
List unused directories. Important: ALL jails must be running while
executing this command! Options:
-b         list active and unused bases
-a         list active and unused appls
-j <jail>  list version and unused jail specific directories for <jail>
-u         only list unused dirs

Use the option -u to omit active dirs and '|xargs rm -rf' to actually
delete directories. Be sure to have backups available!
"
}

jaildk_prune() {
    local BASE APPL JAIL UNUSED

    OPTIND=1; while getopts "baj:u" arg; do
        case $arg in
            b) BASE=1;;
            a) APPL=1;;
            j) JAIL=${OPTARG};;
            u) UNUSED=1;;
            *) usage_bootstrap;;
        esac
    done

    dirs="/tmp/jaildk-$$-dirs"

    if test -n "$BASE"; then
        (
            mount | grep /base/ | cut -d' ' -f1
            ls -1d /jail/base/*
        ) > $dirs

        if test -z "$UNUSED"; then
            bold "Active BASE mounts:" > /dev/stderr
            cat $dirs | sort -V | uniq -c | grep -v " 1" | awk '{print $2}'
            echo
        fi

        bold "Unused BASE mounts (be aware of build mounts!):" > /dev/stderr
        cat $dirs | sort -V | uniq -c | grep " 1" | awk '{print $2}'

        rm -f $dirs

    elif test -n "$APPL"; then
        (
            mount | grep /appl/ | cut -d' ' -f1
            ls -1d /jail/appl/*
        ) > $dirs

        if test -z "$UNUSED"; then
            bold "Active APPL mounts:" > /dev/stderr
            cat $dirs | sort -V | uniq -c | grep -v " 1" | awk '{print $2}'
            echo
        fi

        bold "Unused APPL mounts:" > /dev/stderr
        cat $dirs | sort -V | uniq -c | grep " 1" | awk '{print $2}'

        rm -f $dirs

    elif test -n "$JAIL"; then
        die_if_not_exist $JAIL
        load_jail_config $JAIL

        if test -z "$UNUSED"; then
            bold "Current Active jail version for jail $JAIL:" > /dev/stderr
            echo $version; echo
        fi

        bold "Unused jail specific mounts for jail $JAIL:" > /dev/stderr
        ls -1d $j/etc/$JAIL/*[0-1]* $j/log/$JAIL-*[0-1]* $j/home/$JAIL/*[0-1]* | grep -v $version | sort -V
    fi
}

usage_bootstrap() {
    echo "$0 bootstrap <jail> [-b <base>] [-v <version>] [-p <port,...>] [-a <appl>] [-i <ip,..>]
Create, build and install a new jail with name <jail>. Options:
-b <base>        Use <base> as base, create if not existent.
-v <version>     Assign <version> to new jail, otherwise use YYYYMMDD.
-p <port,...>    Install specified ports into jail.
-a <appl>        Use <appl>-<version> as /usr/local/, create if not existent.
-i <ip,..>       Configure the jail in /etc/jail.conf with ip addresses <ip,...>
"
    exit 1
}

jaildk_bootstrap() {
    # combines base, create and build functions into a oneshot command
    # to create a new jail
    local jail BASE VERSION APPL PORTS IP loadbase RUN subdir port
    jail=$1
    shift
    
    BASE=''
    VERSION=''
    APPL=''
    PORTS=''
    IP=''

    OPTIND=1; while getopts "i:b:v:p:a:" arg; do
        case $arg in
            b) BASE=${OPTARG};;
            v) VERSION=${OPTARG};;
            p) PORTS=${OPTARG};;
            a) APPL=${OPTARG};;
            i) IP=${OPTARG};;
            *) usage_bootstrap;;
        esac
    done

    if test -z "$jail" -o "$jail" = "-h"; then
        usage_bootstrap
    fi

    # if no base specified, use last  existing one or create one if no
    # base exists at all
    if test -z "$BASE"; then
        lastbase=$(ls -1tr $j/base/ | grep -v build | tail -1)
        if test -n "$lastbase"; then
            BASE=$lastbase
        else
            BASE=$(uname -r)
            $(jaildk_base -b $BASE)
        fi
    else
        if ! test -d "$j/base/$BASE"; then
            # base specified but doesnt exist, so create
            $(jaildk_base -b $BASE)
        fi
    fi

    # version no specified
    if test -z "$VERSION"; then
        VERSION=$(date +%Y%m%d)
    fi

    # creation
    $(jaildk_create $jail)
    
    # appl specified, do NOT clone but start empty IF it doesnt' exist yet
    if test -n "$APPL"; then
        if ! test -d "$j/appl/$APPL-$VERSION"; then
            for subdir in db/ports etc; do
                ex mkdir -p $j/$APPL-$VERSION/$subdir
            done
        fi

        # also fix mount.conf
        echo "Setting appl to $APPL"
        sed -iE "s|appl/.+-\$version|appl/$APPL-\$version|" $j/etc/$jail/mount.conf
    fi

    # mount build
    if test -n "$PORTS"; then
        jaildk_build $jail -m start -b $BASE -v $VERSION

        echo "Installing ports"
        for port in `echo "$PORTS" | sed 's/,/ /g'`; do
            chroot $j/build/$jail pkg install $port
        done
    fi

    # install
    jaildk_install $jail -m start

    # run
    RUN=''
    if egrep -q "^${jail} " /etc/jail.conf; then
        RUN=1
    else
        if test -n "$IP"; then
            echo "Adding $jail with ip addrs $IP to /etc/jail.conf"
            (echo
             echo "$jail {"
             for addr in `echo "$IP" | sed 's/,/ /g'`; do
                 if echo "$addr" | egrep -q :; then
                     echo "  ip6.addr = \"$addr\";"
                 else
                     echo "  ip4.addr = \"$addr\";"
                 fi
             done
             echo "}"
            ) >> /etc/jail.conf
            RUN=1
        fi
    fi

    if test -n "$RUN"; then
        service jail start $jail
    fi
}

mustberoot() {
    if test "$( id -u )" -ne 0; then
        echo "Must run as root!" >&2
        exit 1
    fi
}

sanitycheck() {
    # check if certain programs are installed
    for program in cpdup; do
        if ! command -v $program 2>&1 >/dev/null; then
            echo "$program must be installed!" >&2
            exit1
        fi
    done
}

##########################
#
# main()

# will be modified during installation
JAILDIR=/jail

# install modules
RCSCRIPTS_START="rc_mount rc_ports rc_mtree rc_pf"
RCSCRIPTS_STOP="rc_pf rc_mount rc_ports"
RW_RCSCRIPTS_START="rc_mount rc_ports rc_mtree"
RW_RCSCRIPTS_STOP="rc_mount rc_ports"

# globals
j=$JAILDIR
rcdir=$j/bin

runner=$1
shift

if test -z "$runner"; then
    usage_jaildk
fi

sanitycheck

case $runner in
    start|stop|restart)
        # running jails
        mustberoot
        jaildk_jail $runner $*
        ;;
    status)
        # same, w/o root
        jaildk_jail status $*
        ;;
    login)
        # login into jail as non root user allowed
        # eventually calls sudo
        jaildk_login $*
        ;;
    completion)
        echo "$JAILDK_COMPLETION"
        ;;
    _get_rc_scripts)
        get_rc_scripts $*
        ;;
    *)
        # every other management command, if it exists
        if type "jaildk_$runner" 2>&1 > /dev/null; then
            mustberoot
            jaildk_$runner $*
        else
            usage_jaildk $*
        fi
        ;;
esac


