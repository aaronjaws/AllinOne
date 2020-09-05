#!/usr/bin/env bash

sh_ver="1.0.0"

# - ESSENTIAL
install_env() {
	# Sources Update
	cd /etc/apt/
	wget --no-check-certificate https://config.nliu.work/sources_d10.list
	mv sources_d10.list sources.list
	# Install Env
	apt update
	cd ~
	apt install -y curl wget nano net-tools htop nload iperf3 screen ntpdate tzdata dnsutils mtr git rng-tools unzip zip tuned
	# Setup rng-tools and tuned
	echo "HRNGDEVICE=/dev/urandom" >>/etc/default/rng-tools
	systemctl enable rng-tools && systemctl restart rng-tools
	systemctl enable tuned
	tuned-adm profile virtual-guest
	rm -rf /etc/localtime && ln -s /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
	# SSH Key(s) Installation
	curl https://storage.acrtis.app/authorized_keys --create-dirs -o /root/.ssh/authorized_keys
	# Kernel Optimization
	rm -f /etc/security/limits.conf
	wget --no-check-certificate https://storage.acrtis.app/limits
	wget --no-check-certificate https://storage.acrtis.app/sysctl
	cat limits >/etc/security/limits.conf
	cat sysctl >>/etc/sysctl.conf
	rm -rf limits sysctl
}

# - IPTABLES
check_iptables() {
	iptables_exist=$(iptables -V)
	[[ ${iptables_exist} = "" ]] && echo -e "iptables not found, check if it is correctly installed." && exit 1
}

Set_forwarding_port() {
	read -e -p "Type in the ports that you wanna forward to:" forwarding_port
	[[ -z "${forwarding_port}" ]] && echo "Enter something when asking" && exit 1
	echo && echo -e " forwarding ports: ${forwarding_port}" && echo
}
Set_forwarding_ip() {
	read -e -p "type in the address you wanna forward to:" forwarding_ip
	[[ -z "${forwarding_ip}" ]] && echo "Enter something when asking" && exit 1
	echo && echo -e "forwarding IP: ${forwarding_ip}" && echo
}
Set_local_ip() {
	read -e -p "Type in your local IP address:" local_ip
	[[ -z "${local_ip}" ]] && echo "Enter something when asking" && exit 1
	echo && echo -e "local IP: ${local_ip}" && echo
}

Clear_iptables() {
	iptables -P INPUT ACCEPT
	iptables -P FORWARD ACCEPT
	iptables -P OUTPUT ACCEPT
	iptables -t nat -F
	iptables -t mangle -F
	iptables -F
	iptables -X
	iptables-save >/root/rules
}
Add_iptables() {
	Set_forwarding_port
	Set_forwarding_ip
	Set_local_ip
	iptables -t nat -A PREROUTING -p tcp --dport ${forwarding_port} -j DNAT --to-destination ${forwarding_ip}
	iptables -t nat -A PREROUTING -p udp --dport ${forwarding_port} -j DNAT --to-destination ${forwarding_ip}
	iptables -t nat -A POSTROUTING -p tcp -d ${forwarding_ip} --dport ${forwarding_port} -j SNAT --to-source ${local_ip}
	iptables -t nat -A POSTROUTING -p udp -d ${forwarding_ip} --dport ${forwarding_port} -j SNAT --to-source ${local_ip}
	iptables-save >/root/rules
	echo '#!/bin/sh' >>/etc/rc.local
	echo 'iptables-restore < /root/rules' >>/etc/rc.local
	chmod +x /etc/rc.local
}
View_forwarding() {
	iptables -nvL -t nat
}

# - SHIT INSTALLING
kernel_upgrade() {
	apt install -t buster-backports linux-image-cloud-amd64 linux-headers-cloud-amd64 -y
}
install_haproxy() {
	# Install haproxy
	curl https://haproxy.debian.net/bernat.debian.org.gpg | apt-key add -
	echo deb https://haproxy.debian.net stretch-backports-2.1 main | tee /etc/apt/sources.list.d/haproxy.list
	apt update --allow-insecure-repositories
	apt -y install haproxy=2.1.\*
	wget -O /etc/haproxy/haproxy.cfg https://storage.acrtis.app/haproxy
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

# Launchpad
echo && echo -e "
-- Relay.sh [v${sh_ver}] --

- ESSENTIAL

0. first time setup
————————————
- IPTABLES

1. setup relay
2. clear all shit
3. view NAT rules
————————————
- SHIT INSTALLING

4. kernel upgrade
5. install haproxy 2.1
6. install docker
7. install speedtest
" && echo
read -e -p " Enter (0-7):" num
case "${num}" in
0)
	install_env
	break
	;;
1)
	check_iptables
	Add_iptables
	break
	;;
2)
	check_iptables
	Clear_iptables
	break
	;;
3)
	check_iptables
	View_forwarding
	break
	;;
4)
	kernel_upgrade
	break
	;;
5)
	install_haproxy
	break
	;;
6)
	install_docker
	break
	;;
7)
	install_speedtest
	break
	;;
*)
	echo "enter ONLY from 0-7 bruh"
	;;
esac
