FROM python:3.12.11-alpine3.22

RUN apk add --no-cache \
    make \
    openssh-client \
    apache2-utils \
    sshpass

RUN pip install --no-cache-dir "ansible-core>=2.17.0,<2.18.0"

COPY requirements.yml /tmp/requirements.yml
RUN ansible-galaxy install -r /tmp/requirements.yml

WORKDIR /workspace
CMD ["make", "help"]
