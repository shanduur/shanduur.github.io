---
title: "OpenTofu in GitHub Actions"
date: 2025-03-10
draft: true
summary: |
  TODO
tags: ["OpenTofu"]
authors:
  - "shanduur"
---

## Full example

```yaml
name: tofu

on:
  push:
    branches:
      - "main"
  schedule:
    - cron: "0 4 * * *"

concurrency:
  group: ${{ github.workflow }}

jobs:
  org:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: opentofu/setup-opentofu@v1
      - env:
          PAT: ${{ secrets.PAT }}
          PG_CONN_STR: ${{ secrets.PG_CONN_STR }}
        run: |
          tofu init -upgrade
      - env:
          PAT: ${{ secrets.PAT }}
          PG_CONN_STR: ${{ secrets.PG_CONN_STR }}
        run: |
          GITHUB_TOKEN="${PAT}" tofu \
            apply -auto-approve -input=false -lock=true -no-color
```

```terraform
terraform {
  required_version = ">= 1.8"

  backend "pg" {
    schema_name = "example_schema_name"
  }
}
```

## Database

## Pitfalls

* Deleting resources
* `GITHUB_TOKEN="${PAT}" tofu`
