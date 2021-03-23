#!/usr/bin/env bash

install_env() {
    # Sources Update
    cd /etc/apt/
    wget --no-check-certificate https://config.nliu.work/sources_d10.list
    mv sources_d10.list sources.list
    # Install Env
    apt update
    cd ~
    apt install -y curl wget nano net-tools htop nload iperf3 screen ntpdate tzdata dnsutils mtr git rng-tools unzip zip tuned tuned-utils tuned-utils-systemtap
    # Setup rng-tools and tuned
    echo "HRNGDEVICE=/dev/urandom" >>/etc/default/rng-tools
    tuned-adm profile throughput-performance
    systemctl enbale --now tuned
    systemctl enable rng-tools && systemctl restart rng-tools
    rm -rf /etc/localtime && ln -s /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    # SSH Key(s) Installation
    curl https://vault.vt.sb/linux/authorized_keys --create-dirs -o /root/.ssh/authorized_keys
    # Kernel Optimization
    rm -f /etc/security/limits.conf
    wget --no-check-certificate https://vault.vt.sb/linux/limits
    wget --no-check-certificate https://vault.vt.sb/linux/sysctl
    cat limits >/etc/security/limits.conf
    cat sysctl >>/etc/sysctl.conf
    rm -rf limits sysctl
    iptables-save >/root/rules
    echo '#!/bin/sh' >/etc/rc.local
    echo 'default_route=`ip route | grep "^default" | head -1`' >>/etc/rc.local
    echo 'ip route change $default_route initcwnd 20 initrwnd 20' >>/etc/rc.local
    echo 'iptables-restore < /root/rules' >>/etc/rc.local
    chmod +x /etc/rc.local
}

check_iptables() {
    iptables_exist=$(iptables -V)
    [[ ${iptables_exist} = "" ]] && echo -e "iptables not found, check if it is correctly installed." && exit 1
}
forwarding_port() {
    read -e -p "Type in the ports that you wanna forward to:" forwarding_port
    [[ -z "${forwarding_port}" ]] && echo "Enter something when asking" && exit 1
    echo && echo -e " forwarding ports: ${forwarding_port}" && echo
}
forwarding_ip() {
    read -e -p "type in the address you wanna forward to:" forwarding_ip
    [[ -z "${forwarding_ip}" ]] && echo "Enter something when asking" && exit 1
    echo && echo -e "forwarding IP: ${forwarding_ip}" && echo
}
local_ip() {
    read -e -p "Type in your local IP address:" local_ip
    [[ -z "${local_ip}" ]] && echo "Enter something when asking" && exit 1
    echo && echo -e "local IP: ${local_ip}" && echo
}
clear_iptables() {
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -t nat -F
    iptables -t mangle -F
    iptables -F
    iptables -X
    iptables-save >/root/rules
}
forwarding_iptables() {
    forwarding_port
    forwarding_ip
    local_ip
    iptables -t nat -A PREROUTING -p tcp --dport ${forwarding_port} -j DNAT --to-destination ${forwarding_ip}
    iptables -t nat -A PREROUTING -p udp --dport ${forwarding_port} -j DNAT --to-destination ${forwarding_ip}
    iptables -t nat -A POSTROUTING -p tcp -d ${forwarding_ip} --dport ${forwarding_port} -j SNAT --to-source ${local_ip}
    iptables -t nat -A POSTROUTING -p udp -d ${forwarding_ip} --dport ${forwarding_port} -j SNAT --to-source ${local_ip}
    iptables-save >/root/rules
}
check_nat_rules() {
    iptables -nvL -t nat
}

install_fullcone() {
    # Install build needed packages
    apt install build-essential autoconf autogen libtool pkg-config libgmp3-dev bison flex libreadline-dev git -y
    # Download sources
    cd /root/
    git clone git://git.netfilter.org/libmnl
    git clone git://git.netfilter.org/libnftnl.git
    git clone git://git.netfilter.org/iptables.git
    git clone https://github.com/Chion82/netfilter-full-cone-nat.git
    PKG_CONFIG_PATH=/usr/local/lib/pkgconfig
    export PKG_CONFIG_PATH
    # Make libmnl
    cd /root/libmnl
    sh autogen.sh
    ./configure
    make
    make install
    # Make libnftn
    cd /root/libnftnl
    sh autogen.sh
    ./configure
    make
    make install
    # Make modules
    cd ~/netfilter-full-cone-nat
    make
    modprobe nf_nat
    insmod xt_FULLCONENAT.ko
    # Make iptables
    cp ~/netfilter-full-cone-nat/libipt_FULLCONENAT.c ~/iptables/extensions/
    cd ~/iptables
    ln -sfv /usr/sbin/xtables-multi /usr/bin/iptables-xml
    ./autogen.sh
    ./configure
    make
    make install
    # Replace iptables
    rm -rf /sbin/iptables
    rm -rf /sbin/iptables-restore
    rm -rf /sbin/iptables-save
    cd /usr/local/sbin
    cp /usr/local/sbin/iptables /sbin/
    cp /usr/local/sbin/iptables-restore /sbin/
    cp /usr/local/sbin/iptables-save /sbin/
    # Make FullCone modules loaded on boot
    cd /root/
    kernel=$(uname -r)
    cp ~/netfilter-full-cone-nat/xt_FULLCONENAT.ko /lib/modules/$kernel/
    depmod
    echo 'modprobe xt_FULLCONENAT' >>/etc/rc.local
    rm -rf /root/lib* /root/netfilter-full-cone-nat /root/iptables
}

kernel_upgrade() {
    read -p "Do you wanna update your source? 0:No 1:Yes:" sources_update
    if [[ ! ${sources_update} =~ ^[0-1]$ ]]; then
        echo "enter ONLY from 0-1 bruh"
    else
        case "${sources_update}" in
        0)
            apt install -t buster-backports linux-image-cloud-amd64 linux-headers-cloud-amd64 -y
            ;;
        1)
            wget config.nliu.work/sources_d10.list
            cat sources_d10.list >/etc/apt/sources.list
            apt update
            rm -rf sources_d10.list
            apt install -t buster-backports linux-image-cloud-amd64 linux-headers-cloud-amd64 -y
            ;;
        esac
    fi
}
install_haproxy() {
    # Install haproxy
    curl https://haproxy.debian.net/bernat.debian.org.gpg | apt-key add -
    echo deb https://haproxy.debian.net stretch-backports-2.1 main | tee /etc/apt/sources.list.d/haproxy.list
    apt update --allow-insecure-repositories
    apt -y install haproxy=2.1.\*
    wget -O /etc/haproxy/haproxy.cfg https://vault.vt.sb/config/haproxy
}
install_docker() {
    # Docker Installation
    curl -fsSL get.docker.com | bash
    #curl -sSL https://get.daocloud.io/docker | sh
}
install_speedtest() {
    apt-get install gnupg1 apt-transport-https dirmngr -y
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 379CE192D401AB61
    echo "deb https://ookla.bintray.com/debian stretch main" | tee /etc/apt/sources.list.d/speedtest.list
    apt update --allow-insecure-repositories
    apt -y install speedtest
}
add_fullcone() {
    read -e -p "Type in the ethernet name that you are using:" ethernet_name
    [[ -z "${ethernet_name}" ]] && echo "Enter something when asking" && exit 1
    iptables -t nat -A POSTROUTING -o ${ethernet_name} -j FULLCONENAT
    iptables -t nat -A PREROUTING -i ${ethernet_name} -j FULLCONENAT
    iptables-save >/root/rules
}

current_build="v2.0.0"

clear
echo ""
echo "Allinone v ${current_build}"
echo "+--------------------------+"
echo "|a. first time setup       |"
echo "|b. iptables relay         |"
echo "|c. fullcone setup         |"
echo "|d. clear all iptables     |"
echo "|e. check nat chain        |"
echo "|f. kernel upgrade         |"
echo "|g. install haproxy 2.1    |"
echo "|h. install docker         |"
echo "|i. install speedtest      |"
echo "|j. install fullcone rules |"
echo "+--------------------------+"

read -p "Enter (a-j):" num
if [[ ! ${num} =~ ^[a-j]$ ]]; then
	echo "enter ONLY from a-j bruh"
else
	case "${num}" in
	a)
		install_env
		;;
	b)
		check_iptables
		forwarding_iptables
		;;
	c)
		install_fullcone
		add_fullcone
		;;
	d)
		check_iptables
		clear_iptables
		;;
	e)
		check_iptables
		check_nat_rules
		;;
	f)
		kernel_upgrade
		;;
	g)
		install_haproxy
		;;
	h)
		install_docker
		;;
	i)
		install_speedtest
		;;
	j)
		add_fullcone
		;;
	esac
fi