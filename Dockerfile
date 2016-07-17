FROM debian:jessie

RUN apt-get -y update && \
    apt-get -y upgrade

RUN apt-get -y install \
      debootstrap \
      syslinux \
      squashfs-tools \
      genisoimage \
      memtest86+ \
      pciutils \
      rsync

RUN echo "building" >/machine.version

WORKDIR /root/build
CMD ./run.sh

