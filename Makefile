NFPM_VERSION := 2.48.0
NFPM_TARBALL := .tools/nfpm_$(NFPM_VERSION)_Linux_x86_64.tar.gz
NFPM := .tools/nfpm-$(NFPM_VERSION)/nfpm

.PHONY: build verify

build: $(NFPM)
	ARCH=amd64 NFPM=$(CURDIR)/$(NFPM) ./build.sh

verify:
	./build.sh verify

$(NFPM_TARBALL):
	mkdir -p $(@D)
	curl -fsSL -o $@.part https://github.com/goreleaser/nfpm/releases/download/v$(NFPM_VERSION)/$(@F)
	mv $@.part $@

$(NFPM): $(NFPM_TARBALL) checksums/$(notdir $(NFPM_TARBALL)).sha256
	echo "$$(cat checksums/$(notdir $(NFPM_TARBALL)).sha256)  $<" | sha256sum -c - || { rm -f $<; exit 1; }
	mkdir -p $(@D)
	tar -xzf $< -C $(@D) nfpm
	touch $@
