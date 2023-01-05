#!/bin/bash
clear

#INPUT DISK MANAGER
input_disk_manager() {

	#connect_wifi
	select_disk_drive
	partisi_table
}

#INPUT DATA INSTALLER 
input_data_intaller() {

	input_hostname
	input_root_password
	input_timezone
	input_keymap
	input_create_user
	input_pkg_tools
	input_desktop
        input_grub
}

#SETUP ARCH BASE
setup() {
	timedatectl set-ntp true
	#manage disk
	input_disk_manager

	#input data
	input_data_intaller

	#confirm before exec data
	periksa_data

	#formatting 
	format_partisi &>/dev/null

    #Installing base system

    install_base
    
    #Setting fstab
    set_fstab 

    #Chrooting into installed system to continue setup
	set_chroot

	#message if error 
    error_message
}

#CONFIGURE ARCH
configure() {

    #Setting hostname
    set_hostname 

    #Setting timezone
    set_timezone

    #Setting console keymap
    set_keymap

    #Setting root password
    set_root_password 

    #Creating initial user
    create_user
    
    #Installing additional packages
    install_pkg_tools
    
    #configuring grub
    set_grub
    
    #Configuring sudo
    set_sudoers
    
    #Desktop kde minimal
    set_kde_lite
    
    #Clearing package tarballs
    clean_packages

    rm /setup.sh
}

#=======================================================================[NETWORK]
please_wait() {
	n=30
	i=0
	for i in {0..30}; do
		pct=$(( (++i) * 100 / n ))
		echo XXX
		echo $pct
		echo "$msg"
		echo XXX
		sleep 0.1
	done | whiptail --title "NETWORK" --gauge "Please wait..." 6 100 0
}
connect_wifi() {
network=$(ip link | grep "state UP" | awk '{print $2}' | awk -F: '{print $1}')			#cek wifi koneksi
usbteth=$(ip link | grep "enp0s" | awk '{print $2}' | awk -F: '{print $1}')				#cek usb tethering
while :; do
	if [[ -n $network ]]; then 
		whiptail --title "WIFI" --msgbox "terhubung ke wifi $namawifi" --ok-button "Lanjutkan" 7 85
		break
	elif [[ -n $usbteth ]]; then
		whiptail --title "WIFI" --msgbox "terhubung ke usb tethering" --ok-button "Lanjutkan" 7 85
		break
	fi

	msg="Tidak ada koneksi internet! Periksa kabel jaringan atau atur wifi.\nTips: Pilih <Refresh> Jika usb tethering telah disambungkan"
	whiptail --title "NETWORK" --yesno "$msg" --no-button "refersh" --yes-button "Atur wifi" 9 85; nyt=$?
	case $nyt in
	0)
		namawifi=$(whiptail --title "WIFI" --inputbox "Nama wifi : " --cancel-button "Exit" 7 85 3>&1 1>&2 2>&3)
		if [[ $? -eq 1 ]]; then exit ; fi
		iwctl station wlan0 scan
		passwifi=$(whiptail --title "WIFI" --passwordbox "Kata sandi wifi : " --cancel-button "Exit" 7 85 3>&1 1>&2 2>&3)
		if [[ $? -eq 1 ]]; then exit ; fi

		if [[ -n $namawifi ]] || [[ -z $passwifi ]]; then
			gasspoll=$(iwctl station wlan0 connect "$namawifi" --passphrase "$passwifi") ; iyt=$?
			msg="Menghubungkan jaringan..."
			please_wait
			if [[ $iyt -eq 1 ]]; then whiptail --title "WIFI" --msgbox "Nama wifi atau katasandi salah!" 7 85; fi
		fi;;
	esac
done
}

#=======================================================================[PARTITION MANAGER]
#----------------------------------------------------------[select disk] 
info_disk() {
pathdisk=$(fdisk -l | grep GiB | awk '{print $2}' | awk -F: '{print $1}')				# daftar path semua hdd
namedisk=$(fdisk -l $drive | grep model | awk '{print $3}')								# daftar nama semua hdd
sizedisk=$(fdisk -l $drive | grep 'GiB\|MiB' | awk '{print $3}' | awk -F. '{print $1}')	# daftar size semua hdd (tanpa G,M)
}
select_disk_drive() {
	info_disk
	pdisk=($pathdisk)
	ndisk=($namedisk)
	sdisk=($sizedisk)
	choice=$(
			for i in ${pdisk[@]}; do
				echo -e "$i" "${ndisk[next]}_${sdisk[next]}GB"
				((++next))
			done)
	msg="Pilih Disk:\nDimana system akan di install?\n\n"
	drive=$(whiptail --title "DISKS" --menu "$msg" --ok-button "Select" 15 78 0  ${choice[@]} 3>&1 1>&2 2>&3); yt=$?
	if [[ $yt -eq 1 ]]; then exit; fi
}

#--------------------------------------------------------[partisi table]
partisi_table() {
msg="HARAP DI PERHATIKAN.
Pada tahap ini akan memilih antara membuat partisi table atau melewatinya.

Apabila memilih partisi table antara MBR atau GPT, step selanjutnya akan membuka menu
untuk mengatur alokasi size partisi seperti swap, root, home, dan sisanya.
Sedangkan jika memilih <Lewati> akan membuka menu untuk menentukan salah satu partisi yang ada sebagai /root.\n"
partisitable=$(whiptail --title "PARTISI TABLE" --menu "$msg" --ok-button "Select" --cancel-button "Lewati" 20 100 0 MBR "(ms-dos)" GPT "(efi)" 3>&1 1>&2 2>&3)
	case $partisitable in
	MBR)
		partisitable=msdos
		manage_size ;;
	GPT)
		exit
		partisitable=gpt
		manage_size ;;
	*)
	partisitable="Tidak"
	selected_root ;;
	esac
}

#--------------------------------------------[select partition for root]
selected_root() {
while :
do
	info_disk
	partdisk=$(ls -1 $drive[0-9])														# daftar semua partisi di dalam $pathdisk
	partsize=$(lsblk $drive | tail -n +3 | grep part | awk '{print $4}')							# daftar semua size partisi di dalam $pathdisk (G,M)
	partd=($partdisk)
	parts=($partsize)
	
	choice=$(
		for i in ${partd[@]}; do
			echo -e $i "_${parts[n]}"
			((++n))
		done)
	disksize=$(fdisk -l $drive | grep 'GiB' | awk '{print $3}' | awk -F. '{print $1}')
	msg="Pilih partisi root?\nSelected drive: $drive $namedisk ${sizedisk}G"
	partisiroot=$(whiptail --title "PARTISI" --menu "$msg" --ok-button "Select" --cancel-button "Exit" 15 78 0  ${choice[@]} 3>&1 1>&2 2>&3); yt="$?"
		case $yt in 
		0)
			prs=${partisiroot: -1}														# mendapatkan char terahir dari path partisi (/dev/sda3 = 3)
			prs=$((prs - 1))															# nilai prs -  1
			prs=${parts[prs]}															# mendapatkan size partisi (1/2/3) secara dinamis
			prsM=$(echo $prs | grep M)													# mendeteksi size M
			if [[ -n $prsM ]]; then 
				whiptail --title "PILIH PARTISI ROOT" --msgbox "Size tidak boleh kurang dari 4GB!" 7  100
			else break 
			fi ;;
		1)
			exit ;;
		esac
done
}

#------------------------------------[manage size swap, root, home, etc]
manage_size() {	
	sisa_kapasitas() {
		if [[ -z $sizeswap ]] || [[ $sizeswap -le 0 ]]; then sisaswap=$disksize; else sisaswap=$(( disksize - sizeswap )); fi
		if [[ -z $sizeroot ]] || [[ $sizeroot -le 0 ]]; then sisaroot=$sisaswap; else sisaroot=$(( sisaswap - sizeroot )); fi
		if [[ -z $sizehome ]] || [[ $sizehome -le 0 ]]; then sisahome=$sisaroot; else sisahome=$(( sisaroot - sizehome )); fi
		}
s="GB"
unswap="unset sizeswap ; unset sisaswap ; unset bps"									#reset swap
unroot="unset sizeroot ; unset sisaroot ; unset bpr"									#reset root
unhome="unset sizehome ; unset sisahome ; unset bph"									#reset home
unsisa="unset sizesisa ; unset bpl"														#reset sisa
disksize=$(fdisk -l $drive | grep 'GiB' | awk '{print $3}' | awk -F. '{print $1}')

while :; do
	msg="PERHATIKAN! Jika ada tanda (*) partisi wajib dibuat.\nPilih [SELESAI] untuk menyimpan."
	buatpartisi=$(whiptail --title "BUAT PARTISI BARU" --menu "$msg" --ok-button "Select" --nocancel 15 100 6 Swap " Buat partisi /swap : ${bps}" "Root *" " Buat partisi /root : ${bpr}" Home " Buat partisi /home : ${bph}" Sisanya " Buat untuk partisi lainnya : ${bpl}" "" "" "SELESAI" "" --default-item "" 3>&1 1>&2 2>&3); buatpartisiyt=$?
	case $buatpartisi in
	Swap)
		while :; do
			msg="Tentukan size untuk swap.\n\nTOTAL SIZE TERSEDIA : ${disksize}$s"
			sizeswap=$(whiptail --title "BUAT PARTISI SWAP" --inputbox "$msg" 10 100 4 3>&1 1>&2 2>&3); yt=$?
			if [[ $yt -eq 1 ]]; then break ; fi
			if [[ $sizeswap -gt $disksize ]]; then 
				msg="Ups, Tidak boleh lebih dari ${disksize}$s.\n\nTOTAL SIZE TERSEDIA : ${disksize} $s"
				whiptail --title "BUAT PARTISI SWAP" --msgbox "$msg" 7 100 3>&1 1>&2 2>&3
				break
			elif [[ $sizeswap -le $disksize ]]; then 
				if [[ $sizeswap -eq 0 ]]; then $unswap; break; else bps=${sizeswap}$s; fi
				$unroot; $unhome; $unsisa; break 1
			fi
		done ;;
	"Root *")
		while :; do
		sisa_kapasitas
			if [[ $sisaswap -lt 4  ]]; then
				msg="Ups, Tidak ada kapasitas tersisa!"
				whiptail --title "BUAT PARTISI ROOT" --msgbox "$msg" 7 100 3>&1 1>&2 2>&3; 
				$unswap; break
			fi
			msg="Tentukan size untuk /root. minimum size adalah 4$s.\n\nTOTAL SIZE TERSEDIA : ${sisaswap}$s"
			sizeroot=$(whiptail --title "BUAT PARTISI ROOT" --inputbox "$msg" 10 100 $sisaswap 3>&1 1>&2 2>&3); yt=$?
			if [[ $yt -eq 1 ]]; then $unroot ; break 1;fi
			if [[ $sizeroot -lt 4 ]]; then
				msg="Ups, Size terlalu kecil! Minimum size untuk partisi root adalah 4$s.\n\nTOTAL SIZE TERSEDIA : $sisaswap $s"
				whiptail --title "BUAT PARTISI ROOT" --msgbox "$msg" 7 100 3>&1 1>&2 2>&3;
			elif [[ $sizeroot -gt $sisaswap ]]; then
				msg="Ups, Melebihi kapasitas! Maximum size untuk partisi root adalah : ${sisaswap} $s"
				whiptail --title "BUAT PARTISI ROOT" --msgbox "$msg" 7 100 3>&1 1>&2 2>&3; 
			else 
				if [[ $sizeroot -lt 4 ]]; then sizeroot=4; bpr=${sizeroot}$s; else bpr=${sizeroot}$s; fi
				$unhome; $unsisa; break 1 
			fi
		done ;;
	Home)
		while :; do
		sisa_kapasitas
			if [[ $sisaroot -le 0 ]]; then 
				msg="Ups, Tidak ada kapasitas tersisa!"
				whiptail --title "BUAT PARTISI YANG TERSISISA" --msgbox "$msg" 7 100 3>&1 1>&2 2>&3
				break
			fi
			msg="Tentukan size untuk /home.\n\nTOTAL SIZE TERSEDIA : ${sisaroot}$s."
			sizehome=$(whiptail --title "BUAT PARTISI HOME" --inputbox "$msg" 10 100 ${sisaroot} 3>&1 1>&2 2>&3)
			$unsisa
			if [[ -n $sizehome ]] && [[ $sizehome -gt $sisaroot ]]; then
				whiptail --title "BUAT PARTISI HOME" --msgbox "Ups, Melebihi kapasitas!" 7 100 3>&1 1>&2 2>&3
			elif [[ $sizehome -le $sisaroot ]]; then 
				if [[ $sizehome -eq 0 ]]; then $unhome; else bph=${sizehome}$s;	fi
				$unsisa; break 1
			fi
		done ;;
	Sisanya)
		while :; do
		sisa_kapasitas
			if [[ $sisahome -le 0 ]]; then
				msg="Ups, Tidak ada kapasitas tersisa!"
				whiptail --title "BUAT PARTISI YANG TERSISISA" --msgbox "$msg" 7 100 3>&1 1>&2 2>&3
				break
			fi
			msg="Buat partisi dari size yg tersisa.\n\nTOTAL SIZE TERSEDIA : ${sisahome}$s"
			sizesisa=$(whiptail --title "BUAT PARTISI YANG TGERSISISA" --inputbox "$msg" 10 100 ${sisahome} 3>&1 1>&2 2>&3)
			if [[ $sizesisa -gt $sisahome ]]; then
				whiptail --title "BUAT PARTISI YANG TERSISA" --msgbox "Ups, Melebihi kapasitas!" 7 100 3>&1 1>&2 2>&3
			elif [[ $sizesisa -le $sisahome ]];	then 
				if [[ $sizesisa -eq 0 ]]; then $unsisa; else bpl=${sizesisa}$s; fi
				break 1
			fi
		done ;;
	SELESAI)
		if [[ -z $sizeroot ]]; then
			$unswap ; $unroot ;	$unhome ; $unsisa
			whiptail --title "BUAT PARTISI BARU" --msgbox "Ups, belum mengatur partisi root" 7 100 3>&1 1>&2 2>&3
		else break 1
		fi ;;
	esac
done
}

#------------------------------------------[set root partition selected]
path_partisi_root() {
	pathswap=$(lsblk | grep SWAP | awk '{print $1}')
	if [[ -n $pathswap ]]; then swapoff ${drive}${pathswap: -1}; fi
	pathmnt=$(lsblk | grep mnt | awk '{print $1}')
	if [[ -n $pathmnt ]]; then umount -a &>/dev/null;fi

	yes | mkfs.ext4 $partisiroot
	mount $partisiroot /mnt
}
#--------------------------------------------------[set partition table]
buat_partisi_table() {
	pathswap=$(lsblk | grep SWAP | awk '{print $1}')
	if [[ -n $pathswap ]]; then swapoff ${drive}${pathswap: -1}; fi
	pathmnt=$(lsblk | grep mnt | awk '{print $1}')
	if [[ -n $pathmnt ]]; then umount -a &>/dev/null;fi
	parted -s $drive mktable $partisitable
}
#--------------------------------------------------------[set size swap]
buat_partisi_swap() {
	size_swap () {
		s=G
		parted -s $drive mkpart primary linux-swap 1M $sizeswap$s
		yes | mkswap ${drive}$nourut
		swapon ${drive}$nourut
		}
	
	if [[ -n $sizeswap ]]; then nourut=1; size_swap; fi
}
#--------------------------------------------------------[set size root]
buat_partisi_root() {
	size_root() {
		if [[ $sizeroot == $sisaswap ]]; then sizeroot=100; s="%"; else s="G"; fi
		if [[ -z $sizeswap ]]; then sizeswap="1M"; else sizeswap=${sizeswap}G; fi
		parted -s $drive mkpart primary ext4 $sizeswap $sizeroot$s ;
		yes | mkfs.ext4 ${drive}$nourut ;
		mount ${drive}$nourut /mnt
		}
	
	if [[ $nourut -le 0 ]]; then 
		nourut=1; 
		size_root
	elif [[ $nourut -eq 1 ]]; then
		nourut=2; 
		size_root
	fi
}
#--------------------------------------------------------[set size home]
buat_partisi_home() {
	size_home() {
		if [[ -n $sizehome ]] && [[ $sizehome == $sisaroot ]]; then sizehome=100; s="%"; else s="G"; fi
		if [[ -n $sizeroot ]];then sizeroot=${sizeroot}G; fi
		parted -s $drive mkpart primary ext4 $sizeroot $sizehome$s
		yes | mkfs.ext4 ${drive}$nourut
		mkdir -p /mnt/home
		mount ${drive}$nourut /home
		}
	
	if [[ -n $sizehome ]] && [[ $nourut -eq 1 ]]; then
		nourut=2; 
		size_home
	elif [[ -n $sizehome ]] && [[ $nourut -eq 2 ]]; then
		nourut=3; 
		size_home
	fi
}
#--------------------------------------------------------[set size sisa]
buat_partisi_sisa() {
	size_sisa() { 
		if [[ -n $sizesisa ]] && [[ $sizesisa -eq $sizehome ]] || [[ $sizesisa -eq $sisaroot ]]; then sizesisa=100; s="%"; else s="G"; fi
		if [[ -z $sizehome ]]; then sizehome=${sizeroot}G; fi
		parted -s $drive mkpart primary ext4 $sizehome$s $sizesisa$s
		yes | mkfs.ext4 ${drive}$nourut
		chmod 755 ${drive}$nourut
		}
	
	if [[ -n $sizesisa ]] && [[ $nourut -eq 1 ]]; then
		nourut=2; size_sisa
	elif [[ -n $sizesisa ]] && [[ $nourut -eq 2 ]]; then
		nourut=3; size_sisa 
	elif [[ -n $sizesisa ]] && [[ $nourut -eq 3 ]]; then
		nourut=4; size_sisa 
	fi
}
#=======================================================================[FORMATTING]
# format partisi
format_partisi() {
	if [[ $eksyt == 0 ]];then
		case $partisitable in
		Tidak)
			#setup partition for root
			path_partisi_root
			;;
		msdos)
			#creat partition table
			buat_partisi_table
			
			#creat /swap
			buat_partisi_swap
			
			#creat /root
			buat_partisi_root
			
			#creat /home
			buat_partisi_home
			
			#creat /sisa
			buat_partisi_sisa
			;;
		esac
	fi
}

#=======================================================================[SHOW OUTPUT]
periksa_data() {
case $partisitable in
Tidak)
	info_disk
	targetinstall=$(echo "$partisiroot")
	sdrive=$(echo "Target install          : $drive $namedisk ${sizedisk}GB")
	ptable=$(echo "Partisi table           : ${partisitable}")
	proot=$(echo "Partisi root            : $partisiroot $prs")
	msg=$(
	echo "Apakah data dibawah sudah benar ?"
	echo ""
	echo "$sdrive"
	echo "$ptable"
	echo "$proot"
	echo ""
	echo "Host name               : $hostname"
	echo "User name               : $username"
	echo "Time zone               : $timezone"
	echo "layout keyboard         : $keymap"
	echo ""
	echo ""
	)
	whiptail --title "PERIKSA DATA" --scrolltext --yesno "$msg" --yes-button "Ya" --no-button "Batalkan" 27 100
	if [[ $? -eq 1 ]]; then exit; else confirm_to_format ; fi
	;;
msdos)
	#swap
	if [[ -n $sizeswap ]]; then
		pswap=$(echo "Partisi swap            : ${bps}")
		unset proot ; unset phome ; unset psisa
	fi
	
	#root
	if [[ -n $sizeroot ]] && [[ -z $sizeswap ]]; then
		pswap=$(echo "Partisi root            : ${bpr}")
		unset proot ; unset phome ; unset psisa
		elif [[ -n $sizeroot ]] && [[ -n $sizeswap ]]; then
		proot=$(echo "Partisi root            : ${bpr}")
	fi
	
	#home
	if [[ -n $sizehome ]] && [[ -z $sizeswap ]]; then
		proot=$(echo "Partisi home            : ${bph}")
		unset phome ; unset psisa
		elif [[ -n $sizehome ]] && [[ -n $sizeswap ]]; then
		phome=$(echo "Partisi home            : ${bph}")
		unset psisa
	fi
	
	#sisa
	if [[ -n $sizesisa ]] && [[ -z $sizehome ]] && [[ -z $sizeswap ]]; then
		proot=$(echo "Partisi sisa            : ${bpl}")
		unset phome ; unset psisa
		elif [[ -n $sizesisa ]] && [[ -n $sizehome ]] && [[ -z $sizeswap ]]; then
		phome=$(echo "Partisi sisa            : ${bpl}")
		unset psisa
		elif [[ -n $sizesisa ]] && [[ -z $sizehome ]] && [[ -n $sizeswap ]]; then
		phome=$(echo "Partisi sisa            : ${bpl}")
		unset psisa
		elif [[ -n $sizesisa ]] && [[ -n $sizehome ]] && [[ -n $sizeswap ]]; then
		psisa=$(echo "Partisi sisa            : ${bpl}") 
	fi
	
	#show data
	info_disk
	targetinstall=$(echo "$drive $namedisk ${disksize}GB")
	sdrive=$(echo "Target install          : $drive $namedisk ${disksize}GB")
	ptable=$(echo "Partisi table           : ${partisitable}")
	msg=$(
	echo "Sebelum melanjutkan pastikan data dibawah sudah benar."
	echo ""
	echo "$sdrive"
	echo "$ptable"
	echo ""
	echo "$pswap"
	echo "$proot"
	echo "$phome"
	echo "$psisa"
	echo "Host name               : $hostname"
	echo "User name               : $username"
	echo "Time zone               : $timezone"
	echo "layout keyboard         : $keymap"
	echo ""
	echo ""
	)
	whiptail --title "PERIKSA DATA" --scrolltext --yesno "$msg" --yes-button "Ya" --no-button "Batalkan" 22 100
	if [[ $? -eq 1 ]]; then exit; else confirm_to_format ; fi
	;;
esac
}
#WARNING
confirm_to_format() {
	info_disk
	msg=$(
		echo "!CATATAN: Setelah memilih <YA> proses install tidak dapat dibatalkan!"
		echo ""
		echo "Proses ini akan menghapus seluruh data pada drive: $targetinstall."
		echo "Sebelum melanjutkan, cadangkan dulu data-data pentingnya."
		echo ""
		echo ""
		echo ""
		echo ""
		echo "Tekan <YA> jika sudah yakin, atau tekan <KELUAR> untuk membatalkan semua perubahan."
		)
	eksekusi=$(whiptail --clear --title "PERHATIAN!" --yesno "$msg" --yes-button "YA" --no-button "KELUAR" 16 100 3>&1 1>&2 2>&3) eksyt=$?
	if [[ eksyt -eq 1 ]]; then exit; fi
}

#STEP SETUP
#---------------------------------------------------------[install base]
install_base() {
        pacman -S --noconfirm archlinux-keyring
	pacstrap /mnt base linux linux-firmware nano libnewt
	#fix gpg key if error
	if ! [[ $? == 0 ]]; then 
	echo 'memperbaiki gpg key yang error'
	killall gpg-agent
	rm -rf /etc/pacman.d/gnupg
	pacman-key --init
	pacman-key --populate archlinux
	pacstrap /mnt base linux linux-firmware nano libnewt
	if ! [[ $? == 0 ]]; then exit; fi
	fi
}

#----------------------------------------------------------------[fstab]
set_fstab() {
    genfstab -U /mnt >> /mnt/etc/fstab
}

#---------------------------------------------------------------[chroot]
set_chroot() {
	isetup="/mnt/setup.sh"
    cp $0 $isetup
	sed -i "3ihostname='$hostname'" $isetup
	sed -i "4ipassroot='$passroot'" $isetup
	sed -i "5iusername='$username'" $isetup
	sed -i "6ipassuser='$passuser'" $isetup
	sed -i "7itimezone='$timezone'" $isetup
	sed -i "8ikeymap='$keymap'" $isetup
	sed -i "9idrive='$drive'" $isetup
	sed -i "10idesktopyt='$desktopyt'" $isetup
	sed -i "11ipkg='$(echo -e $pkgtools)'" $isetup
        sed -i "12ipathgrub='$pathgrub'" $isetup
        sed -i "13grubyt='$grubyt'" $isetup
	arch-chroot /mnt ./setup.sh chroot
}
error_message() {
if [ -f /mnt/setup.sh ]
    then
		msg=''
        msg='ERROR: Tidak dapat melakukan chroot ke system.'
        msg+='\nKesalah bisa terjadi karena proses installing "base" terganggu.'
        msg+='\nPastikan koneksi internet tetap stabil.'
		echo "$msg"
	else
        unmount_filesystems
        msg='Installation is complete.'
        echo "$msg"
    fi
}

#CONFIGURE STEP
#-------------------------------------------------------------[hostname]
input_hostname() {
	while :; do
		msg="Nama host/komputer?"
		hostname=$(whiptail --title "HOSTNAME"	--inputbox "$msg" --nocancel 7 85 3>&1 1>&2 2>&3)		#inputbox didalam subkulit
		hostname=$(echo $hostname | tr '[:upper:]' '[:lower:]')											#conver huruf besar -> kecil
		printf -v hostname '%s' $hostname; hostname=$(echo "$hostname")									#hapus semua spasi atau ruang putih kosong
		if [[ -n $hostname ]]; then break; fi
	done
}
set_hostname() {
    echo "$hostname" > /etc/hostname
    cat >> /etc/hosts <<EOF
127.0.0.1	localhost 
::1		localhost
127.0.1.1	$hostname.localdomain	$hostname 
EOF
	}

#-------------------------------------------------------------[timesone]
input_timezone() {
	msg="Pilih zona waktu tempat :\nIni akan mengatur waktu ke zona yg dipilih. Jika tinggal di Indonesia pilih (Asia/Jakarta).\n\n"
	tz=$(timedatectl list-timezones)																	# daftar timezones
	commands=($(
		for i in $tz; do
		echo -e "$i \r"
		done))
	timezone=$(whiptail --title "TIME ZONES" --menu "$msg" --nocancel --default-item "Asia/Jakarta" 25 100 15 ${commands[@]} 3>&1 1>&2 2>&3)
}
set_timezone() {
    ln -sf "/usr/share/zoneinfo/$timezone" /etc/localtime
    hwclock --systohc
	}

#--------------------------------------------------------[root password]
input_root_password() {
	while :; do
		title="PASSWORD ROOT"
		msg="Buat password root."
		passroot=$(whiptail --title "$title" --passwordbox "$msg" --nocancel 7 85 3>&1 1>&2 2>&3)		#passwordbox
		msg="Ulangi masukan password root"
		passroot1=$(whiptail --title "$title" --passwordbox "$msg" --nocancel 7 85 3>&1 1>&2 2>&3)		#passwordbox
		
		if [[ -z $passroot ]] || [[ -z $passroot1 ]]; 
		then
			msg="Password tidak boleh kosong!"
			whiptail --title "$title" --msgbox "$msg" 7 85
		elif [[ $passroot == $passroot1 ]]; 
		then 
			break; 
		else 
			msg="Password tidak sama!"
			whiptail --title "$title" --msgbox "$msg" 7 85
		fi
	done
}
set_root_password() {
    echo -en "$passroot\n$passroot" | passwd
	}

#-----------------------------------------------------------[creat user]
input_create_user() {
	while :
	do
		msg="Tambah user baru?"
		username=$(whiptail --title "CREAT USER" --inputbox "$msg" --nocancel 7 85 3>&1 1>&2 2>&3)				#inputbox didalam subkulit
		username=$(echo $username | tr '[:upper:]' '[:lower:]')													#conver huruf besar -> kecil
		printf -v username '%s' $username; username=$(echo "$username")											#hapus semua spasi atau ruang putih kosong
		if [[ -n $username ]]; then break; fi
	done
	while :; do
		msg="Password untuk user $username"
		passuser=$(whiptail --title "PASSWORD ROOT"	--passwordbox "$msg" --nocancel 7 85 3>&1 1>&2 2>&3)		#passwordbox
		msg="Ulangi masukan password"
		passuser1=$(whiptail --title "PASSWORD ROOT" --passwordbox "$msg" --nocancel 7 85 3>&1 1>&2 2>&3)		#passwordbox
		if [[ -z $passuser ]] || [[ -z $passuser1 ]]; 
		then 
			whiptail --title "PASSWORD USER" --msgbox "Password tidak boleh kosong!" 7 85
		elif
			[[ $passuser == $passuser1 ]]; 
		then 
			break; 
		else  
			whiptail --title "PASSWORD USER" --msgbox "Password tidak sama!" 7 85; 
		fi
	done
}
create_user() {
    useradd -m -G wheel "$username"
	echo -en "$passuser\n$passuser" | passwd "$username"
	}

#-------------------------------------------------------------[pkgtools]
input_pkg_tools() {
list=(
	xf86-video-intel "Driver GPU intel" off \
	xf86-video-ati "Driver GPU Radeon" off \
	xf86-video-nouveau "Driver GPU nouveau" off \
	dialog "Dialog interactif di mode cli" on \
	mtools "Utilitas untuk mengakses disk MS-DOS" on \
	ntfs-3g "Dukungan untuk baca/tulis ke filesystem NTFS" on \
	dosfstools "Utilitas untuk membuat dan memeriksa systemfile MSDOS FAT" on \
	os-prober "Menampilkan OS lain pada grub boot loader" on \
	grub "Boot loader" on \
	base-devel "group package for base (pacman, sudo, dll)" on \
	xorg "Display server" on \
	xorg-xinit "Menjalankan aplikasi GUI" on \
	xdg-user-dirs "Folder hirarki user" on \
	wireless_tools "Dukungan/ekstensi untuk wireless dan jaringan" on \
	iwd	'alternatif network manager' off \
	dhcpcd 'client' off \
	networkmanager "Penyedia jaringan" on \
	linux-headers "building modules for kernel" on \
        polkit "authorized tools" on \
	)
msg="\nTools/utilitas dasar, berfungsi untuk mendukung kinerja system.

Hati-hati jika ingin mengaktifkan driver GPU, pilih salah satu saja yg sesuai.
Jika tidak paham, sebaiknya biarkan apa adanya.\n\n"
pkgtools=$(whiptail --separate-output --title "TOOLS AND UTILITIES" --checklist "$msg" 28 100 18 "${list[@]}" 3>&1 1>&2 2>&3)
}
install_pkg_tools() {
	pacman -Sy --noconfirm $pkg
	#fix gpg key if error
	if ! [[ $? == 0 ]]; then 
	echo 'memperbaiki gpg key yang error'
	killall gpg-agent
	rm -rf /etc/pacman.d/gnupg
	pacman-key --init
	pacman-key --populate archlinux
	pacman -Sy --noconfirm $pkg
	fi
	systemctl enable NetworkManager &>/dev/null
	systemctl start NetworkManager &>/dev/null
	}

#---------------------------------------------------------------[locale]
set_locale() {
    echo "LANG=en_US.UTF-8" > /etc/locale.conf
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
    locale-gen
}

#---------------------------------------------------------------[keymap]
input_keymap() {
	msg="Atur layout keyboard. jika bingung pilih saja: (us)\n\n"
	tz=$(localectl list-keymaps)
	pilihan=($(
		for i in $tz; do
		echo -e "$i \r"
		done))
	keymap=$(whiptail --title "$KEYMAP" --menu "$msg" --nocancel --default-item "us" 25 100 15 ${pilihan[@]} 3>&1 1>&2 2>&3)
}
set_keymap() {
    echo "KEYMAP=$keymap" > /etc/vconsole.conf
	}

#--------------------------------------------------------------[sudoers]
set_sudoers() {
    echo "%wheel ALL=(ALL) ALL" | tee -a /etc/sudoers &>/dev/null
}

#-----------------------------------------------------------------[grub]
input_grub() {
	local
pathdisk=$(fdisk -l | grep GiB | awk '{print $2}' | awk -F: '{print $1}')				# daftar path semua hdd
namedisk=$(fdisk -l | grep model | awk '{print $3}')								# daftar nama semua hdd
sizedisk=$(fdisk -l | grep 'GiB\|MiB' | awk '{print $3}' | awk -F. '{print $1}')	# daftar size semua hdd (tanpa G,M)

	pdisk=($pathdisk)
	ndisk=($namedisk)
	sdisk=($sizedisk)
	choice=$(
			for i in ${pdisk[@]}; do
				echo -e "$i" "${ndisk[next]}_${sdisk[next]}GB"
				((++next))
			done)
	msg="Pilih Disk:\nDimana bootloader akan di install?\n\n"
	pathgrub=$(whiptail --title "INSTALL GRUB" --menu "$msg" --ok-button "Select" 15 78 0  ${choice[@]} 3>&1 1>&2 2>&3); grubyt=$?
}

set_grub() {
if [[ $grubyt -eq 0 ]]; then
     grub-install --target=i386-pc $pathgrub
else
     grub-install --target=i386-pc $drive
fi
     grub-mkconfig -o /boot/grub/grub.cfg
}

#--------------------------------------------------[clean chace package]
clean_packages() {
    yes | pacman -Scc
}

#---------------------------------------------------[unmount filesystem]
unmount_filesystems() {
	pathswap=$(lsblk | grep SWAP | awk '{print $1}')
	if [[ -n $pathswap ]]; then 
	swapoff ${drive}${pathswap: -1}; 
	fi
	pathmnt=$(lsblk | grep mnt | awk '{print $1}')
	if [[ -n $pathmnt ]]; then 
	umount -a &>/dev/null
	fi
}

#-------------------------------------------------------------[kde lite]
input_desktop() {
desktop=$(whiptail --title 'DESKTOP' --yesno 'Install desktop kde plasma lite?' --yes-button 'Install' --no-button 'Lewati' 7 85 3>&1 1>&2 2>&3) ; desktopyt=$?
}

set_kde_lite() {
packages=''
packages+=' plasma-desktop plasma-wayland-session plasma-disks plasma-nm plasma-pa plasma-workspace-wallpapers'
packages+=' kdeplasma-addons kdegraphics-thumbnailers ffmpegthumbs kde-gtk-config'
packages+=' kwayland-integration kscreen kinfocenter konsole krunner'
packages+=' dolphin-plugins breeze-gtk powerdevil power-profiles-daemon phonon-qt5-vlc sddm-kcm'
packages+=' spectacle ark gwenview okular'
		

if [[ $desktopyt == 0 ]]; then
pacman -S --noconfirm $packages
systemctl enable sddm

set_sddm_theme
set_kde_menu_edit

fi
}

set_sddm_theme() {
mkdir -p /etc/sddm.conf.d
pathsddm='/etc/sddm.conf.d/kde_settings.conf'
cat <<'EOF' >$pathsddm
[Autologin]
Relogin=false
Session=
User=

[General]
HaltCommand=/usr/bin/systemctl poweroff
RebootCommand=/usr/bin/systemctl reboot

[Theme]
Current=breeze

[Users]
MaximumUid=60513
MinimumUid=1000
EOF

chmod +x $pathsddm
}

set_kde_menu_edit() {
pathmenus="/home/${username}/.config/menus/applications-kmenuedit.menu"
dirmenus="/home/${username}/.config/menus"
kmenu_edit() {
cat <<'EOF' >$pathmenus
<!DOCTYPE Menu PUBLIC '-//freedesktop//DTD Menu 1.0//EN' 'http://www.freedesktop.org/standards/menu-spec/1.0/menu.dtd'>
<Menu>
 <Menu>
  <Name>Development</Name>
  <Exclude>
   <Filename>assistant.desktop</Filename>
   <Filename>designer.desktop</Filename>
   <Filename>linguist.desktop</Filename>
   <Filename>qdbusviewer.desktop</Filename>
   <Filename>org.kde.kuserfeedback-console.desktop</Filename>
  </Exclude>
  <Layout>
   <Merge type="menus"/>
   <Menuname>Translation</Menuname>
   <Menuname>Web Development</Menuname>
  </Layout>
 </Menu>
 <Menu>
  <Name>.hidden</Name>
  <Include>
   <Filename>assistant.desktop</Filename>
   <Filename>designer.desktop</Filename>
   <Filename>linguist.desktop</Filename>
   <Filename>qdbusviewer.desktop</Filename>
   <Filename>bssh.desktop</Filename>
   <Filename>bvnc.desktop</Filename>
   <Filename>avahi-discover.desktop</Filename>
   <Filename>lstopo.desktop</Filename>
   <Filename>qv4l2.desktop</Filename>
   <Filename>qvidcap.desktop</Filename>
   <Filename>org.kde.kuserfeedback-console.desktop</Filename>
  </Include>
 </Menu>
 <Menu>
  <Name>Internet</Name>
  <Layout>
   <Merge type="menus"/>
   <Menuname>Terminal</Menuname>
   <Separator/>
   <Menuname>More</Menuname>
  </Layout>
  <Exclude>
   <Filename>bssh.desktop</Filename>
   <Filename>bvnc.desktop</Filename>
  </Exclude>
 </Menu>
 <Menu>
  <Name>System</Name>
  <Layout>
   <Merge type="menus"/>
   <Menuname>ScreenSavers</Menuname>
   <Menuname>Terminal</Menuname>
   <Merge type="files"/>
   <Filename>org.kde.dolphin.desktop</Filename>
   <Filename>org.kde.kinfocenter.desktop</Filename>
   <Filename>org.kde.konsole.desktop</Filename>
   <Filename>org.kde.kmenuedit.desktop</Filename>
   <Filename>urxvt.desktop</Filename>
   <Filename>urxvtc.desktop</Filename>
   <Filename>urxvt-tabbed.desktop</Filename>
   <Separator/>
   <Menuname>More</Menuname>
  </Layout>
  <Exclude>
   <Filename>avahi-discover.desktop</Filename>
   <Filename>lstopo.desktop</Filename>
  </Exclude>
 </Menu>
 <Menu>
  <Name>Multimedia</Name>
  <Layout>
   <Merge type="files"/>
   <Filename>vlc.desktop</Filename>
   <Separator/>
   <Merge type="menus"/>
   <Menuname>More</Menuname>
  </Layout>
  <Exclude>
   <Filename>qv4l2.desktop</Filename>
   <Filename>qvidcap.desktop</Filename>
  </Exclude>
 </Menu>
 <Menu>
  <Name>Education</Name>
  <Deleted/>
 </Menu>
 <Layout>
  <Merge type="menus"/>
  <Menuname>Development</Menuname>
  <Menuname>Games</Menuname>
  <Menuname>Graphics</Menuname>
  <Menuname>Internet</Menuname>
  <Menuname>Multimedia</Menuname>
  <Menuname>Office</Menuname>
  <Menuname>Settingsmenu</Menuname>
  <Menuname>System</Menuname>
  <Menuname>Utilities</Menuname>
  <Menuname>Applications</Menuname>
 </Layout>
 <Menu>
  <Name>Science</Name>
  <Deleted/>
 </Menu>
</Menu>
EOF
	}
if [[ -d $dirmenus ]] && [[ -f $pathmenus ]]; then
kmenu_edit
else 
mkdir -p $dirmenus
kmenu_edit
chown -R ${username}:${username} $dirmenus
fi
}

#-----------------------------------------------------------------[exec]
	if [[ "$1" == "chroot" ]]
	then 
		configure
	else 
		setup
	fi
