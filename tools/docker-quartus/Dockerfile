FROM ubuntu:18.04 as install
ADD libpng12-0_1.2.54-1ubuntu1.1_amd64.deb /libpng12-0_1.2.54-1ubuntu1.1_amd64.deb
ADD libpng12-0_1.2.54-1ubuntu1.1_i386.deb /libpng12-0_1.2.54-1ubuntu1.1_i386.deb
ADD Quartus-web-13.1.0.162-linux.tar /quartus
ADD QuartusSetup-13.1.4.182.run /quartus
RUN set -eux && \
    dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install --no-install-recommends -y \
        ca-certificates \
        lib32ncurses5-dev \
        libc6:i386 \
        libfontconfig1 \
        libglib2.0-0 \
        libncurses5:i386 \
        libsm6 \
        libsm6:i386 \
        libssl-dev \
        libstdc++6:i386 \
        libxext6:i386 \
        libxft2:i386 \
        libxrender1 \
        libzmq3-dev \
        locales \
        make \
        openjdk-8-jdk \
        pkg-config \
        unixodbc-dev \
        wget \
        xauth \
        xvfb && \
        dpkg --install  /libpng12-0_1.2.54-1ubuntu1.1_amd64.deb /libpng12-0_1.2.54-1ubuntu1.1_i386.deb && \
        ln -s /usr/bin/env /bin/env && \
        /quartus/setup.sh --mode unattended --installdir /opt/quartus && \
        chmod a+x /quartus/QuartusSetup-13.1.4.182.run && \
        /quartus/QuartusSetup-13.1.4.182.run --mode unattended --installdir /opt/quartus && \
        rm -rf /quartus

