# Garry's Mod dedicated server (TTT) – Debian Bullseye (glibc 2.31)
FROM debian:bullseye-slim

LABEL description="Garry's Mod dedicated server (TTT) – Debian Bullseye (glibc 2.31)"
LABEL maintainer="EinsPhoenix"

ENV DEBIAN_FRONTEND=noninteractive

# Install required (32-bit) libs for srcds_linux + steamcmd
RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get -y --no-install-recommends --no-install-suggests install \
        wget ca-certificates tar \
        lib32gcc-s1 libgcc-s1 \
        libcurl4-gnutls-dev:i386 libcurl4:i386 libcurl3-gnutls:i386 \
        libssl1.1 libssl1.1:i386 \
        libtinfo5 libtinfo5:i386 libncurses5:i386 \
        lib32z1 lib32stdc++6 \
        libsdl2-2.0-0:i386 libfontconfig1 \
        net-tools coreutils \
        xz-utils \
        rsync \
 && apt-get clean \
 && rm -rf /tmp/* /var/lib/apt/lists/*

# Steam user
RUN useradd -d /home/gmod -m steam
USER steam
RUN mkdir -p /home/gmod/server /home/gmod/steamcmd

# SteamCMD
RUN wget -P /home/gmod/steamcmd/ https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
 && tar -xvzf /home/gmod/steamcmd/steamcmd_linux.tar.gz -C /home/gmod/steamcmd \
 && rm -f /home/gmod/steamcmd/steamcmd_linux.tar.gz

# Download GMod dedicated server (app 4020)
COPY assets/update.txt /home/gmod/update.txt
RUN /home/gmod/steamcmd/steamcmd.sh +runscript /home/gmod/update.txt +quit || true \
 && /home/gmod/steamcmd/steamcmd.sh +runscript /home/gmod/update.txt +quit

# CSS content (needed by many TTT maps)
RUN /home/gmod/steamcmd/steamcmd.sh +force_install_dir /home/gmod/temp +login anonymous +app_update 232330 validate +quit || true \
 && /home/gmod/steamcmd/steamcmd.sh +force_install_dir /home/gmod/temp +login anonymous +app_update 232330 validate +quit \
 && mkdir -p /home/gmod/mounts \
 && mv /home/gmod/temp/cstrike /home/gmod/mounts/cstrike \
 && rm -rf /home/gmod/temp

# Steam client SDK symlinks (32 + 64 bit)
RUN mkdir -p /home/gmod/.steam/sdk32 /home/gmod/.steam/sdk64 \
 && cp -v /home/gmod/steamcmd/linux32/steamclient.so /home/gmod/.steam/sdk32/steamclient.so \
 && cp -v /home/gmod/steamcmd/linux64/steamclient.so /home/gmod/.steam/sdk64/steamclient.so

# Mount config + sv.db + cache dirs
RUN echo '"mountcfg" {"cstrike" "/home/gmod/mounts/cstrike"}' > /home/gmod/server/garrysmod/cfg/mount.cfg \
 && touch /home/gmod/server/garrysmod/sv.db \
 && mkdir -p /home/gmod/server/steam_cache/content /home/gmod/server/garrysmod/cache/srcds

EXPOSE 27015 27015/udp 27005/udp

ENV MAXPLAYERS="16" \
    GAMEMODE="terrortown" \
    MAP="ttt_minecraft_b5" \
    MAPS="" \
    PORT="27015"

COPY --chown=steam:steam assets/start.sh /home/gmod/start.sh
COPY --chown=steam:steam assets/health.sh /home/gmod/health.sh
RUN chmod +x /home/gmod/start.sh /home/gmod/health.sh

HEALTHCHECK --start-period=60s CMD /home/gmod/health.sh

CMD ["/home/gmod/start.sh"]
