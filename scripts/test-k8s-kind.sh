#!/usr/bin/env bash
# Test K8s executor with Kind (Kubernetes in Docker)
#
# This script:
# 1. Creates a Kind cluster with local registry
# 2. Runs the K8s executor test
# 3. Cleans up
#
# Usage:
#   ./scripts/test-k8s-kind.sh [shared|dedicated|matrix]

set -euo pipefail

MODE="${1:-shared}"
CLUSTER_NAME="nixactions-test"
REGISTRY_NAME="kind-registry"
REGISTRY_PORT="5001"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[nixactions]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[nixactions]${NC} $*" >&2; }
error() { echo -e "${RED}[nixactions]${NC} $*" >&2; }

cleanup() {
    log "Cleaning up..."
    kind delete cluster --name "$CLUSTER_NAME" 2>/dev/null || true
    docker rm -f "$REGISTRY_NAME" 2>/dev/null || true
    log "Cleanup complete"
}

# Trap for cleanup on exit
trap cleanup EXIT

# Check dependencies
check_deps() {
    log "Checking dependencies..."
    
    if ! command -v docker &> /dev/null; then
        error "docker is required but not installed"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        error "Docker daemon is not running"
        exit 1
    fi
    
    # We'll use nix-shell for kind and kubectl
    log "Dependencies OK (will use nix-shell for kind/kubectl)"
}

# Create local registry
create_registry() {
    log "Creating local registry on port $REGISTRY_PORT..."
    
    # Remove existing registry if any
    docker rm -f "$REGISTRY_NAME" 2>/dev/null || true
    
    # Start registry
    docker run -d \
        --restart=always \
        -p "127.0.0.1:${REGISTRY_PORT}:5000" \
        --name "$REGISTRY_NAME" \
        registry:2
    
    log "Registry started at localhost:$REGISTRY_PORT"
}

# Create Kind cluster with registry
create_cluster() {
    log "Creating Kind cluster '$CLUSTER_NAME'..."
    
    # Kind config with registry
    cat <<EOF | nix-shell -p kind --run "kind create cluster --name $CLUSTER_NAME --config=-"
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:${REGISTRY_PORT}"]
    endpoint = ["http://${REGISTRY_NAME}:5000"]
EOF
    
    # Connect registry to kind network
    if [ "$(docker inspect -f='{{json .NetworkSettings.Networks.kind}}' "${REGISTRY_NAME}")" = 'null' ]; then
        docker network connect "kind" "${REGISTRY_NAME}"
    fi
    
    # Document the local registry
    # https://kind.sigs.k8s.io/docs/user/local-registry/
    cat <<EOF | nix-shell -p kubectl --run "kubectl apply -f -"
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${REGISTRY_PORT}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF
    
    log "Kind cluster created and configured with local registry"
}

# Wait for cluster to be ready
wait_for_cluster() {
    log "Waiting for cluster to be ready..."
    
    nix-shell -p kubectl --run "kubectl wait --for=condition=Ready nodes --all --timeout=120s"
    
    log "Cluster is ready"
}

# Run the K8s test
run_test() {
    log "Running K8s executor test (mode: $MODE)..."
    
    # Set registry credentials (not actually used by local registry, but required by executor)
    export REGISTRY_USER="unused"
    export REGISTRY_PASSWORD="unused"
    
    # Run the example
    case "$MODE" in
        dedicated)
            nix run ".#example-test-k8s-dedicated"
            ;;
        matrix)
            log "Running matrix test with 10 parallel workers..."
            nix run ".#example-test-k8s-matrix-dedicated"
            ;;
        *)
            nix run ".#example-test-k8s-shared"
            ;;
    esac
    
    log "Test completed successfully!"
}

# Main
main() {
    log "=== NixActions K8s Executor Test ==="
    log "Mode: $MODE"
    log ""
    
    check_deps
    create_registry
    create_cluster
    wait_for_cluster
    run_test
    
    log ""
    log "=== All tests passed! ==="
}

main "$@"
