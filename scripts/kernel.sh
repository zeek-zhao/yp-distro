#!/bin/bash
#https://mirrors.aliyun.com/gnu/gcc/

#mkdir -p kernels && cd kernels
#wget https://mirrors.aliyun.com/gnu/gcc/gcc-13.4.0/gcc-13.4.0.tar.xz
#wget https://mirrors.aliyun.com/gnu/gcc/gcc-11.5.0/gcc-11.5.0.tar.xz
#git clone --branch v5.15 --depth 1 https://github.com/torvalds/linux.git 5.15
#git clone --branch v6.6 --depth 1 https://github.com/torvalds/linux.git 6.6

https://developer.toradex.com/hardware
https://developer.toradex.com/hardware/legacy-products/apalis-som-family/apalis-tk1
https://developer.toradex.com/hardware/legacy-products/apalis-som-family/apalis-imx8x
https://developer.toradex.com/software/linux-resources/linux-features/

https://developer.toradex.com/linux-bsp/os-development/build-u-boot-and-linux-kernel-from-source-code/build-u-boot/build-u-boot-for-nxp-imx88x-modules/
https://developer.toradex.com/linux-bsp/os-development/build-u-boot-and-linux-kernel-from-source-code/build-linux-kernel-from-source-code#downstream
https://developer.toradex.com/linux-bsp/os-development/build-u-boot-and-linux-kernel-from-source-code/build-device-tree-overlays-from-source-code
https://developer.toradex.com/linux-bsp/os-development/build-u-boot-and-linux-kernel-from-source-code/build-custom-imx-88x-system-controller-firmware-scfw
https://developer.toradex.com/linux-bsp/os-development/build-yocto/yocto-project

# https://developer.arm.com/downloads/-/gnu-a
# AArch64 GNU/Linux target (aarch64-none-linux-gnu)
# apalis-imx8x
wget -O gcc-arm-9.2-2019.12-x86_64-aarch64-none-linux-gnu.tar.xz https://developer.arm.com/-/media/Files/downloads/gnu-a/9.2-2019.12/binrel/gcc-arm-9.2-2019.12-x86_64-aarch64-none-linux-gnu.tar.xz?revision=61c3be5d-5175-4db6-9030-b565aae9f766&la=en&hash=0A37024B42028A9616F56A51C2D20755C5EBBCD7
ADD gcc-arm-9.2-2019.12-x86_64-aarch64-none-linux-gnu.tar.xz /
ENV ARCH=arm64
ENV CROSS_COMPILE=aarch64-none-linux-gnu-
ENV PATH=/gcc-arm-9.2-2019.12-x86_64-aarch64-none-linux-gnu/bin/:$PATH
ENV DTC_FLAGS="-@"
# kernel编译过程
make clean
make toradex_defconfig
make menuconfig
make -j$(nproc) Image.gz
make -j$(nproc) modules
mkdir modules && export INSTALL_MOD_PATH=modules && make modules_install && cd modules && tar -czf ../modules.tar.gz . && cd ..
make freescale/imx8qm-apalis-v1.1-eval.dtb
# kernel使用过程
scp arch/arm64/boot/Image.gz root@127.0.0.1:~/1
scp modules.tar.gz root@127.0.0.1:~/1
scp arch/arm64/boot/dts/freescale/imx8qm-apalis-v1.1-eval.dtb root@127.0.0.1:~/1
tar -xzf modules.tar.gz -C /


# ARM Linux target (arm-linux-gnueabihf) 
# apalis-tk1
wget -O gcc-arm-8.3-2019.03-x86_64-arm-linux-gnueabihf.tar.xz https://developer.arm.com/-/media/Files/downloads/gnu-a/8.3-2019.03/binrel/gcc-arm-8.3-2019.03-x86_64-arm-linux-gnueabihf.tar.xz?revision=e09a1c45-0ed3-4a8e-b06b-db3978fd8d56&la=en&hash=93ED4444B8B3A812B893373B490B90BBB28FD2E3
ADD gcc-arm-8.3-2019.03-x86_64-arm-linux-gnueabihf.tar.xz /
ENV ARCH=arm
ENV CROSS_COMPILE=arm-linux-gnueabihf-
ENV PATH=/gcc-arm-8.3-2019.03-x86_64-arm-linux-gnueabihf/bin/:$PATH
ENV DTC_FLAGS="-@"

# kernel 配置
make tegra_defconfig
make
# kernel 设备树
tegra124-apalis-v1.2-eval.dtb
tegra124-apalis-eval.dtb


