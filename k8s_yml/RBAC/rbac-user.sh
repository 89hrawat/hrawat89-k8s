 ##### Client side ##########
 pre-step
 
sudo useradd devops
sudo passwd devops
sudo mkdir -p /home/devops/.kube
sudo chown devops:devops /home/devops/.kube

##########this document to use add a user( as a clinet machine who want to perform kubectl opration a propiated permisson)
1. add a user on linux machine 
    # useradd devops /  and provide the password to devops user
	# su - devops
	
2. install kubctl clinet command to clinet machine by using link # https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
   $ sudo curl -LO https://dl.k8s.io/release/v1.33.0/bin/linux/amd64/kubectl
   ### Download the kubectl checksum file:
    $ curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
	$ sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
	$ kubectl version --client
3.  Generate Private Key for user
    $ openssl genrsa -out devops.key 2048
4. Generate CSR (Certificate Signing Request)
     $ openssl req -new -key devops.key -out devops.csr -subj "/CN=devops/O=devops-group"
	after then cerate csr send to file devops.csr to cluster admin to cerate crt with apropiate CA 
------------------------------------------------------------------------------------------------------------	
#### cluster admin side opration ##############
5.  Methode:1 Create Kubernetes CSR Object
CSR_BASE64=$(cat devops.csr | base64 | tr -d '\n') # this command convert the devops.csr to enform of base64 encode to variable CSR_BASE64

cat <<EOF > devops-csr.yaml
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: devops-csr
spec:
  request: ${CSR_BASE64}
  signerName: kubernetes.io/kube-apiserver-client
  usages:
  - client auth
EOF
 procdure:2 ## by using simle commad line
  sudo openssl x509 -req -in devops.csr \
  -CA /etc/kubernetes/pki/ca.crt \
  -CAkey /etc/kubernetes/pki/ca.key \
  -CAcreateserial \
  -out devops.crt \
  -days 365

6.    ####### apply the csr for CertificateSigning Request 
   kubectl apply -f devops-csr.yaml
7. to check the csr request status by command
   $ kubectl get csr

8. pproved the CSR.
  kubectl certificate approve <name of CSR>
  $ kubectl certificate approve devops-csr
9. to verify the csr status and details 
  $ kubectl describe csr <csr-name>
10. Extract Signed Certificate
  kubectl get csr devops-csr -o jsonpath='{.status.certificate}' | base64 --decode > devops.crt
################
11 check who you are
 # kubectl auth whoami
12  to check if you have access to a particular resource
kubectl auth can-i create <name  of the resource> --as <name of the user>
kubectl  auth can-i create pod --as devops

#################	flow  digram ###############


+-------------------------+
|      Kubernetes RBAC    |
|  (apiGroup: rbac.*)     |
+-------------------------+
          |
          | (defines access rules)
          v
+-------------------------+      +------------------------+
|   Role / ClusterRole    | ---> |   Resources in other   |
| (rbac.authorization.*)  |      |   API groups           |
+-------------------------+      +------------------------+
          ^
          | (binding user/group to Role)
          |
+-------------------------+
| RoleBinding / ClustRB   |
| (rbac.authorization.*)  |
+-------------------------+
          ^
          |
+-------------------------+
| Subjects (User, Group,  |
| ServiceAccount)         |
+-------------------------+
          ^            
          |
+-------------------------+
| roleRef                 |
|  apiGroup: rbac         | 
|  kind: Role             | 
|  name: devops-role       |
+-------------------------+           
##############################

###############RoleBinding in devops namespace but subject in another namespace ##### it only happed in servieAccount 
metadata:
  namespace: devops
subjects:
  - kind: ServiceAccount
    name: ci-runner
    namespace: cicd
➡ This means: the ServiceAccount ci-runner in cicd namespace gets access to resources in the devops namespace.

✅ Summary

RoleBinding.metadata.namespace → defines where the permissions apply.

subjects[].namespace (for ServiceAccounts only) → defines which exact ServiceAccount identity gets those permissions.

That’s why it’s mandatory for ServiceAccounts but not for Users/Groups (since they’re cluster-wide).





















kubectl config set-credentials devops \
  --client-certificate=devops.crt \
  --client-key=devops.key \
  --certificate-authority=ca.crt \
  --embed-certs=true
  
  kubectl config set-cluster kind-my-cluster \
  --server=https://127.0.0.1:34439 \
  --certificate-authority=ca.crt \
  --embed-certs=true \
  --kubeconfig=~/.kube/config
  
  
  kubectl config set-context devops@kind-dev-context \
  --cluster=kind-dev \
  --user=devops \
  --namespace=default
  
  
  
  
  
  
  
##########################################Script for user create on cluster ############
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

echo "[6/7] Creating Role and RoleBinding for Pod CRUD..."
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: ${NAMESPACE}
  name: ${USER_NAME}-pod-crud-role
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["create", "get", "list", "watch", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  namespace: ${NAMESPACE}
  name: ${USER_NAME}-pod-crud-binding
subjects:
  - kind: User
    name: ${USER_NAME}
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: ${USER_NAME}-pod-crud-role
  apiGroup: rbac.authorization.k8s.io
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




#################### on clinet side #################
# it will provide three file 
    1. devops.key ## private key
	2. devops.crt ### certificate of client devops user 
	3.   ### clinet kuebconfig file 
# pre recomenet step ~/#HOME/.kube file existe if not present the perform that step
   ssh devops@<client-machine-ip>
   mkdir -p ~/.kube
   mv ~/config ~/.kube/config   # copy the content of devops.kubeconfig file to config file by $ cp devops.kubeconfig ~/.kube/config
   chmod 600 ~/.kube/config
# Set KUBECONFIG environment variable # if you don't want to overide the file  $ ~/.kube/config then do 
   export KUBECONFIG=/path/to/devops.kubeconfig
   kubectl get pods
    Add that export line to ~/.bashrc or ~/.zshrc for persistence.
# Multi-context usage (if client already has another cluster config)
  If the client already uses Kubernetes for other clusters, instead of replacing ~/.kube/config, merge the configs:
   KUBECONFIG=~/.kube/config:/path/to/devops.kubeconfig kubectl config view --merge --flatten > /tmp/config && mv /tmp/config ~/.kube/config

