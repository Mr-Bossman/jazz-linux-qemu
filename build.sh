cat <<EOF > /etc/apt/sources.list.d/bookworm.sources
Types: deb deb-src
URIs: http://deb.debian.org/debian
Suites: bookworm
Architectures: mipsel
Components: main
EOF
apt update
apt install -y dpkg-dev debhelper quilt python3 flex bison gcc-mipsel-linux-gnu libssl-dev bc
apt source -t bookworm linux
cd linux-*
cat <<EOF | patch -p1
diff --git a/arch/mips/Kconfig b/arch/mips/Kconfig
index 15cb692b0a09..b9404940cc55 100644
--- a/arch/mips/Kconfig
+++ b/arch/mips/Kconfig
@@ -421,6 +421,12 @@ config MACH_JAZZ
 	select I8259
 	select ISA
 	select SYS_HAS_CPU_R4X00
+	select SYS_HAS_CPU_MIPS32_R1
+	select SYS_HAS_CPU_MIPS32_R2
+	select SYS_HAS_CPU_MIPS32_R6
+	select SYS_HAS_CPU_MIPS64_R1
+	select SYS_HAS_CPU_MIPS64_R2
+	select SYS_HAS_CPU_MIPS64_R6
 	select SYS_SUPPORTS_32BIT_KERNEL
 	select SYS_SUPPORTS_64BIT_KERNEL
 	select SYS_SUPPORTS_100HZ
diff --git a/arch/mips/fw/arc/identify.c b/arch/mips/fw/arc/identify.c
index 5527e0f54079..93557929260c 100644
--- a/arch/mips/fw/arc/identify.c
+++ b/arch/mips/fw/arc/identify.c
@@ -98,11 +98,13 @@ void __init prom_identify_arch(void)
 	 * The root component tells us what machine architecture we have here.
 	 */
 	p = ArcGetChild(PROM_NULL_COMPONENT);
-	if (p == NULL) {
+/*
+	if (p == NULL || p->iname == 0) {
 		iname = "Unknown";
 	} else
 		iname = (char *) (long) p->iname;
-
+*/
+	iname = "Microsoft-Jazz";
 	printk("ARCH: %s\n", iname);
 	mach = string_to_mach(iname);
 	system_type = mach->liname;
diff --git a/arch/mips/mm/init.c b/arch/mips/mm/init.c
index e8660d06f663..c72674c7efe6 100644
--- a/arch/mips/mm/init.c
+++ b/arch/mips/mm/init.c
@@ -496,7 +496,7 @@ void __weak __init prom_free_prom_memory(void)

 void __ref free_initmem(void)
 {
-	prom_free_prom_memory();
+//	prom_free_prom_memory();
 	/*
 	 * Let the platform define a specific function to free the
 	 * init section since EVA may have used any possible mapping
--
EOF
chmod -x debian/*.install # https://github.com/sonic-net/sonic-linux-kernel/issues/117#issuecomment-2742269309
debian/rules source
# in the future this may break, compiling using gcc-14 currently works
sed -i 's/gcc-12/gcc/g' debian/rules.gen
sed -i 's/vmlinuz/vmlinux/g' debian/rules.gen
sed -i 's/vmlinuz/vmlinux/g' debian/config/mipsel/defines
sed -i 's/vmlinuz/vmlinux/g' debian/linux-image-*-4kc-malta.*
dpkg-architecture -a mipsel -c "make -f debian/rules.gen setup_mipsel_none"
./scripts/config -d CONFIG_MIPS_MALTA -e CONFIG_MACH_JAZZ -e CONFIG_MIPS_MAGNUM_4000 --file debian/build/build_mipsel_none_4kc-malta/.config
# For some reason ZSTD is not working
./scripts/config -d CONFIG_RD_ZSTD -e CONFIG_FB_G364 -e CONFIG_JAZZ_ESP --file debian/build/build_mipsel_none_4kc-malta/.config
dpkg-architecture -a mipsel -c "make -C debian/build/build_mipsel_none_4kc-malta olddefconfig"
dpkg-architecture -a mipsel -c "DEB_RULES_REQUIRES_ROOT=no make -f debian/rules.gen binary-arch_mipsel_none_4kc-malta_real_image -j$(nproc)"
#CONFIG_FB_G364=y
#CONFIG_JAZZ_ESP=y
#CONFIG_MIPS_JAZZ_SONIC=y
#CONFIG_SERIAL_8250_DETECT_IRQ=y
#ZSTD_INIT=n

#CONFIG_VT_HW_CONSOLE_BINDING=y
#CONFIG_SERIAL_8250=y
#CONFIG_SERIAL_8250_CONSOLE=y
#CONFIG_SERIAL_8250_EXTENDED=y
#CONFIG_SERIAL_8250_SHARE_IRQ=y
#CONFIG_SERIAL_8250_RSA=y