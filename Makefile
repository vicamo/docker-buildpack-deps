SHELL := /bin/bash

ifneq ($(strip $(V)),)
  hide :=
else
  hide := @
endif

LATEST := jessie

DOCKER ?= docker
DOCKER_REPO := buildpack-deps
DOCKER_USER := $(shell $(DOCKER) info | awk '/^Username:/ { print $$2 }')

# $(1): relative directory path, e.g. "jessie/amd64"
define target-name-from-path
$(subst /,-,$(1))
endef

# $(1): relative directory path, e.g. "jessie/amd64"
define suite-name-from-path
$(word 1,$(subst /, ,$(1)))
endef

# $(1): relative directory path, e.g. "jessie/amd64"
define arch-name-from-path
$(word 2,$(subst /, ,$(1)))
endef

# $(1): relative directory path, e.g. "jessie/amd64/curl"
define func-name-from-path
$(word 3,$(subst /, ,$(1)))
endef

# $(1): relative directory path, e.g. "jessie/amd64"
define base-image-from-path
$(shell cat $(1)/Dockerfile | grep ^FROM | awk '{print $$2}')
endef

# $(1): base image name, e.g. "foo/bar:tag"
define enumerate-build-dep-for-docker-build-inner
$(if $(filter $(DOCKER_USER)/$(DOCKER_REPO):%,$(1)),$(patsubst $(DOCKER_USER)/$(DOCKER_REPO):%,%,$(1)))
endef

# $(1): relative directory path, e.g. "jessie/amd64", "jessie/amd64/scm"
define enumerate-build-dep-for-docker-build
$(call enumerate-build-dep-for-docker-build-inner,$(call base-image-from-path,$(1)))
endef

# $(1): suite
# $(2): arch
# $(3): func
define enumerate-additional-tags-for
$(if $(filter amd64,$(2)),$(1)$(if $(3),-$(3))) $(if $(filter $(LATEST),$(1)),latest-$(2)$(if $(3),-$(3)) $(if $(filter amd64,$(2)),latest$(if $(3),-$(3))))
endef

define do-docker-build
@echo "$@ <= docker building $(PRIVATE_PATH)";
$(hide) if [ -n "$(FORCE)" -o -z "$$($(DOCKER) inspect $(DOCKER_USER)/$(DOCKER_REPO):$(PRIVATE_TARGET) 2>/dev/null | grep Created)" ]; then \
  $(DOCKER) build -t $(DOCKER_USER)/$(DOCKER_REPO):$(PRIVATE_TARGET) $(PRIVATE_PATH); \
fi

endef

# $(1): relative directory path, e.g. "jessie/amd64", "jessie/amd64/scm"
# $(2): target name, e.g. jessie-amd64-scm
# $(3): suite name, e.g. jessie
# $(4): arch name, e.g. amd64
# $(5): func name, e.g. scm
define define-docker-build-target
.PHONY: docker-build-$(2)
$(2): docker-build-$(2)
docker-build-$(2): PRIVATE_TARGET := $(2)
docker-build-$(2): PRIVATE_PATH := $(1)
docker-build-$(2): $(call enumerate-build-dep-for-docker-build,$(1))
	$$(call do-docker-build)

endef

define do-docker-tag
@echo "$@ <= docker tagging $(PRIVATE_PATH)";
$(hide) for tag in $(PRIVATE_TAGS); do \
  $(DOCKER) tag -f $(DOCKER_USER)/$(DOCKER_REPO):$(PRIVATE_TARGET) $(DOCKER_USER)/$(DOCKER_REPO):$${tag}; \
done

endef

# $(1): relative directory path, e.g. "jessie/amd64", "jessie/amd64/scm"
# $(2): target name, e.g. jessie-amd64-scm
# $(3): suite name, e.g. jessie
# $(4): arch name, e.g. amd64
# $(5): func name, e.g. scm
define define-docker-tag-target
.PHONY: docker-tag-$(2)
$(2): docker-tag-$(2)
docker-tag-$(2): PRIVATE_TARGET := $(2)
docker-tag-$(2): PRIVATE_PATH := $(1)
docker-tag-$(2): PRIVATE_TAGS := $(call enumerate-additional-tags-for,$(3),$(4),$(5))
docker-tag-$(2): docker-build-$(2)
	$$(call do-docker-tag)

endef

# $(1): relative directory path, e.g. "jessie/amd64", "jessie/amd64/scm"
define define-target-from-path
$(eval target := $(call target-name-from-path,$(1)))
$(eval suite := $(call suite-name-from-path,$(1)))
$(eval arch := $(call arch-name-from-path,$(1)))
$(eval func := $(call func-name-from-path,$(1)))

.PHONY: $(target) $(suite) $(arch) $(func)
all: $(target)
$(suite): $(target)
$(arch): $(target)
$(if $(func),$(func): $(target))
$(target):
	@echo "$$@ done"

$(call define-docker-build-target,$(1),$(target),$(suite),$(arch),$(func))
$(if $(strip $(call enumerate-additional-tags-for,$(suite),$(arch),$(func))), \
  $(call define-docker-tag-target,$(1),$(target),$(suite),$(arch),$(func)))

endef

all:
	@echo "Build $(DOCKER_USER)/$(DOCKER_REPO) done"

$(foreach f,$(shell find . -type f -name Dockerfile | cut -d/ -f2-), \
  $(eval path := $(patsubst %/Dockerfile,%,$(f))) \
  $(if $(wildcard $(path)/skip), \
    $(info Skipping $(path): $(shell cat $(path)/skip)), \
    $(eval $(call define-target-from-path,$(path))) \
  ) \
)

.PHONY: debian ubuntu
debian: wheezy jessie stretch sid
ubuntu: precise trusty vivid wily
