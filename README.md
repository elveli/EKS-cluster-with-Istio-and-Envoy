# EKS Cluster with Istio and Envoy Showcase

This project provides Terraform code to provision an Amazon EKS cluster and instructions to deploy Istio (which uses Envoy under the hood) along with a sample application to showcase traffic routing, observability, and security.

## Architecture & Traffic Flow

The following diagram illustrates how the components interact in the cloud environment, from the user's initial request down to the individual components in the Bookinfo microservices.

```mermaid
graph TD
    User((User)) -->|HTTP Request| IngressGW

    Admin((Cluster Admin)) -->|kubectl / istioctl| EKSAPI[EKS API Server]
    EKSAPI --> Istiod

    subgraph "AWS Cloud (VPC)"
        subgraph "Amazon EKS Cluster"
            subgraph "namespace: istio-system"
                Istiod["Istiod (Control Plane)<br/>Manages config & certificates"]
                IngressGW["Istio Ingress Gateway (Envoy)<br/>Entrypoint for external traffic"]
            end

            subgraph "namespace: default (Bookinfo App)"
                ProductPage["productpage pod<br/>(App + Envoy Sidecar)"]
                Details["details pod<br/>(App + Envoy Sidecar)"]
                
                subgraph "reviews pods"
                    Reviews1["reviews-v1<br/>(App + Envoy Sidecar)"]
                    Reviews2["reviews-v2<br/>(App + Envoy Sidecar)"]
                    Reviews3["reviews-v3<br/>(App + Envoy Sidecar)"]
                end
                
                Ratings["ratings pod<br/>(App + Envoy Sidecar)"]
            end
            
            %% Control Plane connections (xDS)
            Istiod -.-|Push Envoy Config (xDS)| IngressGW
            Istiod -.-|Push Envoy Config (xDS)| ProductPage
            Istiod -.-|Push Envoy Config (xDS)| Details
            Istiod -.-|Push Envoy Config (xDS)| Reviews1
            Istiod -.-|Push Envoy Config (xDS)| Reviews2
            Istiod -.-|Push Envoy Config (xDS)| Reviews3
            Istiod -.-|Push Envoy Config (xDS)| Ratings
            
            %% Data Plane traffic flow
            IngressGW ==>|Routes traffic| ProductPage
            ProductPage ==>|Fetches details| Details
            ProductPage ==>|Fetches reviews| Reviews1
            ProductPage ==>|Fetches reviews| Reviews2
            ProductPage ==>|Fetches reviews| Reviews3
            Reviews2 ==>|Fetches ratings| Ratings
            Reviews3 ==>|Fetches ratings| Ratings
        end
    end

    classDef controlPlane fill:#e3f2fd,stroke:#1565c0,stroke-width:2px;
    classDef dataPlane fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px;
    classDef gw fill:#fff3e0,stroke:#e65100,stroke-width:2px;
    classDef admin fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px;

    class Istiod controlPlane;
    class ProductPage,Details,Reviews1,Reviews2,Reviews3,Ratings dataPlane;
    class IngressGW gw;
    class EKSAPI admin;
```

## 1. Provision the EKS Cluster

Navigate to the `terraform` directory and apply the configuration:

```bash
cd terraform
terraform init
terraform apply -auto-approve
```

Configure your local `kubectl` to connect to the new cluster:

```bash
aws eks --region $(terraform output -raw region) update-kubeconfig --name $(terraform output -raw cluster_name)
```

## 2. Install Istio

Download and install the Istio CLI (`istioctl`):

```bash
curl -L https://istio.io/downloadIstio | sh -
cd istio-*
export PATH=$PWD/bin:$PATH
```

Install Istio on the EKS cluster with the `demo` profile (good for showcasing):

```bash
istioctl install --set profile=demo -y
```

Label the default namespace to instruct Istio to automatically inject Envoy sidecar proxies when you deploy your application:

```bash
kubectl label namespace default istio-injection=enabled
```

## 3. Deploy the Sample Application (Bookinfo)

The Bookinfo app is a classic microservices example provided by Istio to showcase routing and Envoy proxies.

```bash
# Assuming you are still in the istio-* directory
kubectl apply -f samples/bookinfo/platform/kube/bookinfo.yaml
```

Verify the pods are running and have 2 containers each (the app container + the Envoy sidecar):

```bash
kubectl get services
kubectl get pods
```

## 4. Expose the Application

Deploy the Istio Ingress Gateway to allow external traffic into the mesh:

```bash
kubectl apply -f samples/bookinfo/networking/bookinfo-gateway.yaml
```

Get the external IP/URL of the Ingress Gateway:

```bash
export INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
export GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT

echo "Access the app at: http://$GATEWAY_URL/productpage"
```

## 5. Showcase Istio & Envoy Functionality

### A. Traffic Routing (Weight-based routing)

Route 50% of traffic to reviews v1 and 50% to reviews v3:

```bash
kubectl apply -f samples/bookinfo/networking/destination-rule-all.yaml
kubectl apply -f samples/bookinfo/networking/virtual-service-reviews-50-v3.yaml
```

### B. View Envoy Proxy Configuration

You can inspect the Envoy configuration generated by Istio for a specific pod using the `proxy-config` (or `pc`) wrappers:

```bash
# Get a reviews pod name
REVIEWS_POD=$(kubectl get pod -l app=reviews -o jsonpath='{.items[0].metadata.name}')

# View listeners, routes, clusters, and endpoints configured in Envoy
istioctl proxy-config listeners $REVIEWS_POD
istioctl proxy-config routes $REVIEWS_POD
istioctl proxy-config clusters $REVIEWS_POD
istioctl proxy-config endpoints $REVIEWS_POD
```

### C. Check Envoy Sync Status

Verify the synchronization status between the Istio Control Plane (istiod) and the Envoy proxies:

```bash
istioctl proxy-status
```

### D. Direct Envoy Admin API & Dashboard

Each Envoy proxy exposes a native Admin API on port `15000` inside the pod.

**1. Open the raw Envoy Admin UI in your browser:**
```bash
istioctl dashboard envoy $REVIEWS_POD
```

**2. Query the Envoy Admin API directly via port-forwarding:**
```bash
# Open port-forwarding in the background (or another terminal)
kubectl port-forward $REVIEWS_POD 15000:15000 &

# List all available Envoy admin endpoints
curl http://localhost:15000/help

# View Envoy internal metrics and stats
curl http://localhost:15000/stats

# Get a full JSON dump of the Envoy configuration
curl http://localhost:15000/config_dump
```

### E. View Envoy Access Logs

To see the traffic access logs from the Envoy sidecar proxy container:

```bash
kubectl logs $REVIEWS_POD -c istio-proxy
```

### F. Observability (Kiali & Jaeger)

Install the observability addons:

```bash
kubectl apply -f samples/addons
```

Access the Kiali dashboard to visualize the mesh:

```bash
istioctl dashboard kiali
```

## 6. Cleanup

```bash
# Remove the sample app
samples/bookinfo/platform/kube/cleanup.sh

# Uninstall Istio
istioctl uninstall -y --purge
kubectl delete namespace istio-system

# Destroy EKS Cluster
cd ../terraform
terraform destroy -auto-approve
```
