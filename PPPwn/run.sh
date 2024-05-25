#!/bin/bash

ifconfig eth0 promisc

VERSION=2.0

if [ -f /boot/firmware/PPPwn/config.sh ]; then
	source /boot/firmware/PPPwn/config.sh
fi

if [ -z "$INTERFACE" ]; then INTERFACE="eth0"; fi
if [ -z "$FIRMWAREVERSION" ]; then FIRMWAREVERSION="11.00"; fi
if [ -z "$SHUTDOWN" ]; then SHUTDOWN=true; fi
if [ -z "$PPPOECONN" ]; then PPPOECONN=false; fi
if [ -z "$PPDBG" ]; then PPDBG=false; fi
if [ -z "$TIMEOUT" ]; then TIMEOUT="15m"; fi

CPPBIN="pppwn11"

echo -e "\n\n\033[36m _____  _____  _____
|  __ \\|  __ \\|  __ \\
| |__) | |__) | |__) |_      ___ __
|  ___/|  ___/|  ___/\\ \\ /\\ / / '_ \\
| |    | |    | |     \\ V  V /| | | |
|_|    |_|    |_|      \\_/\\_/ |_| |_|\033[0m
\n\033[33mhttps://github.com/Mintneko/WKY-Pwn\033[0m\n" | sudo tee /dev/tty1

echo -e "\033[92mVersion $VERSION \033[0m" | sudo tee /dev/tty1

sudo systemctl stop pppoe >/dev/null 2>&1 &

sudo ip link set "$INTERFACE" up
sudo ip link set "$INTERFACE" promisc on

echo -e "\n\033[36m$WKYTYP\033[92m\nFirmware:\033[93m $FIRMWAREVERSION\033[92m\nInterface:\033[93m $INTERFACE\033[0m" | sudo tee /dev/tty1
echo -e "\033[92mPPPwn:\033[93m C++ $CPPBIN \033[0m" | sudo tee /dev/tty1

if [ "$PPPOECONN" = true ]; then
	echo -e "\033[92mInternet Access:\033[93m Enabled\033[0m" | sudo tee /dev/tty1
else
	echo -e "\033[92mInternet Access:\033[93m Disabled\033[0m" | sudo tee /dev/tty1
fi

if [ -f /boot/firmware/PPPwn/pwn.log ]; then
	sudo rm -f /boot/firmware/PPPwn/pwn.log
fi

echo -e "\033[31mWaiting for $INTERFACE link\033[0m" | sudo tee /dev/tty1
while [[ ! $(ethtool "$INTERFACE") == *"Link detected: yes"* ]]; do
	sleep 1
done
echo -e "\033[32mLink found\033[0m\n" | sudo tee /dev/tty1

WKYIP=$(hostname -I) || true
if [ "$WKYIP" ]; then
	echo -e "\n\033[92mIP: \033[93m $WKYIP\033[0m" | sudo tee /dev/tty1
fi

echo -e "\n\033[95mReady for console connection\033[0m\n" | sudo tee /dev/tty1
while true; do
	if [ -f /boot/firmware/PPPwn/config.sh ]; then
		if grep -Fxq "PPDBG=true" /boot/firmware/PPPwn/config.sh; then
			logfile=/boot/firmware/PPPwn/pwn.log
		else
			logfile=/dev/null
		fi
	fi

	if [[ $FIRMWAREVERSION == "10.00" ]]; then
		STAGEVER="10.00"
	elif [[ $FIRMWAREVERSION == "10.01" ]]; then
		STAGEVER="10.01"
	elif [[ $FIRMWAREVERSION == "9.00" ]]; then
		STAGEVER="9.00"
	else
		STAGEVER="11.00"
	fi

	if timeout "$TIMEOUT" sudo /boot/firmware/PPPwn/$CPPBIN --interface "$INTERFACE" --fw "${STAGEVER//./}" --stage1 "/boot/firmware/PPPwn/stage1_$STAGEVER.bin" --stage2 "/boot/firmware/PPPwn/stage2_$STAGEVER.bin" -t 20 -a | sudo tee /dev/tty1 | sudo tee -a "$logfile"; then
		echo -e "\033[32m\nConsole PPPwned! \033[0m\n" | sudo tee /dev/tty1
		if [ "$PPPOECONN" = true ]; then
			sudo sysctl net.ipv4.ip_forward=1
			sudo sysctl net.ipv4.conf.all.route_localnet=1

			# 清除现有的nat表规则
			sudo iptables -t nat -F

			# 取消注释以允许ps4访问网络
			#sudo iptables -t nat -I PREROUTING -s 192.168.2.0/24 -p udp -m udp --dport 53 -j DNAT --to-destination 127.0.0.1:5353
			#sudo iptables -t nat -A POSTROUTING -s 192.168.2.0/24 ! -d 192.168.2.0/24 -j MASQUERADE

			# 确保22端口的流量不被重定向，如果玩客云有其它的端口需要使用，可以在此添加
			sudo iptables -t nat -A PREROUTING -p tcp --dport 22 -j ACCEPT
			# 将所有TCP流量（除了22端口）重定向到内部IP 192.168.2.2
			sudo iptables -t nat -A PREROUTING -p tcp -j DNAT --to-destination 192.168.2.2
			# 将所有UDP流量重定向到内部IP 192.168.2.2
			sudo iptables -t nat -A PREROUTING -p udp -j DNAT --to-destination 192.168.2.2
			# 在POSTROUTING链中使用MASQUERADE，适用于动态IP环境
			sudo iptables -t nat -A POSTROUTING -j MASQUERADE
			# 保存iptables规则（不同系统命令不同）
			#sudo iptables-save >/etc/iptables/rules.v4 # 对于Debian/Ubuntu
			echo -e "\n\n\033[93m\nPPPoE Enabled \033[0m\n" | sudo tee /dev/tty1 | sudo tee -a "$logfile"
			sudo pppoe-server -I "$INTERFACE" -T 60 -N 1 -C PS4 -S PS4 -L 192.168.2.1 -R 192.168.2.2 -F
		else
			if [ "$SHUTDOWN" = true ]; then
				sleep 5
				sudo poweroff
			fi
		fi
		exit 0
	else
		echo -e "\033[31m\nFailed retrying...\033[0m\n" | sudo tee /dev/tty1
	fi

	sleep 1
done
