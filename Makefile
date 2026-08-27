# Convenience wrapper around the manual steps documented in README.md.
# Run `make help` to list all available targets.

ISTIO_VERSION    ?= 1.29.1
ISTIO_PROFILE    ?= demo
NAMESPACE        ?= default
KUBE_CONTEXT     ?=
TF_DIR           ?= terraform
GATEWAY_HOST     ?= localhost
GATEWAY_PORT     ?= 80
REVIEWS_LABEL    ?= app=reviews
LOG_LEVEL        ?= debug
TRAFFIC_REQUESTS ?= 100

ISTIO_DIR := istio-$(ISTIO_VERSION)
ISTIOCTL  := $(ISTIO_DIR)/bin/istioctl
KUBECTL   := kubectl$(if $(KUBE_CONTEXT), --context=$(KUBE_CONTEXT),)

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this list of targets
	@grep -E '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

## -- 1. Provision the cluster ------------------------------------------------

.PHONY: docker-desktop
docker-desktop: ## Point kubectl at the local Docker Desktop cluster
	$(KUBECTL) config use-context docker-desktop

.PHONY: tf-apply
tf-apply: ## Provision the EKS cluster via Terraform
	cd $(TF_DIR) && terraform init && terraform apply -auto-approve

.PHONY: tf-kubeconfig
tf-kubeconfig: ## Point kubectl at the newly created EKS cluster
	cd $(TF_DIR) && aws eks --region $$(terraform output -raw region) update-kubeconfig --name $$(terraform output -raw cluster_name)

.PHONY: tf-destroy
tf-destroy: ## Destroy the EKS cluster
	cd $(TF_DIR) && terraform destroy -auto-approve

## -- 2. Install Istio ----------------------------------------------------------

.PHONY: istio-download
istio-download: ## Download istioctl + samples for ISTIO_VERSION (skipped if already present)
	@if [ ! -d "$(ISTIO_DIR)" ]; then \
		curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$(ISTIO_VERSION) sh -; \
	fi

.PHONY: istio-install
istio-install: istio-download ## Install the Istio control plane and enable sidecar injection
	$(ISTIOCTL) install --set profile=$(ISTIO_PROFILE) -y
	$(KUBECTL) label namespace $(NAMESPACE) istio-injection=enabled --overwrite

## -- 3. Deploy Bookinfo ----------------------------------------------------------

.PHONY: bookinfo-deploy
bookinfo-deploy: istio-download ## Deploy the Bookinfo sample application
	$(KUBECTL) apply -n $(NAMESPACE) -f $(ISTIO_DIR)/samples/bookinfo/platform/kube/bookinfo.yaml

.PHONY: bookinfo-status
bookinfo-status: ## Show Bookinfo services and pods
	$(KUBECTL) get services -n $(NAMESPACE)
	$(KUBECTL) get pods -n $(NAMESPACE)

## -- 4. Expose the application ---------------------------------------------------

.PHONY: gateway-apply
gateway-apply: istio-download ## Deploy the Istio Ingress Gateway for Bookinfo
	$(KUBECTL) apply -n $(NAMESPACE) -f $(ISTIO_DIR)/samples/bookinfo/networking/bookinfo-gateway.yaml

.PHONY: gateway-url
gateway-url: ## Print the Bookinfo URL (auto-detects an EKS LoadBalancer, else falls back to GATEWAY_HOST:GATEWAY_PORT)
	@host=$$($(KUBECTL) -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null); \
	if [ -n "$$host" ]; then \
		port=$$($(KUBECTL) -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}'); \
		echo "http://$$host:$$port/productpage"; \
	else \
		echo "http://$(GATEWAY_HOST):$(GATEWAY_PORT)/productpage"; \
	fi

## -- 5. Showcase Istio & Envoy functionality --------------------------------------

.PHONY: routing-50-50
routing-50-50: istio-download ## Split reviews traffic 50/50 between v1 and v3
	$(KUBECTL) apply -n $(NAMESPACE) -f $(ISTIO_DIR)/samples/bookinfo/networking/destination-rule-all.yaml
	$(KUBECTL) apply -n $(NAMESPACE) -f $(ISTIO_DIR)/samples/bookinfo/networking/virtual-service-reviews-50-v3.yaml

.PHONY: fault-delay
fault-delay: istio-download ## Inject a 7s delay into ratings for user "jason"
	$(KUBECTL) apply -n $(NAMESPACE) -f $(ISTIO_DIR)/samples/bookinfo/networking/virtual-service-ratings-test-delay.yaml

.PHONY: proxy-config
proxy-config: ## Show listeners/routes/clusters/endpoints for a pod matching REVIEWS_LABEL
	@pod=$$($(KUBECTL) get pod -n $(NAMESPACE) -l $(REVIEWS_LABEL) -o jsonpath='{.items[0].metadata.name}'); \
	for kind in listeners routes clusters endpoints; do \
		echo "--- $$kind ---"; \
		$(ISTIOCTL) proxy-config $$kind -n $(NAMESPACE) $$pod; \
	done

.PHONY: proxy-status
proxy-status: ## Show xDS sync status between istiod and every Envoy proxy
	$(ISTIOCTL) proxy-status

.PHONY: log-level
log-level: ## Set connection/http Envoy log level (LOG_LEVEL) on a pod matching REVIEWS_LABEL
	@pod=$$($(KUBECTL) get pod -n $(NAMESPACE) -l $(REVIEWS_LABEL) -o jsonpath='{.items[0].metadata.name}'); \
	$(ISTIOCTL) proxy-config log -n $(NAMESPACE) $$pod --level connection:$(LOG_LEVEL),http:$(LOG_LEVEL)

.PHONY: access-logs
access-logs: ## Tail Envoy sidecar access logs for a pod matching REVIEWS_LABEL
	@pod=$$($(KUBECTL) get pod -n $(NAMESPACE) -l $(REVIEWS_LABEL) -o jsonpath='{.items[0].metadata.name}'); \
	$(KUBECTL) logs -n $(NAMESPACE) $$pod -c istio-proxy

.PHONY: addons-install
addons-install: istio-download ## Install the observability addons (Kiali, Grafana, Jaeger, Prometheus)
	$(KUBECTL) apply -f $(ISTIO_DIR)/samples/addons

.PHONY: traffic
traffic: ## Send TRAFFIC_REQUESTS sample requests through the gateway
	@host=$$($(KUBECTL) -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null); \
	if [ -n "$$host" ]; then \
		port=$$($(KUBECTL) -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}'); \
		url="http://$$host:$$port/productpage"; \
	else \
		url="http://$(GATEWAY_HOST):$(GATEWAY_PORT)/productpage"; \
	fi; \
	echo "Sending $(TRAFFIC_REQUESTS) requests to $$url"; \
	for i in $$(seq 1 $(TRAFFIC_REQUESTS)); do curl -s -o /dev/null "$$url"; done

.PHONY: kiali
kiali: istio-download ## Open the Kiali dashboard
	$(ISTIOCTL) dashboard kiali

.PHONY: grafana
grafana: istio-download ## Open the Grafana dashboard
	$(ISTIOCTL) dashboard grafana

.PHONY: jaeger
jaeger: istio-download ## Open the Jaeger dashboard
	$(ISTIOCTL) dashboard jaeger

## -- 6. Cleanup --------------------------------------------------------------------

.PHONY: cleanup-app
cleanup-app: istio-download ## Remove the Bookinfo app and its networking rules
	$(ISTIO_DIR)/samples/bookinfo/platform/kube/cleanup.sh

.PHONY: cleanup-istio
cleanup-istio: istio-download ## Uninstall Istio and remove the istio-system namespace
	$(ISTIOCTL) uninstall -y --purge
	$(KUBECTL) delete namespace istio-system --ignore-not-found

.PHONY: clean
clean: ## Remove the locally downloaded istioctl/samples directory
	rm -rf istio-*/
