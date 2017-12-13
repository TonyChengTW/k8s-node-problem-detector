# Copyright 2017 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Build the node-problem-detector image.

.PHONY: all build-container build-tar build push-container push-tar push clean vet fmt version Dockerfile

all: build

# VERSION is the version of the binary.
VERSION:=$(shell git describe --tags --dirty)

# TAG is the tag of the container image, default to binary version.
TAG?=$(VERSION)

# PROJ is the image project.
PROJ?=gcr.io/google_containers

# UPLOAD_PATH is the cloud storage path to upload release tar.
UPLOAD_PATH?=gs://kubernetes-release
# Trim the trailing '/' in the path
UPLOAD_PATH:=$(shell echo $(UPLOAD_PATH) | sed '$$s/\/*$$//')

# PKG is the package name of node problem detector repo.
PKG:=k8s.io/node-problem-detector

# PKG_SOURCES are all the go source code.
PKG_SOURCES:=$(shell find pkg cmd -name '*.go')

# TARBALL is the name of release tar. Include binary version by default.
TARBALL:=node-problem-detector-$(VERSION).tar.gz

# IMAGE is the image name of the node problem detector container image.
IMAGE:=$(PROJ)/node-problem-detector:$(TAG)

# ENABLE_JOURNALD enables build journald support or not. Building journald support needs libsystemd-dev
# or libsystemd-journal-dev.
# TODO(random-liu): Build NPD inside container.
ENABLE_JOURNALD?=1

# TODO(random-liu): Support different architectures.
BASEIMAGE:=alpine:3.4

# Disable cgo by default to make the binary statically linked.
CGO_ENABLED:=0

# NOTE that enable journald will increase the image size.
ifeq ($(ENABLE_JOURNALD), 1)
	# Enable journald build tag.
	BUILD_TAGS:=-tags journald
	# Use fedora because it has newer systemd version (229) and support +LZ4. +LZ4 is needed
	# on some os distros such as GCI.
	BASEIMAGE:=fedora
	# Enable cgo because sdjournal needs cgo to compile. The binary will be dynamically
	# linked if CGO_ENABLED is enabled. This is fine because fedora already has necessary
	# dynamic library. We can not use `-extldflags "-static"` here, because go-systemd uses
	# dlopen, and dlopen will not work properly in a statically linked application.
	CGO_ENABLED:=1
endif

vet:
	go list ./... | grep -v "./vendor/*" | xargs go vet

fmt:
	find . -type f -name "*.go" | grep -v "./vendor/*" | xargs gofmt -s -w -l

version:
	@echo $(VERSION)

./bin/node-problem-detector: $(PKG_SOURCES)
	CGO_ENABLED=$(CGO_ENABLED) GOOS=linux go build -o bin/node-problem-detector \
	     -ldflags '-X $(PKG)/pkg/version.version=$(VERSION)' \
	     $(BUILD_TAGS) cmd/node_problem_detector.go

Dockerfile: Dockerfile.in
	sed -e 's|@BASEIMAGE@|$(BASEIMAGE)|g' $< >$@

test: vet fmt
	go test -timeout=1m -v -race ./pkg/... $(BUILD_TAGS)

build-container: ./bin/node-problem-detector Dockerfile
	docker build -t $(IMAGE) .

build-tar: ./bin/node-problem-detector
	tar -zcvf $(TARBALL) bin/ config/
	sha1sum $(TARBALL)
	md5sum $(TARBALL)

build: build-container build-tar

push-container: build-container
	gcloud docker -- push $(IMAGE)

push-tar: build-tar
	gsutil cp $(TARBALL) $(UPLOAD_PATH)/node-problem-detector/

push: push-container push-tar

clean:
	rm -f bin/node-problem-detector
	rm -f node-problem-detector-*.tar.gz
