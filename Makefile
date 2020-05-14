
SHELL := /bin/bash


export GITHUB_USER    := $(shell echo $(GITHUB_USER) | sed 's/@/%40/g')
export GITHUB_TOKEN   ?=

export ARCH       ?= $(shell uname -m)
export ARCH_TYPE   = $(if $(patsubst x86_64,,$(ARCH)),$(ARCH),amd64)
export BUILD_DATE  = $(shell date +%m/%d@%H:%M:%S)

export CGO_ENABLED  = 0
export GO111MODULE := on
export GOOS         = $(shell go env GOOS)
export GOARCH       = $(ARCH_TYPE)
export GOPACKAGES   = $(shell go list ./... | grep -v /vendor | grep -v /build | grep -v /test)

export PROJECT_DIR            = $(shell 'pwd')
export BUILD_DIR              = $(PROJECT_DIR)/build
export DOCKER_BUILD_PATH      = $(PROJECT_DIR)/.build-docker
export COMPONENT_SCRIPTS_PATH = $(BUILD_DIR)

## WARNING: OPERATOR-SDK - IMAGE_DESCRIPTION & DOCKER_BUILD_OPTS MUST NOT CONTAIN ANY SPACES
export COMPONENT_NAME ?= $(shell cat ./COMPONENT_NAME 2> /dev/null)
export COMPONENT_VERSION ?= $(shell cat ./COMPONENT_VERSION 2> /dev/null)

export IMAGE_DESCRIPTION ?= Klusterlet_Operator
export DOCKER_FILE        = $(BUILD_DIR)/Dockerfile
export DOCKER_REGISTRY   ?= quay.io
export DOCKER_NAMESPACE  ?= open-cluster-management
export DOCKER_IMAGE      ?= $(COMPONENT_NAME)
export DOCKER_BUILD_TAG  ?= latest
export DOCKER_TAG        ?= $(shell whoami)

export DOCKER_BUILD_OPTS  = --build-arg REMOTE_SOURCE=. \
	--build-arg REMOTE_SOURCE_DIR=/remote-source \
	--build-arg GITHUB_TOKEN=$(GITHUB_TOKEN) \
	--build-arg VCS_REF=$(VCS_REF) \
	--build-arg VCS_URL=$(GIT_REMOTE_URL) \
	--build-arg IMAGE_NAME=$(DOCKER_IMAGE) \
	--build-arg IMAGE_DESCRIPTION=$(IMAGE_DESCRIPTION) \
	--build-arg IMAGE_VERSION=$(SEMVERSION) \
	--build-arg COMPONENT_NAME=$(COMPONENT_NAME) \
	--build-arg COMPONENT_VERSION=$(COMPONENT_VERSION) \
	--build-arg ARCH_TYPE=$(ARCH_TYPE)

BEFORE_SCRIPT := $(shell build/before-make.sh)

USE_VENDORIZED_BUILD_HARNESS ?=

ifndef USE_VENDORIZED_BUILD_HARNESS
-include $(shell curl -s -H 'Authorization: token ${GITHUB_TOKEN}' -H 'Accept: application/vnd.github.v4.raw' -L https://api.github.com/repos/open-cluster-management/build-harness-extensions/contents/templates/Makefile.build-harness-bootstrap -o .build-harness-bootstrap; echo .build-harness-bootstrap)
else
-include vbh/.build-harness-vendorized
endif

# Only use git commands if it exists
ifdef GIT
GIT_COMMIT      = $(shell git rev-parse --short HEAD)
GIT_REMOTE_URL  = $(shell git config --get remote.origin.url)
VCS_REF     = $(if $(shell git status --porcelain),$(GIT_COMMIT)-$(BUILD_DATE),$(GIT_COMMIT))
endif

.PHONY: deps
## Download all project dependencies
deps: init component/init

.PHONY: check
## Runs a set of required checks
check: lint ossccheck copyright-check

.PHONY: test
## Runs go unit tests
test: component/test/unit

.PHONY: build
## Builds operator binary inside of an image
build: component/build
	

.PHONY: copyright-check
copyright-check:
	./build/copyright-check.sh $(TRAVIS_BRANCH)

.PHONY: clean
## Clean build-harness and remove Go generated build and test files
clean::
	@rm -rf $(BUILD_DIR)/_output
	@[ "$(BUILD_HARNESS_PATH)" == '/' ] || \
	 [ "$(BUILD_HARNESS_PATH)" == '.' ] || \
	   rm -rf $(BUILD_HARNESS_PATH)

.PHONY: run
## Run the operator against the kubeconfig targeted cluster
run:
	operator-sdk run --local --namespace="" --operator-flags="--zap-devel=true"

.PHONE: request-destruct
request-destruct:
	build/bin/self-destruct.sh

.PHONY: ossccheck
ossccheck:
	ossc --check

.PHONY: ossc
ossc:
	ossc

.PHONY: lint
## Runs linter against go files
lint:
	@echo "Running linting tool ..."
	@golangci-lint run --timeout 5m

.PHONY: helpz
helpz:
ifndef build-harness
	$(eval MAKEFILE_LIST := Makefile build-harness/modules/go/Makefile)
endif

### HELPER UTILS #######################

.PHONY: utils\crds\install
utils\crds\install:
	kubectl apply -f deploy/crds/agent.open-cluster-management.io_klusterlets_crd.yaml

.PHONY: utils\crds\uninstall
utils\crds\uninstall:
	kubectl delete -f deploy/crds/agent.open-cluster-management.io_klusterlets_crd.yaml

### FUNCTIONAL TESTS UTILS ###########

deploy:
	mkdir -p overlays/deploy
	cp overlays/template/kustomization.yaml overlays/deploy
	cd overlays/deploy
	kustomize build overlays/deploy | kubectl apply -f -
	rm -rf overlays/deploy

.PHONY: functional-test
functional-test: 
	ginkgo -v -tags functional -failFast --slowSpecThreshold=10 test/klusterlet-operator-test/... -- --v=5

.PHONY: functional-test-full
functional-test-full: build-coverage component/test/functional

.PHONY: build-coverage
## Builds operator binary inside of an image
build-coverage: 
	build/build-coverage.sh ${COMPONENT_DOCKER_REPO}/${COMPONENT_NAME}:${COMPONENT_VERSION}${COMPONENT_TAG_EXTENSION}-coverage
	
