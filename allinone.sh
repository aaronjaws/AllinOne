#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

current_build="v20210331"

install_dependencies(){
    # brook, joker and jinbe latest version
    joker_version=$(wget -qO- https://api.github.com/repos/txthinking/joker/releases| grep "tag_name"| head -n 1| awk -F ":" '{print $2}'| sed 's/\"//g;s/,//g;s/ //g')
    brook_version=$(wget -qO- https://api.github.com/repos/txthinking/brook/releases| grep "tag_name"| head -n 1| awk -F ":" '{print $2}'| sed 's/\"//g;s/,//g;s/ //g')
    jinbe_version=$(wget -qO- https://api.github.com/repos/txthinking/jinbe/releases| grep "tag_name"| head -n 1| awk -F ":" '{print $2}'| sed 's/\"//g;s/,//g;s/ //g')
    # update sources to prevent upgrade failure
    curl -L https://config.nliu.work/sources_d10.list -o /etc/apt/sources.list
    # install dependencies
    apt update
    apt install -y curl wget nano net-tools htop nload iperf3 screen ntpdate tzdata dnsutils mtr git rng-tools unzip zip tuned tuned-utils tuned-utils-systemtap bash-completion
    curl -L https://github.com/txthinking/joker/releases/download/${joker_version}/joker_linux_amd64 -o /usr/local/bin/joker
    curl -L https://github.com/txthinking/brook/releases/download/${brook_version}/brook_linux_amd64 -o /usr/local/bin/brook
    curl -L https://github.com/txthinking/jinbe/releases/download/${jinbe_version}/jinbe_linux_amd64 -o /usr/local/bin/jinbe
    # setup rng-tools and tuned
    echo "HRNGDEVICE=/dev/urandom" >> /etc/default/rng-tools
    tuned-adm profile throughput-performance
    systemctl enbale --now tuned
    systemctl enable rng-tools && systemctl restart rng-tools
    rm -rf /etc/localtime && ln -s /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    # ssh key installation
    curl https://vault.vt.sb/linux/authorized_keys --create-dirs -o /root/.ssh/authorized_keys
    # kernel optimization
    rm -f /etc/security/limits.conf
    wget --no-check-certificate https://vault.vt.sb/linux/limits
    wget --no-check-certificate https://vault.vt.sb/linux/sysctl
    cat limits > /etc/security/limits.conf
    cat sysctl >> /etc/sysctl.conf
    rm -rf limits sysctl
    iptables-save > /root/rules
    # startup scripts
    echo '#!/bin/sh' > /etc/rc.local
    #echo 'default_route=`ip route | grep "^default" | head -1`' >> /etc/rc.local
    #echo 'ip route change $default_route initcwnd 15 initrwnd 15' >> /etc/rc.local
    echo 'iptables-restore < /root/rules' >> /etc/rc.local
    chmod +x /etc/rc.local && chmod +x /usr/local/bin/joker && chmod +x /usr/local/bin/brook && chmod +x /usr/local/bin/jinbe
    clear
}

kernel_upgrade() {
    read -p "Do you wanna update your source? [y/n]:" sources_update
        case "${sources_update}" in
        n)
            apt install -t buster-backports linux-image-cloud-amd64 linux-headers-cloud-amd64 -y
            ;;
        y)
            curl -L https://config.nliu.work/sources_d10.list -o /etc/apt/sources.list
            apt update
            apt install -t buster-backports linux-image-cloud-amd64 linux-headers-cloud-amd64 -y
            ;;
        esac
}

# start relay with brook
brook_src_port(){
    read -e -p "what is the port that your local server listen to ? :" brook_src_port
    [[ -z "${brook_src_port}" ]] && echo "Enter something when asking" && exit 1
    echo && echo -e " src port: ${brook_src_port}" && echo
}

brook_dst_ip(){
    read -e -p "what is the IPv4 address that you wanna forward to ? :" brook_dst_ip
    [[ -z "${brook_dst_ip}" ]] && echo "Enter something when asking" && exit 1
    echo && echo -e " dst IP: ${brook_dst_ip}" && echo
}

brook_dst_port(){
    read -e -p "what is the port that you wanna forward to ? :" brook_dst_port
    [[ -z "${brook_dst_port}" ]] && echo "Enter something when asking" && exit 1
    echo && echo -e " dst port: ${brook_dst_port}" && echo
}

start_brook_relay(){
    jinbe joker brook relay --from :${brook_src_port} --to ${brook_dst_ip}:${brook_dst_port}
}
# end relay with brook

# start relay with iptables
iptables_dst_ports() {
    read -e -p "Type in the ports that you wanna forward to:" iptables_dst_ports
    [[ -z "${iptables_dst_ports}" ]] && echo "Enter something when asking" && exit 1
    echo && echo -e " forwarding ports: ${iptables_dst_ports}" && echo
}

iptables_dst_ip() {
    read -e -p "type in the address you wanna forward to:" iptables_dst_ip
    [[ -z "${iptables_dst_ip}" ]] && echo "Enter something when asking" && exit 1
    echo && echo -e "forwarding IP: ${iptables_dst_ip}" && echo
}

iptables_src_ip() {
    read -e -p "Type in your local IP address:" iptables_src_ip
    [[ -z "${iptables_src_ip}" ]] && echo "Enter something when asking" && exit 1
    echo && echo -e "local IP: ${iptables_src_ip}" && echo
}

start_iptables() {
    iptables_dst_ports
    iptables_dst_ip
    iptables_src_ip
    iptables -t nat -A PREROUTING -p tcp --dport ${iptables_dst_ports} -j DNAT --to-destination ${iptables_dst_ip}
    iptables -t nat -A PREROUTING -p udp --dport ${iptables_dst_ports} -j DNAT --to-destination ${iptables_dst_ip}
    iptables -t nat -A POSTROUTING -p tcp -d ${iptables_dst_ip} --dport ${iptables_dst_ports} -j SNAT --to-source ${iptables_src_ip}
    iptables -t nat -A POSTROUTING -p udp -d ${iptables_dst_ip} --dport ${iptables_dst_ports} -j SNAT --to-source ${iptables_src_ip}
    iptables-save > /root/rules
}
# end relay with iptables

clear_iptables_rules() {
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -t nat -F
    iptables -t mangle -F
    iptables -F
    iptables -X
    iptables-save > /root/rules
}

build_fullcone_modules() {
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

add_fullcone() {
    read -e -p "Type in the ethernet name that you are using:" ethernet_name
    [[ -z "${ethernet_name}" ]] && echo "Enter something when asking" && exit 1
    iptables -t nat -A POSTROUTING -o ${ethernet_name} -j FULLCONENAT
    iptables -t nat -A PREROUTING -i ${ethernet_name} -j FULLCONENAT
    iptables-save > /root/rules
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

clear
echo ""
echo "Allinone ${current_build}"
echo "+--------------------------+"
echo "|a. install dependencies   |"
echo "|b. kernel upgrade         |"
echo "|c. fullcone setup         |"
echo "|d. add fullcone rules     |"
echo "|e. relay with brook       |"
echo "|f. relay with iptables    |"
echo "|g. install haproxy 2.1    |"
echo "|h. install docker         |"
echo "|i. install speedtest      |"
echo "|j. DELTE ALL RULES        |"
echo "+--------------------------+"

read -p "Enter (a-j):" num
case "${num}" in
    a)
        install_dependencies
        ;;
    b)
        kernel_upgrade
        ;;
    c)
        build_fullcone_modules
        add_fullcone
        ;;
    d)
        add_fullcone
        ;;
    e)
        brook_src_port
        brook_dst_ip
        brook_dst_port
        start_brook_relay
        ;;
    f)
        iptables_dst_ports
        iptables_dst_ip
        iptables_src_ip
        start_iptables
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
        clear_iptables_rules
        ;;
    esac