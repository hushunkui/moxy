#!/bin/bash

#grub-mkstandalone -d /usr/lib/grub/x86_64-efi/ -O x86_64-efi --fonts="unicode" -o grub-bootx64.efi boot/grub/grub.cfg
#sudo mount /dev/nbd0p1 /mnt/efi/
#sudo cp grub-bootx64.efi /mnt/efi/EFI/BOOT/bootx64.efi 
#sudo umount /mnt/efi/

mkdir -p boot/grub
cat <<EOF > boot/grub/grub.conf
menuentry "tinycore" {                                                                                                                                                                                                                                       
  set gfxpayload=keep                                                                                                                                                                                                                                      
      linux (memdisk)/tc_vmlinuz                                                                                                                                                                                                                           
      initrd (memdisk)/tc_initrd                                                                                                                                                                                                                           
}                                                                                                                                                                                                                                                            
                                                                                                                                                                                                                                                             
set timeout=0                                                                                                                                                                                                                                                
set default="tinycore" 
EOF

cp /build/vmlinuz ./tc_vmlinuz
cp /build/initramfs ./tc_initrd
tar cvf memdisk.tar boot 

grub-mkimage  -v --memdisk=memdisk.tar -o grub-boot.img -O i386-pc memdisk tar echo sleep linux reboot multiboot linux16 boot # gfxterm

cp /usr/lib/grub/i386-pc/lnxboot.img ./lnxboot.img
#grub-mkstandalone --compress xz -o ./core.img \
#    -d /usr/lib/grub/i386-pc/ -O i386-pc \
#    --modules="all_video echo gfxterm halt normal pci png reboot serial test" boot/grub/grub.cfg

#grub-mkstandalone -d /usr/lib/grub/i386-pc/ -O i386-pc -o grub-boot-2.img --fonts="unicode" memdisk.tar

