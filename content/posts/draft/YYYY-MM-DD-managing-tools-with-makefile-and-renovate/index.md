---
title: "Managing tools with Makefile and Renovate"
date: 2025-03-10
draft: true
summary: |
  TODO
tags: ["Renovate", "Dependencies"]
authors:
  - "shanduur"
---

```Makefile
.PHONY: lint
lint: golangci-lint ## Run golangci-lint linter.
	$(GOLANGCI_LINT) run

##@ Dependencies

LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p $(LOCALBIN)

GOLANGCI_LINT ?= $(LOCALBIN)/golangci-lint
GOLANGCI_LINT_VERSION ?= v1.64.6

.PHONY: golangci-lint
golangci-lint: $(GOLANGCI_LINT)-$(GOLANGCI_LINT_VERSION) ## Download golangci-lint locally if necessary.
$(GOLANGCI_LINT)-$(GOLANGCI_LINT_VERSION): $(LOCALBIN)
	$(call go-install-tool,$(GOLANGCI_LINT),github.com/golangci/golangci-lint/cmd/golangci-lint,$(GOLANGCI_LINT_VERSION))
```

```Makefile
# go-install-tool will 'go install' any package with custom target and name of binary, if it doesn't exist
# $1 - target path with name of binary
# $2 - package url which can be installed
# $3 - specific version of package
define go-install-tool
@[ -f "$(1)-$(3)" ] || { \
set -e; \
package=$(2)@$(3) ;\
echo "Downloading $${package}" ;\
rm -f $(1) || true ;\
GOBIN=$(LOCALBIN) go install $${package} ;\
mv $(1) $(1)-$(3) ;\
} ;\
ln -sf $(1)-$(3) $(1)
endef
```


```Makefile
# renovate: datasource=github-tags depName=golangci/golangci-lint
GOLANGCI_LINT_VERSION ?= v1.64.6
```

```json
{
  "extends": ["config:recommended"],
  "customManagers": [
    {
      "customType": "regex",
      "fileMatch": ["^Makefile$"],
      "matchStrings": [
        "# renovate: datasource=(?<datasource>.*?) depName=(?<depName>.*?)( versioning=(?<versioning>.*?))?\\s[A-Z_]+\\s\\?=\\s(?<currentValue>\\S+)"
      ],
      "versioningTemplate": "{{#if versioning}}{{{versioning}}}{{else}}semver{{/if}}"
    }
  ]
}
```

[regex](https://regex101.com/r/hrkIWv/1)
