FROM alpine:3

WORKDIR /root
USER root:root

ARG WRK_USER_ID=1111
ARG WRK_USER_NAME=wrkuser
ARG WRK_USER_SHELL=/bin/zsh
ARG WRK_USER_HOME_DIR=/home/$WRK_USER_NAME

ARG WRK_GROUP_ID=1111
ARG WRK_GROUP_NAME=wrkgroup

RUN set -xeuo pipefail \
    && apk add --no-cache \
        vim git zsh \
        libgcc libstdc++ \
        pkgconfig shadow ca-certificates \
        bash curl wget sudo less procps file \
    \
    # create wrkuser && wrkgroup
    && groupadd --gid "${WRK_GROUP_ID}" ${WRK_GROUP_NAME} \
    && adduser \
        --gecos "" \
        --disabled-password \
        --uid "${WRK_USER_ID}" \
        --shell "${WRK_USER_SHELL}" \
        --ingroup ${WRK_GROUP_NAME} \
        --home "${WRK_USER_HOME_DIR}" \
    ${WRK_USER_NAME} \
    && usermod --password "*" ${WRK_USER_NAME} \
    && chfn --full-name ${WRK_USER_NAME} ${WRK_USER_NAME} \
    && mkdir -p /etc/sudoers.d \
    && printf '%s ALL=(ALL) NOPASSWD:ALL\n' "${WRK_USER_NAME}" > "/etc/sudoers.d/${WRK_USER_NAME}" \
    && chmod 0440 "/etc/sudoers.d/${WRK_USER_NAME}" \
    && visudo -cf "/etc/sudoers.d/${WRK_USER_NAME}" \
    \
    && printf '#!/bin/sh\nprintf "%s\n" "Skipping browser open in container: $*" >&2\nexit 0\n' > /usr/local/bin/xdg-open \
    && chmod 0755 /usr/local/bin/xdg-open \
    \
    # finish
    && set +xeuo pipefail



WORKDIR "$WRK_USER_HOME_DIR"
USER "$WRK_USER_NAME:$WRK_GROUP_NAME"

ENV HOME=$WRK_USER_HOME_DIR
ENV PATH=$WRK_USER_HOME_DIR/.opencode/bin:$PATH

ENV XDG_DATA_HOME=$WRK_USER_HOME_DIR/.local/share
ENV XDG_CACHE_HOME=$WRK_USER_HOME_DIR/.cache
ENV XDG_CONFIG_HOME=$WRK_USER_HOME_DIR/.config

RUN set -xeuo pipefail \
    && mkdir -p \
        "$XDG_DATA_HOME/opencode" \
        "$XDG_CACHE_HOME/opencode" \
        "$XDG_CONFIG_HOME/opencode" \
    \
    && curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path \
    && set +xeuo pipefail


WORKDIR /root
USER root:root
RUN set -xeuo pipefail \
    # Do not install openssh-client here: sandboxed agents are allowed to act
    # freely inside the container and should not have any SSH acceess by default.
    && apk add --no-cache \
        jq \
        just \
        file \
        ripgrep \
        python3 \
        py3-yaml \
    \
    && set +xeuo pipefail

WORKDIR "$WRK_USER_HOME_DIR"
USER "$WRK_USER_NAME:$WRK_GROUP_NAME"

CMD ["opencode"]
