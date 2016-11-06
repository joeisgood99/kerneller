#!/sbin/sh
# Define commonly used/long directory names.
boot="/dev/block/platform/msm_sdcc.1/by-name/boot"
tools="/tmp/kerneller/tools"
work="/tmp/kerneller/work"
OUTFD=`ps | grep -v "grep" | grep -oE "update(.*)" | cut -d" " -f3`;
ui_print() { echo "ui_print $1" >&$OUTFD; echo "ui_print" >&$OUTFD; }
# Remove files from previous installation -- if the user flashes the zip
# twice, there would otherwise be issues, creating a useless boot.img
rm -rf $work;
# Extract the ramdisk, check if it's one- or two-staged
# (New Xperia boot images as well as most other devices use a single stage.)
ramdisk_extract () {
	ui_print "Modifying ramdisk";
	dd if=$boot of=/tmp/kerneller/original.img;
	chmod 777 $tools/unpackbootimg;
	mkdir $work;
	$tools/unpackbootimg -i /tmp/kerneller/original.img -o $work;
	mkdir $work/combinedroot;
	cd $work/combinedroot;
	cat $work/original.img-ramdisk.gz | gzip -d | cpio -i -d;
  	if [ ! -f $work/combinedroot/sbin/ramdisk.cpio ]; then
		ui_print "Found single-stage ramdisk"
		number=1
		fstab=$work/combinedroot/fstab.qcom
  	else 
		ui_print "Found two-stage ramdisk"
		number=2
		fstab=$work/ramdisk/fstab.qcom
		mkdir $work/ramdisk;
		cd $work/ramdisk;
		cat $work/combinedroot/sbin/ramdisk.cpio | cpio -i -d;
  	fi
}
# Replace the crucial files and repack the ramdisk
ramdisk_cpy () {
# Modify the following as per the files you've placed inside res/ (other than zImage & dt)
	cp /tmp/kerneller/res/fstab.qcom $work/ramdisk/fstab.qcom;
	cp /tmp/kerneller/res/init.sh $work/combinedroot/sbin/init.sh;
	chmod 777 $work/ramdisk/fstab.qcom;
	chmod 777 $work/combinedroot/sbin/init.sh;
# Repack the ramdisk back completely
	if [ $number = 2 ]; then
		find . | cpio -o -H newc > $work/combinedroot/sbin/ramdisk.cpio;
		cd $work/combinedroot;
		ui_print "Repacking two-stage ramdisk"
	else 
		find . | cpio -o -H newc | gzip -c > $work/original.img-ramdisk.gz;
		ui_print "Repacking single-stage ramdisk"
	fi
}

cmdline () {
	cd $work
	# If Vol+ was pressed, check if cmdline already has the permissive tag
	# If yes, move on. If not, echo it in.
	if [ $mode = "permissive" ]; then
		if cat $work/original.img-cmdline | grep androidboot.selinux=permissive; then
			:
		elif ! cat $work/original.img-cmdline | grep androidboot.selinux=permissive; then
			 echo "$(cat $work/original.img-cmdline) androidboot.selinux=permissive" >$work/original.img-cmdline
		fi
	# Else, check the cmdline and remove the tag if it's already present
	else
		if ! cat $work/original.img-cmdline | grep androidboot.selinux=permissive; then
			:
		elif cat $work/original.img-cmdline | grep androidboot.selinux=permissive; then
			# It's dirty, I know. I'm new to this.
			# Tips and/or pull requests appreciated!
			cat $work/original.img-cmdline | sed 's/ androidboot.selinux=permissive//' >tmp
			cat tmp >$work/original.img-cmdline
		fi
	fi
	cat $work/original.img-cmdline
}

mkimg () {
	chmod 777 $tools/mkbootimg
	$tools/mkbootimg --kernel /tmp/kerneller/res/zImage-dtb --ramdisk $work/original.img-ramdisk.gz --cmdline "$(cat $work/original.img-cmdline)" --board "$(cat $work/original.img-board)" --base "$(cat $work/original.img-base)" --pagesize "$(cat $work/original.img-pagesize)" --kernel_offset "$(cat $work/original.img-kerneloff)" --ramdisk_offset "$(cat $work/original.img-ramdiskoff)" --tags_offset "$(cat $work/original.img-tagsoff)" -o /tmp/kerneller/boot.img
}

modcpy () {
	cp -f /tmp/kerneller/modules/* /system/lib/modules/
}

# Functions are all set: Run them in order
ramdisk_extract
#ramdisk_cpy
#cmdline
mkimg
# Check for one of the files we copied: if it's there, the boot
# image was repacked succesfully. If not, flashing it would not
# allow the device to boot. Include copying of modules in this check
if [ -f /tmp/kerneller/boot.img ]; then
# [ -f $work/ramdisk/fstab.qcom ] || [ -f $work/combinedroot/fstab.qcom ] && 
  ui_print "Done messing around!";
  ui_print "Writing the new boot.img...";
  dd if=/tmp/kerneller/boot.img of=/dev/block/platform/msm_sdcc.1/by-name/boot
  # ui_print "Copying modules...";
  #modcpy
else
  ui_print "Error creating working boot image, aborting install!";
fi
