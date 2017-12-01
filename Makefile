CONFIG ?= config.yaml
SECRETS ?= secrets.yaml
GENERATED ?= .generated.yaml

KUBE_CPU ?= 2
KUBE_MEM ?= 8192

.PHONY: help start-all start-minikube start-servcies start-db
.DEFAULT_GOAL := help

help: ## Print this message and exit.
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%15s\033[0m : %s\n", $$1, $$2}' $(MAKEFILE_LIST)

start-all: start-minikube start-services start-db ## Start minikube and all services.

start-minikube: cmd-minikube cmd-kubectl ## Start local minikube environment.
	@minikube delete || true
	@minikube start --cpus $(KUBE_CPU) --memory $(KUBE_MEM)
	@minikube addons enable ingress
	@kubectl create secret docker-registry atsk8sregistrykey \
		--docker-username=$$(grep dockerUser $(SECRETS) | cut -d' ' -f2) \
		--docker-password=$$(grep dockerPassword $(SECRETS) | cut -d' ' -f2) \
		--docker-email=$$(grep dockerEmail $(SECRETS) | cut -d' ' -f2)

start-services: cmd-kops ## Apply the generated config to the k8s cluster.
	@kops toolbox template \
		--values $(CONFIG) \
		--values $(SECRETS) \
		--template templates \
		--logtostderr \
		--output $(GENERATED)
	@kubectl apply --filename $(GENERATED)

start-db: cmd-kubectl ## Create all database tables and users.
	@eval $$(minikube docker-env); \
		until $$(docker ps | grep --silent mariadb); do sleep 5; done; sleep 15; \
		CONTAINER="$$(docker ps | grep mariadb | awk '{print $$1}')"; \
		docker cp "$(CURDIR)/scripts/create_databases.sql" "$${CONTAINER}:/tmp"; \
		docker exec -it $${CONTAINER} bash -c "mysql -proot < /tmp/create_databases.sql"

cmd-%: # Check that a command exists.
	@: $(if $$(command -v ${*} 2>/dev/null),,$(error Please install "$*" first))