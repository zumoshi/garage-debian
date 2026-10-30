FROM debian:trixie@sha256:4c25275446ca371766b8b093c696782eabce06263fccacb8d5d813b3dc44b308
RUN apt-get update \
	&& apt-get install -y --no-install-recommends lintian shellcheck \
	&& rm -rf /var/lib/apt/lists/*
