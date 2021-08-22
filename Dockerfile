# nvidia environment
FROM nvidia/cuda:11.4.1-devel-ubuntu18.04 as nvidia_environment

RUN cd / && \
    tar czf nvidia.tar.gz \
      /etc/alternatives/cuda* \
      /usr/local/cuda* \
      /usr/lib/x86_64-linux-gnu/libcuda* \
      /usr/lib/x86_64-linux-gnu/libnv*

# epgstation
FROM l3tnun/epgstation:v2.6.11-debian

# nvidia environment copy
COPY --from=nvidia_environment /nvidia.tar.gz /nvidia.tar.gz
RUN cd / && tar xzf nvidia.tar.gz

ENV DEV="make gcc git g++ automake curl wget autoconf build-essential libass-dev libfreetype6-dev libsdl1.2-dev libtheora-dev libtool libva-dev libvdpau-dev libvorbis-dev libxcb1-dev libxcb-shm0-dev libxcb-xfixes0-dev pkg-config texinfo zlib1g-dev cmake"

ARG NASM_VER="2.14.02"
ARG LAME_VER="3.100"
ARG FFMPEG_VER="4.4"
# ARG NV_CODEC_HEADERS_VER="n11.0.10.1"
ARG NV_CODEC_HEADERS_VER="n11.1.5.0"

ENV LD_LIBRARY_PATH /usr/local/cuda/lib64:$LD_LIBRARY_PATH
ENV NVIDIA_VISIBLE_DEVICES all
ENV NVIDIA_DRIVER_CAPABILITIES utility,compute,video

RUN apt-get update && \
    apt-get -y install $DEV && \
    apt-get -y install yasm libx264-dev libmp3lame-dev libopus-dev libvpx-dev && \
    apt-get -y install libx265-dev libnuma-dev && \
    apt-get -y install libasound2 libass9 libvdpau1 libva-x11-2 libva-drm2 libxcb-shm0 libxcb-xfixes0 libxcb-shape0 libvorbisenc2 libtheora0

RUN mkdir -p /tmp/ffmpeg_sources /tmp/ffmpeg_build /tmp/bin

#NASM
RUN cd /tmp/ffmpeg_sources && \
    wget https://www.nasm.us/pub/nasm/releasebuilds/${NASM_VER}/nasm-${NASM_VER}.tar.bz2 && \
    tar xjvf nasm-${NASM_VER}.tar.bz2 && \
    cd nasm-${NASM_VER} && \
    ./autogen.sh && \
    PATH="/tmp/bin:$PATH" ./configure --prefix="/tmp/ffmpeg_build" --bindir="/tmp/bin" && \
    make -j$(nproc) && \
    make install

#libx264
RUN cd /tmp/ffmpeg_sources && \
    git -C x264 pull 2> /dev/null || git clone --depth 1 https://code.videolan.org/videolan/x264.git && \
    cd x264 && \
    PATH="/tmp/bin:$PATH" PKG_CONFIG_PATH="/tmp/ffmpeg_build/lib/pkgconfig" ./configure --prefix="/tmp/ffmpeg_build" --bindir="/tmp/bin" --enable-static --enable-pic && \
    PATH="/tmp/bin:$PATH" make -j$(nproc) && \
    make install

#libx265
RUN cd /tmp/ffmpeg_sources && \
    git -C x265_git pull 2> /dev/null || git clone https://bitbucket.org/multicoreware/x265_git && \
    cd x265_git/build/linux && \
    PATH="/tmp/bin:$PATH" cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="/tmp/ffmpeg_build" -DENABLE_SHARED=off ../../source && \
    PATH="/tmp/bin:$PATH" make -j$(nproc) && \
    make install

#libvpx
RUN cd /tmp/ffmpeg_sources && \
    git -C libvpx pull 2> /dev/null || git clone --depth 1 https://chromium.googlesource.com/webm/libvpx.git && \
    cd libvpx && \
    PATH="/tmp/bin:$PATH" ./configure --prefix="/tmp/ffmpeg_build" --disable-examples --disable-unit-tests --enable-vp9-highbitdepth --as=yasm && \
    PATH="/tmp/bin:$PATH" make -j$(nproc) && \
    make install

#libfdk-aac
RUN cd /tmp/ffmpeg_sources && \
    git -C fdk-aac pull 2> /dev/null || git clone --depth 1 https://github.com/mstorsjo/fdk-aac && \
    cd fdk-aac && \
    autoreconf -fiv && \
    ./configure --prefix="/tmp/ffmpeg_build" --disable-shared && \
    make -j$(nproc) && \
    make install

#libmp3lame
RUN cd /tmp/ffmpeg_sources && \
    wget -O lame-${LAME_VER}.tar.gz https://downloads.sourceforge.net/project/lame/lame/${LAME_VER}/lame-${LAME_VER}.tar.gz && \
    tar xzvf lame-${LAME_VER}.tar.gz && \
    cd lame-${LAME_VER} && \
    PATH="/tmp/bin:$PATH" ./configure --prefix="/tmp/ffmpeg_build" --bindir="/tmp/bin" --disable-shared --enable-nasm && \
    PATH="/tmp/bin:$PATH" make -j$(nproc) && \
    make install

#libopus
RUN cd /tmp/ffmpeg_sources && \
    git -C opus pull 2> /dev/null || git clone --depth 1 https://github.com/xiph/opus.git && \
    cd opus && \
    ./autogen.sh && \
    ./configure --prefix="/tmp/ffmpeg_build" --disable-shared && \
    make -j$(nproc) && \
    make install

#libaom
RUN cd /tmp/ffmpeg_sources && \
    git -C aom pull 2> /dev/null || git clone --depth 1 https://aomedia.googlesource.com/aom && \
    mkdir -p aom_build && \
    cd aom_build && \
    PATH="/tmp/bin:$PATH" cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="/tmp/ffmpeg_build" -DENABLE_SHARED=off -DENABLE_NASM=on ../aom && \
    PATH="/tmp/bin:$PATH" make -j$(nproc) && \
    make install

#libsvtav1
RUN cd /tmp/ffmpeg_sources && \
    git -C SVT-AV1 pull 2> /dev/null || git clone https://github.com/AOMediaCodec/SVT-AV1.git && \
    mkdir -p SVT-AV1/build && \
    cd SVT-AV1/build && \
    PATH="/tmp/bin:$PATH" cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="/tmp/ffmpeg_build" -DCMAKE_BUILD_TYPE=Release -DBUILD_DEC=OFF -DBUILD_SHARED_LIBS=OFF .. && \
    PATH="/tmp/bin:$PATH" make -j$(nproc) && \
    make install

#NVIDIA codec API
RUN cd /tmp/ffmpeg_sources && \
    git -C nv-codec-headers pull 2> /dev/null || git clone https://git.videolan.org/git/ffmpeg/nv-codec-headers -b ${NV_CODEC_HEADERS_VER} && \
    cd nv-codec-headers && \
    make -j$(nproc) && \
    make install PREFIX="/tmp/ffmpeg_build"

#libaribb24
RUN cd /tmp/ffmpeg_sources && \
    git clone https://github.com/nkoriyama/aribb24 && \
    cd aribb24 && \
    autoreconf -fiv && \
    ./configure --prefix="/tmp/ffmpeg_build" --enable-static --disable-shared && \
    make -j$(nproc) && \
    make install

#ffmpeg
RUN cd /tmp/ffmpeg_sources && \
	wget -O ffmpeg.tar.bz2 https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VER}.tar.bz2 && \
    tar xjvf ffmpeg.tar.bz2 && \
    cd ffmpeg-${FFMPEG_VER} && \
    PATH="/tmp/bin:/usr/local/cuda/bin:$PATH" PKG_CONFIG_PATH="/tmp/ffmpeg_build/lib/pkgconfig" ./configure \
      --prefix=/usr/local \
      --pkg-config-flags=--static \
      --extra-cflags="-I/tmp/ffmpeg_build/include" \
      --extra-ldflags="-L/tmp/ffmpeg_build/lib" \
      --enable-cuda-nvcc \
      --nvccflags="-gencode arch=compute_52,code=sm_52" \
      --enable-cuvid \
      --enable-nvenc \
      --enable-libnpp \
      --extra-cflags="-I/usr/local/cuda/include" \
      --extra-ldflags="-L/usr/local/cuda/lib64" \
      --extra-libs="-lpthread -lm" \
      --disable-shared \
      --enable-libaom \
      --enable-libass \
      --enable-libfdk-aac \
      --enable-libfreetype \
      --enable-libmp3lame \
      --enable-libopus \
      --enable-libtheora \
      --enable-libsvtav1 \
      --enable-libvorbis \
      --enable-libvpx \
      --enable-libx264 \
      --enable-libx265 \
      --enable-static \
      --enable-nonfree \
      --disable-debug \
      --disable-doc \
      --enable-libaribb24 \
      --enable-version3 \
      --enable-gpl \
      --enable-nonfree \
      --disable-debug \
      --disable-doc && \
    PATH="/tmp/bin:/usr/local/cuda/bin:$PATH" make -j$(nproc) && \
    make install

# remove unnecessary packages
RUN apt-get -y remove $DEV && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /tmp/ffmpeg_sources && \
    rm -rf /tmp/ffmpeg_build && \
    rm -rf /tmp/bin
