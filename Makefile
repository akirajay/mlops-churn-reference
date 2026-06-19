ENV ?= dev
LAB ?= 01

.PHONY: install lab-whatif lab-deploy lab-verify lab-clean

install:
	uv sync

lab-whatif:
	az deployment group what-if -g rg-churn-$(ENV) \
	  -f infra/main.bicep -p infra/env/$(ENV).bicepparam

lab-deploy:
	az deployment group create -g rg-churn-$(ENV) \
	  -f infra/main.bicep -p infra/env/$(ENV).bicepparam

lab-verify:
	uv run pytest labs/$(LAB)-*/verify -v --env=$(ENV)

lab-clean:
	az group delete -n rg-churn-$(ENV) --yes --no-wait
