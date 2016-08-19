#!/bin/sh

# Create all the symlinks to /bin/busybox
/bin/busybox --install -s

# Mount things needed by this script
/bin/mount -t proc proc /proc
/bin/mount -t sysfs sysfs /sys
/bin/mount -t devpts /dev/pts /dev/pts

# Disable kernel messages from popping onto the screen
# echo 0 > /proc/sys/kernel/printk

# Clear the screen
# clear

# Create device nodes
/bin/mknod /dev/null c 1 3
/bin/mknod /dev/tty c 5 0
/sbin/mdev -s

# Function for parsing command line options with "=" in them
# get_opt("init=/sbin/init") will return "/sbin/init"
#function get_opt() {
#    echo "$@" | /usr/bin/cut -d "=" -f 2
#}

# Defaults
#init="/sbin/init"
#root="/dev/hda1"

## Process command line options
#for i in $(cat /proc/cmdline); do
#    case $i in
#        root\=*)
#            root=$(get_opt $i)
#            ;;
#        init\=*)
#            init=$(get_opt $i)
#            ;;
#    esac
#done
#
# Mount the root device
# mount "${root}" /newroot

#Check if $init exists and is executable
# if [[ -x "/newroot/${init}" ]] ; then
#     #Unmount all other mounts so that the ram used by
#     #the initramfs can be cleared after switch_root
#     umount /sys /proc
#     
#     #Switch to the new root and execute init
#     exec switch_root /newroot "${init}"
# fi

modprobe e1000
ifconfig eth0 192.168.0.107
route add default gw 192.168.0.1
# ip route add default via 192.168.0.1

echo "root:6OBjvdEuHx43.:0:0:Linux,,,:/root:/bin/sh" > /etc/passwd
echo "root:x:0:root" > /etc/group

dropbear
mkdir -p /var/log
syslogd
echo 7 7 7 7 > /proc/sys/kernel/printk

# echo "download get initrd.img"
# /bin/gget -o /root/initrd -url https://raw.githubusercontent.com/stephen-soltesz/pxe-test/master/initrd.img

# echo "starting kexec"
# sleep 1
# /usr/sbin/kexec -d --force --initrd=/root/initrd --command-line="acpi=off nolapic noapic nosmp nr_cpus=1 maxcpus=0" /root/centos_vmlinuz

echo "Dropping to a shell with job control. -- 3"
setsid sh -c 'exec sh </dev/tty1 >/dev/tty1 2>&1'

echo "Shell without job control."
exec /bin/sh
