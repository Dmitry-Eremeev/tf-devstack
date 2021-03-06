#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"
source "$my_dir/../common/common.sh"
source "$my_dir/../common/functions.sh"
source "$my_dir/../common/stages.sh"
source "$my_dir/../common/collect_logs.sh"

init_output_logging

# stages declaration

declare -A STAGES=( \
    ["all"]="build k8s manifest tf wait logs" \
    ["default"]="k8s manifest tf wait" \
    ["master"]="build k8s manifest tf wait" \
    ["platform"]="k8s" \
)

# constants
export DEPLOYER='k8s_manifests'
# max wait in seconds after deployment
export WAIT_TIMEOUT=600
DEPLOYER_IMAGE="contrail-k8s-manifests"
DEPLOYER_DIR="contrail-container-builder"
AGENT_LABEL="node-role.opencontrail.org/agent="

# default env variables

KUBE_MANIFEST=${KUBE_MANIFEST:-$WORKSPACE/$DEPLOYER_DIR/kubernetes/manifests/contrail-standalone-kubernetes.yaml}
CONTRAIL_POD_SUBNET=${CONTRAIL_POD_SUBNET:-"10.32.0.0/12"}
CONTRAIL_SERVICE_SUBNET=${CONTRAIL_SERVICE_SUBNET:-"10.96.0.0/12"}

# stages

# deployment related environment set by any stage and put to tf_stack_profile at the end
declare -A DEPLOYMENT_ENV

function build() {
    "$my_dir/../common/dev_env.sh"
}

function logs() {
    local errexit_state=$(echo $SHELLOPTS| grep errexit | wc -l)
    set +e

    create_log_dir
    collect_system_stats
    collect_contrail_status
    collect_docker_logs
    collect_kubernetes_objects_info
    collect_kubernetes_logs
    collect_contrail_logs

    tar -czf ${WORKSPACE}/logs.tgz -C ${TF_LOG_DIR}/.. logs
    rm -rf $TF_LOG_DIR

    # Restore errexit state
    if [[ $errexit_state == 1 ]]; then
        set -e
    fi
}

function k8s() {
    export K8S_NODES=$AGENT_NODES
    export K8S_MASTERS=$CONTROLLER_NODES
    export K8S_POD_SUBNET=$CONTRAIL_POD_SUBNET
    export K8S_SERVICE_SUBNET=$CONTRAIL_SERVICE_SUBNET
    $my_dir/../common/deploy_kubespray.sh
}

function manifest() {
    fetch_deployer
    export CONTRAIL_REGISTRY=$CONTAINER_REGISTRY
    export CONTRAIL_CONTAINER_TAG=$CONTRAIL_CONTAINER_TAG
    export HOST_IP=$NODE_IP
    export JVM_EXTRA_OPTS="-Xms1g -Xmx2g"
    export LINUX_DISTR=$DISTRO
    export KUBERNETES_PUBLIC_FIP_POOL="{'project' : 'k8s-default', 'domain': 'default-domain', 'name': '__fip_pool_public__' , 'network' : '__public__'}"
    $WORKSPACE/$DEPLOYER_DIR/kubernetes/manifests/resolve-manifest.sh $KUBE_MANIFEST > contrail.yaml
}

function tf() {
    ensure_insecure_registry_set $CONTAINER_REGISTRY
    ensure_kube_api_ready

    # label nodes
    labels=( $(grep "key: \"node-role." contrail.yaml | tr -s [:space:] | sort -u | cut -d: -f2 | tr -d \") )
    label_nodes_by_ip $AGENT_LABEL $AGENT_NODES
    for label in ${labels[@]}
    do
        label_nodes_by_ip "$label=" $CONTROLLER_NODES
    done

    # apply manifests
    kubectl apply -f contrail.yaml

    # show results
    echo "Contrail Web UI will be available at https://$NODE_IP:8143"
    echo "Use admin/contrail123 to log in"
}

# This is_active function is called in wait stage defined in common/stages.sh
function is_active() {
    check_pods_active && check_tf_active
}

function collect_deployment_env() {
    # no additinal info is needed
    :
}

run_stages $STAGE
