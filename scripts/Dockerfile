FROM ubuntu:22.04

ARG LC_ALL=C DEBIAN_FRONTEND=noninteractive
ENV DEBIAN_FRONTEND noninteractive
ENV TZ=Asia/Shanghai LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

USER root

RUN sed -i 's/archive.ubuntu.com/cn.archive.ubuntu.com/g' /etc/apt/sources.list
RUN apt-get update -q && \
    apt-get install -y --no-install-recommends \
        locales locales-all && \
    apt-get clean && \
    locale-gen en_US.UTF-8 && \
    rm -rf /var/lib/apt/lists/* 
 
# Yocto build
# https://docs.yoctoproject.org/4.0.31/brief-yoctoprojectqs/index.html
RUN apt-get update -q && \
    apt-get install -y --no-install-recommends \
        build-essential chrpath cpio debianutils diffstat file gawk gcc git \
        iputils-ping libacl1 liblz4-tool locales python3 python3-git \
        python3-jinja2 python3-pexpect python3-pip python3-subunit \
        socat texinfo unzip wget xz-utils zstd \
        rsync tmux iproute2 iptables sudo  && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Cross compile toolchains for ARM and ARM64
#RUN wget -O gcc-arm-8.3-2019.03-x86_64-arm-linux-gnueabihf.tar.xz \
# "https://developer.arm.com/-/media/Files/downloads/gnu-a/8.3-2019.03/binrel/\
#gcc-arm-8.3-2019.03-x86_64-arm-linux-gnueabihf.tar.xz?\
#revision=e09a1c45-0ed3-4a8e-b06b-db3978fd8d56&la=en&hash=93ED4444B8B3A812B893373B490B90BBB28FD2E3" && \
#    tar -xf gcc-arm-8.3-2019.03-x86_64-arm-linux-gnueabihf.tar.xz -C /opt/ && \
#    rm gcc-arm-8.3-2019.03-x86_64-arm-linux-gnueabihf.tar.xz
#ENV ARCH=arm
#ENV CROSS_COMPILE=arm-linux-gnueabihf-
#ENV PATH=/opt/gcc-arm-8.3-2019.03-x86_64-arm-linux-gnueabihf/bin/:$PATH
#ENV DTC_FLAGS="-@"
#
#RUN wget -O gcc-arm-9.2-2019.12-x86_64-aarch64-none-linux-gnu.tar.xz \
#"https://developer.arm.com/-/media/Files/downloads/gnu-a/9.2-2019.12/binrel/\
#gcc-arm-9.2-2019.12-x86_64-aarch64-none-linux-gnu.tar.xz?\
#revision=61c3be5d-5175-4db6-9030-b565aae9f766&la=en&hash=0A37024B42028A9616F56A51C2D20755C5EBBCD7" && \
#    tar -xf gcc-arm-9.2-2019.12-x86_64-aarch64-none-linux-gnu.tar.xz -C /opt/ && \
#    rm gcc-arm-9.2-2019.12-x86_64-aarch64-none-linux-gnu.tar.xz
#ENV ARCH=arm64
#ENV CROSS_COMPILE=aarch64-none-linux-gnu-
#ENV PATH=/opt/gcc-arm-9.2-2019.12-x86_64-aarch64-none-linux-gnu/bin/:$PATH
#ENV DTC_FLAGS="-@"