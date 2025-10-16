FROM debian:12.12

ARG USER_NAME
ARG USER_HOME

RUN apt-get update && \
    apt-get -y install borgbackup ssh

RUN adduser $USER_NAME --home $USER_HOME
USER ${USER_NAME}
ENV PATH=${USER_HOME}/bin:$PATH
