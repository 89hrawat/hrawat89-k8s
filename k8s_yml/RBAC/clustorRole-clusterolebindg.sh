#!/bin/bash
set -e

USER_NAME=$1
NAMESPACE=${2:-default}

if [ -z "$USER_NAME" ]; then
    echo "Usage: $0 <username> [namespace]"
    exit 1
fi

echo "[1/7] Generating private key..."
openssl genrsa -out ${USER_NAME}.key 2048

echo "[2/7] Generating CSR..."
openssl req -new -key ${USER_NAME}.key -out ${USER_NAME}.csr -subj "/CN=${USER_NAME}/O=${USER_NAME}-group"

echo "[3/7] Creating Kubernetes CSR YAML..."
CSR_BASE64=$(cat ${USER_NAME}.csr | base64 | tr -d '\n')
cat <<EOF > ${USER_NAME}-csr.yaml
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${USER_NAME}-csr
spec:
  request: ${CSR_BASE64}
  signerName: kubernetes.io/kube-apiserver-client
  usages:
  - client auth
EOF

kubectl apply -f ${USER_NAME}-csr.yaml

echo "[4/7] Approving CSR..."
kubectl certificate approve ${USER_NAME}-csr

echo "[5/7] Extracting signed certificate..."
kubectl get csr ${USER_NAME}-csr -o jsonpath='{.status.certificate}' | base64 --decode > ${USER_NAME}.crt

echo "[6/7] Creating clusterRole and ClusterRoleBinding for Pod CRUD..."
cat <<EOF | kubectl apply -f -
apiVsersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata: 
  name: ${USER_NAME}-clusterrole
rules:
  - apiGroups: [""]
    resources: ["pods", "services"]
    verbs: ["get","list", "watch", "update", "patch", "create", "delete"]
  - apiGroups: ["apps"]
    resources: ["statefulsets", "daemonsets", "deployments"]
    verbs: ["get","list", "watch", "update", "patch", "create", "delete"] 
---
apiVsersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${USER_NAME}-clusterrolebinding
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: ${USER_NAME}
roleRef:                        #### only one roleRef is allowed in ClusterRoleBinding
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: ${USER_NAME}-clusterrole
EOF

echo "[7/7] Creating kubeconfig for the user..."
CLUSTER_NAME=$(kubectl config view --minify -o jsonpath='{.clusters[0].name}')
CLUSTER_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CLUSTER_CA=$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 --decode)

kubectl config --kubeconfig=${USER_NAME}.kubeconfig set-cluster ${CLUSTER_NAME} \
  --server=${CLUSTER_SERVER} \
  --certificate-authority=<(echo "$CLUSTER_CA") \
  --embed-certs=true

kubectl config --kubeconfig=${USER_NAME}.kubeconfig set-credentials ${USER_NAME} \
  --client-certificate=${USER_NAME}.crt \
  --client-key=${USER_NAME}.key \
  --embed-certs=true

kubectl config --kubeconfig=${USER_NAME}.kubeconfig set-context ${USER_NAME}-context \
  --cluster=${CLUSTER_NAME} \
  --namespace=${NAMESPACE} \
  --user=${USER_NAME}

kubectl config --kubeconfig=${USER_NAME}.kubeconfig use-context ${USER_NAME}-context

echo "✅ User '${USER_NAME}' created successfully!"
echo "Kubeconfig file: ${USER_NAME}.kubeconfig"
