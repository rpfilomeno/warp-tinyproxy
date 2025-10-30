FROM ubuntu:22.04

LABEL org.opencontainers.image.authors="rpfilomeno"
LABEL org.opencontainers.image.url="https://github.com/rpfilomeno/warp-tinyproxy"
LABEL COMMIT_SHA=${COMMIT_SHA}

ENV WARP_SLEEP=2
ENV REGISTER_WHEN_MDM_EXISTS=
ENV WARP_LICENSE_KEY=
ENV BETA_FIX_HOST_CONNECTIVITY=
ENV WARP_ENABLE_NAT=

# The port which the Tinyproxy service will listen on.
ENV PORT="1080"
# Insert any value (preferably "yes") to disable the Via-header:
ENV DISABLE_VIA_HEADER=""
# Set this to e.g. tinyproxy.stats to enable stats-page on that address
ENV STAT_HOST=""
ENV MAX_CLIENTS=""
# A space separated list. If not set or is empty, all networks are allowed.
ENV ALLOWED_NETWORKS=""
# One of Critical, Error, Warning, Notice, Connect, Info
ENV LOG_LEVEL=""
# Maximum number of seconds idle connections are allowed to remain open
ENV TIMEOUT=""
# Username for BasicAuth
ENV AUTH_USER=""
# Password for BasicAuth (letters and digits only)
ENV AUTH_PASSWORD=""
# The preferred way for providing passwords. You can use e.g. docker-compose secrets for which this
# variable has been configured for by default. Alternatively, you could bind-mount the
# password-file manually and change this if necessary
ENV AUTH_PASSWORD_FILE="/run/secrets/auth_password"

# Use a custom UID/GID instead of the default system UID which has a greater possibility
# for collisions with the host and other containers.


COPY entrypoint.sh /entrypoint.sh
COPY ./healthcheck /healthcheck

# install dependencies
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y curl gnupg lsb-release sudo jq ipcalc && \
    curl https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list && \
    apt-get update && \
    apt-get install -y cloudflare-warp tinyproxy&& \
    apt-get clean && \
    apt-get autoremove

RUN chmod +x /entrypoint.sh && \
    chmod +x /healthcheck/index.sh && \
    useradd -m -s /bin/bash warp && \
    echo "warp ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/warp


USER warp

# Accept Cloudflare WARP TOS
RUN mkdir -p /home/warp/.local/share/warp && \
    echo -n 'yes' > /home/warp/.local/share/warp/accepted-tos.txt

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD /healthcheck/index.sh

ENTRYPOINT ["/entrypoint.sh"]
