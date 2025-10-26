#!/usr/bin/env bash

set -euo pipefail  # Exit on error, undefined vars, and pipeline failures

# Configuration
CONTAINER_NAME="${1:-my_container}"  # Allow override via first argument
CONTAINER_IP_ADDRESS="192.168.15.1/24"  # Added subnet mask
CONTAINER_VETH_NAME="veth-${CONTAINER_NAME}"
VIRTUAL_NETWORK_NAME="v-net-0"
PEER_NAME="${CONTAINER_VETH_NAME}-peer"  # Added consistent peer naming

# Helper function for error handling
function cleanup() {
    echo "Cleaning up resources..."
    ip netns del "$CONTAINER_NAME" 2>/dev/null || true
    ip link del "$VIRTUAL_NETWORK_NAME" 2>/dev/null || true
}

# Setup error handling
trap cleanup ERR

echo "Creating container network environment..."

# Check if network namespace already exists
if ip netns list | grep -q "$CONTAINER_NAME"; then
    echo "Network namespace $CONTAINER_NAME already exists. Cleaning up..."
    cleanup
fi

# Create a network namespace
echo "Creating network namespace: $CONTAINER_NAME"
ip netns add "$CONTAINER_NAME"

# Create virtual ethernet pair
echo "Creating veth pair: $CONTAINER_VETH_NAME <--> $PEER_NAME"
ip link add "$CONTAINER_VETH_NAME" type veth peer name "$PEER_NAME"

# Move one end to the namespace
echo "Moving $CONTAINER_VETH_NAME to container namespace"
ip link set "$CONTAINER_VETH_NAME" netns "$CONTAINER_NAME"

# Configure container interface
echo "Configuring container interface"
ip netns exec "$CONTAINER_NAME" ip addr add "$CONTAINER_IP_ADDRESS" dev "$CONTAINER_VETH_NAME"
ip netns exec "$CONTAINER_NAME" ip link set "$CONTAINER_VETH_NAME" up
ip netns exec "$CONTAINER_NAME" ip link set lo up  # Don't forget loopback

# Create and configure bridge
echo "Creating virtual network bridge: $VIRTUAL_NETWORK_NAME"
ip link add "$VIRTUAL_NETWORK_NAME" type bridge
ip link set dev "$VIRTUAL_NETWORK_NAME" up

# Connect peer to bridge
echo "Connecting peer interface to bridge"
ip link set "$PEER_NAME" master "$VIRTUAL_NETWORK_NAME"
ip link set "$PEER_NAME" up

echo "Container network setup completed successfully!"
echo "Container IP: $CONTAINER_IP_ADDRESS"
echo "To execute commands in container: ip netns exec $CONTAINER_NAME COMMAND"
