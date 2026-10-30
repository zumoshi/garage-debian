NFPM_VERSION := 2.48.0
NFPM_TARBALL := .tools/nfpm_$(NFPM_VERSION)_Linux_x86_64.tar.gz
NFPM := .tools/nfpm-$(NFPM_VERSION)/nfpm
TOOLS_IMAGE := garage-debian-tools
ACTIONLINT_IMAGE := rhysd/actionlint:1.7.12@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667
SHELL_SCRIPTS = $(shell git ls-files -z | xargs -0 awk 'FNR == 1 { if (/^#!.*\/(env )?(ba|da)?sh( |$$)/) print FILENAME; nextfile }')

.PHONY: build verify lint check tools-image

build: $(NFPM)
	ARCH=amd64 NFPM=$(CURDIR)/$(NFPM) ./build.sh

verify:
	./build.sh verify

lint: build tools-image
	docker run --rm -u $(shell id -u):$(shell id -g) -v $(CURDIR)/dist:/dist:ro $(TOOLS_IMAGE) \
		sh -c 'lintian --version && lintian --fail-on error,warning,info -I /dist/*.deb'

check: tools-image
	ci/check-no-private-keys.sh
	docker run --rm -v $(CURDIR):/repo:ro -w /repo $(ACTIONLINT_IMAGE)
	docker run --rm -v $(CURDIR):/repo:ro -w /repo $(TOOLS_IMAGE) shellcheck $(SHELL_SCRIPTS)

tools-image:
	docker build -q -t $(TOOLS_IMAGE) - <ci/tools.Dockerfile >/dev/null

$(NFPM_TARBALL):
	mkdir -p $(@D)
	curl -fsSL -o $@.part https://github.com/goreleaser/nfpm/releases/download/v$(NFPM_VERSION)/$(@F)
	mv $@.part $@

$(NFPM): $(NFPM_TARBALL) checksums/$(notdir $(NFPM_TARBALL)).sha256
	echo "$$(cat checksums/$(notdir $(NFPM_TARBALL)).sha256)  $<" | sha256sum -c - || { rm -f $<; exit 1; }
	mkdir -p $(@D)
	tar -xzf $< -C $(@D) nfpm
	touch $@
