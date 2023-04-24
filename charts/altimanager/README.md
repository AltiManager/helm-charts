# altimanager

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.1.0](https://img.shields.io/badge/AppVersion-0.1.0-informational?style=flat-square)

A Helm chart for Pharma Ledger altimanager (electronic product information) application

## Requirements

- [helm 3](https://helm.sh/docs/intro/install/)
- These mandatory configuration values:
  - Vault Domain - The Vault Domain - e.g. `vault.my-company`
  - bdnsHosts - The Centrally managed and provided BDNS Hosts Config
  - buildSecretKey - A secret pass phrase for de/encrpytion of the initially generated private keys of the wallets.

## Usage

- [Here](./README.md#values) is a full list of all configuration values.
- The [values.yaml file](./values.yaml) shows the raw view of all configuration values.

This helm chart uses Helm [hooks](https://helm.sh/docs/topics/charts_hooks/) in order to install, upgrade and manage the application and its resources.

```mermaid
sequenceDiagram
  participant PIN as pre-install
  participant PUP as pre-upgrade
  participant I as install
  participant U as uninstall
  participant PUN as post-uninstall
  note right of PUN: Note on resources marked with *:<br/>They are created on a helm hook<br/>and will not be deleted after execution<br/>but will be removed by Cleanup Job
  Note over PIN,PUN: PersistentVolumeClaim for Builder and Runner (B and R)*
  Note over PIN,PUN: ServiceAccount for B and R*
  note right of PUP: Note on upgrades:<br/>Pre-Builder and Builder jobs run<br/>1. if 'builder.forceRun: true'<br/>2. if builder image has changed
  Note over PUP:Pre-Builder Job*
  Note over PUP:Pre-Builder ServiceAccount
  Note over PUP:Pre-Builder Role
  Note over PUP:Pre-Builder RoleBinding
  Note over PIN,PUP:Builder Job*
  Note over PIN,PUP:Builder ConfigMaps Builder
  Note over PIN,PUP:Builder Secret (or SecretProviderClass)
  Note over I,U:Runner Deployment
  Note over I,U:Runner ConfigMaps
  Note over I,U:Runner Service
  Note over I,U:Runner Ingress
  Note over I,U:Runner Secret (or SecretProviderClass)
  Note over I,U:Build-Info ConfigMap
  note right of PUN: Note: Cleanup job deletes <br/>1. Pre-Builder Job<br/>2. Builder Job<br/>3. ServiceAccount for B and R<br/>4. PersistentVolumeClaim for B and R (optional)
  Note over PUN:Cleanup Job
  Note over PUN:Cleanup ServiceAccount
  Note over PUN:Cleanup Role
  Note over PUN:Cleanup RoleBinding
```

## PersistentVolumeClaim

A Persistent Volume is mounted to the Builder and Runner Pod.
Therefore a PersistentVolumeClaim (PVC) is deployed by the helm chart at hook `pre-install` with various configuration options (see [values.yaml](values.yaml) at section `persistence`).
The PVC is being deleted by *Cleanup Job* on deletion of the helm chart if `persistence.deleteOnUninstall: true` (default).

If you want to reuse an existing PVC instead of creating a new one, set `persistent.existingClaim`.

## ServiceAccount

A dedicated ServiceAccount is required by the Builder Job and the Runner Pod(s) if you need to inject Secrets via *CSI Secrets Driver* instead of using Kubernetes Secrets. Further information can be found later in this document.
It is being deployed by the helm chart at hook `pre-install` and is being deleted by *Cleanup Job* on deletion of the helm chart.
In order to create the ServiceAccount, set `serviceAccount.create: true` (default is `false`).
## Installation

### Quick install with internal service of type ClusterIP

By default, this helm chart installs the Ethereum Adapter Service at an internal ClusterIP Service listening at port 3000.
This is to prevent exposing the service to the internet by accident!

It is recommended to put non-sensitive configuration values in an configuration file and pass sensitive/secret values via commandline.

1. Create configuration file, e.g. *my-config.yaml*

    ```yaml
    config:
      vaultDomain: "vault.companyname"
      ethadapterUrl: "http://ethadapter.altimanager-poc-ethadapter:3000"
      buildSecretKey: "SuperStrongPassword"  # pragma: allowlist secret
      bdnsHosts: |-
          # ... content of the BDNS Hosts file ...

    ```

2. Install via helm to namespace `default`

    ```bash
    helm upgrade my-release-name pharmaledgerassoc/altimanager --version=0.1.0 \
        --install \
        --values my-config.yaml \
    ```

### Expose Service via Load Balancer

In order to expose the service **directly** by an **own dedicated** Load Balancer, just **add** `service.type` with value `LoadBalancer` to your config file (in order to override the default value which is `ClusterIP`).

**Please note:** At AWS using `service.type` = `LoadBalancer` is not recommended any more, as it creates a Classic Load Balancer. Use [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.3/) with an ingress instead. A full sample is provided later in the docs. Using an Application Load Balancer (managed by AWS LB Controller) increases security (e.g. by using a Web Application Firewall for your http based traffic) and provides more features like hostname, pathname routing or built-in authentication mechanism via OIDC or AWS Cognito.

Configuration file *my-config.yaml*

```yaml
service:
  type: LoadBalancer

config:
  # ... config section keys and values ...
```

There are more configuration options available like customizing the port and configuring the Load Balancer via annotations (e.g. for configuring SSL Listener).

**Also note:** Annotations are very specific to your environment/cloud provider, see [Kubernetes Service Reference](https://kubernetes.io/docs/concepts/services-networking/service/#ssl-support-on-aws) for more information. For Azure, take a look [here](https://kubernetes-sigs.github.io/cloud-provider-azure/topics/loadbalancer/#loadbalancer-annotations).

Sample for AWS (SSL and listening on port 1234 instead 80 which is the default):

```yaml
service:
  type: LoadBalancer
  port: 80
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-ssl-cert: arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012
    service.beta.kubernetes.io/aws-load-balancer-backend-protocol: http
    service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "80"
    # https://docs.aws.amazon.com/de_de/elasticloadbalancing/latest/classic/elb-security-policy-table.html
    service.beta.kubernetes.io/aws-load-balancer-ssl-negotiation-policy: "ELBSecurityPolicy-TLS-1-2-2017-01"

# further config
```

### AWS Load Balancer Controller: Expose Service via Ingress

Note: You need the [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/) installed and configured properly.

1. Enable ingress
2. Add *host*, *path* *`/*`* and *pathType* `ImplementationSpecific`
3. Add annotations for AWS LB Controller
4. A SSL certificate at AWS Certificate Manager (either for the hostname, here `altimanager.mydomain.com` or wildcard `*.mydomain.com`)

Configuration file *my-config.yaml*

```yaml
ingress:
  enabled: true
  # Let AWS LB Controller handle the ingress (default className is alb)
  # Note: Use className instead of annotation 'kubernetes.io/ingress.class' which is deprecated since 1.18
  # For Kubernetes >= 1.18 it is required to have an existing IngressClass object.
  # See: https://kubernetes.io/docs/concepts/services-networking/ingress/#deprecated-annotation
  className: alb
  hosts:
    - host: altimanager.mydomain.com
      # Path must be /* for ALB to match all paths
      paths:
        - path: /*
          pathType: ImplementationSpecific
  # For full list of annotations for AWS LB Controller, see https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.3/guide/ingress/annotations/
  annotations:
    # The ARN of the existing SSL Certificate at AWS Certificate Manager
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:REGION:ACCOUNT_ID:certificate/CERTIFICATE_ID
    # The name of the ALB group, can be used to configure a single ALB by multiple ingress objects
    alb.ingress.kubernetes.io/group.name: default
    # Specifies the HTTP path when performing health check on targets.
    alb.ingress.kubernetes.io/healthcheck-path: /
    # Specifies the port used when performing health check on targets.
    alb.ingress.kubernetes.io/healthcheck-port: traffic-port
    # Specifies the HTTP status code that should be expected when doing health checks against the specified health check path.
    alb.ingress.kubernetes.io/success-codes: "200"
    # Listen on HTTPS protocol at port 443 at the ALB
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    # Use internet facing
    alb.ingress.kubernetes.io/scheme: internet-facing
    # Use most current (as of Dec 2021) encryption ciphers
    alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-TLS-1-2-Ext-2018-06
    # Use target type IP which is the case if the service type is ClusterIP
    alb.ingress.kubernetes.io/target-type: ip

config:
  # ... config section keys and values ...
```

## CSI Secrets Driver

This enables storing the following secret values in one of the supported Secret stores (e.g. Azure Key Vault or AWS Secrets Manager) instead of using Kubernetes Secrets:

- `apihub.json` - If using SSO, *apihub.json* contains SSO configuration like Client ID and Secret
- `env.json` - Contains the secret passphrase for de/encrypting the generated private keys for the wallets.

More information can be found here:

- [https://secrets-store-csi-driver.sigs.k8s.io/](https://secrets-store-csi-driver.sigs.k8s.io/)
- [https://aws.amazon.com/blogs/security/how-to-use-aws-secrets-configuration-provider-with-kubernetes-secrets-store-csi-driver/](https://aws.amazon.com/blogs/security/how-to-use-aws-secrets-configuration-provider-with-kubernetes-secrets-store-csi-driver/)

Sample for AWS:

1. Prepare `env.json` and `apihub.json` files. See [here](https://github.com/pharmaledgerassoc/altimanager-workspace/blob/v1.3.1/apihub-root/external-volume/config/apihub.json) and [here](https://github.com/pharmaledgerassoc/altimanager-workspace/blob/v1.3.1/env.json) for templates.
2. Create a new Secret in Secrets Manager with two keys `envJson` and `apihubJson`. Note: If you want to create the secret as PlainText, then you must encode the values to JSON String each!

    Sample:

    ```json
    {
        "envJson": "{  \"PSK_TMP_WORKING_DIR\": \"tmp\", <AND MORE IN JSON STRING FORMAT> }",
        "apihubJson": "{  \"storage\": \"../apihub-root\",  <AND MORE IN JSON STRING FORMAT> }"
    }
    ```

3. Create IAM role with trust relationship to the Kubernetes Service Account and a policy that allows getting the secret value.

    Trust relationship sample:

    ```json
    {
      "Version": "2012-10-17",
      "Statement": [
          {
              "Sid": "AssumeableByOIDC",
              "Effect": "Allow",
              "Principal": {
                  "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/oidc.eks.<REGION>.amazonaws.com/id/<OIDC_PROVIDER_ID>"
              },
              "Action": "sts:AssumeRoleWithWebIdentity",
              "Condition": {
                  "StringLike": {
                      "oidc.eks.<REGION>.amazonaws.com/id/<OIDC_PROVIDER_ID>:sub": "system:serviceaccount:<K8S_NAMESPACE>:<NAME>"
                  }
              }
          }
      ]
    }
    ```

    Policy:

    ```json
    {
        "Statement": [
            {
                "Action": [
                    "secretsmanager:GetSecretValue",
                    "secretsmanager:DescribeSecret"
                ],
                "Effect": "Allow",
                "Resource": [
                    "<SECRET_ARN>"
                ]
            }
        ],
        "Version": "2012-10-17"
    }
    ```

4. Modify config to use ServiceAccount and SecretProviderClass

    ```yaml
    serviceAccount:
      create: true
      annotations:
        eks.amazonaws.com/role-arn: "<ARN of the IAM role>"

    secretProviderClass:
      enabled: true
      spec:
        provider: aws
        parameters:
          objects: |
            - objectName: "<ARN or Name of Secret>"
              objectType: "secretsmanager"
              jmesPath:
                - path: envJson
                  objectAlias: env.json
                - path: apihubJson
                  objectAlias: apihub.json
    ```

## Backup: Create VolumeSnapshot before upgrading and before deletion of helm release

Note: Ensure Volume Snapshotting has been set up appropriately.

```yaml
volumeSnapshots:
  preUpgradeEnabled: true
  finalSnapshotEnabled: true
  # It is stongly recommended to use a class with 'deletionPolicy: Retain' for the pre-upgrade and final snapshots.
  # Otherwise you will loose the snapshot on your storage system if the Kubernetes VolumeSnapshot will be deleted (e.g. if the namespace will be deleted).
  className: "<Name of the VolumeSnapshotClass>"

```

## Additional helm options

Run `helm upgrade --helm` for full list of options.

1. Install to other namespace

    You can install into other namespace than `default` by setting the `--namespace` parameter, e.g.

    ```bash
    helm upgrade my-release-name pharmaledgerassoc/altimanager --version=0.1.0 \
        --install \
        --namespace=my-namespace \
        --values my-config.yaml \
    ```

2. Wait until installation has finished successfully and the deployment is up and running.

    Provide the `--wait` argument and time to wait (default is 5 minutes) via `--timeout`

    ```bash
    helm upgrade my-release-name pharmaledgerassoc/altimanager --version=0.1.0 \
        --install \
        --wait --timeout=600s \
        --values my-config.yaml \
    ```

## Potential issues

1. `Error: admission webhook "vingress.elbv2.k8s.aws" denied the request: invalid ingress class: IngressClass.networking.k8s.io "alb" not found`

    **Description:** This error only applies to Kubernetes >= 1.18 and indicates that no matching *IngressClass* object was found.

    **Solution:** Either declare an appropriate IngressClass or omit *className* and add annotation `kubernetes.io/ingress.class`

    Further information:

     - [Kubernetes IngressClass](https://kubernetes.io/docs/concepts/services-networking/ingress/#ingress-class)
     - [AWS Load Balancer controller documentation](https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.3/guide/ingress/ingress_class/)

## Helm Unittesting

[helm-unittest](https://github.com/quintush/helm-unittest) is being used for testing the output of the helm chart.
Tests can be found in [tests](./tests)

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| skutner |  | <https://github.com/skutner> |

## Values

*Note:* Please scroll horizontally to show more columns (e.g. description)!

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Affinity for scheduling a pod. See [https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/) |
| config.apihubJson | string | `""` |  |
| config.bdnsHosts | string | `""` |  |
| config.buildSecretKey | string | `""` | Secret Pass Phrase for de/encrypting private keys for application wallets created by builder. |
| config.companyName | string | `"Company Inc"` | A CompanyName which is displayed on the web page. |
| config.envJson | string | `""` |  |
| config.environmentJs | string | `""` |  |
| config.vaultDomain | string | `"altimanager"` | The Domain, e.g. "epipoc" |
| config.vaultDomainConfigJson | string | `""` |  |
| extraResources | string | `nil` | An array of extra resources that will be deployed. This is useful e.g. for custom resources like SnapshotSchedule provided by [https://github.com/backube/snapscheduler](https://github.com/backube/snapscheduler). |
| fullnameOverride | string | `""` | fullnameOverride completely replaces the generated name. From [https://stackoverflow.com/questions/63838705/what-is-the-difference-between-fullnameoverride-and-nameoverride-in-helm](https://stackoverflow.com/questions/63838705/what-is-the-difference-between-fullnameoverride-and-nameoverride-in-helm) |
| image.deploymentStrategy | object | `{"type":"Recreate"}` | The strategy of the deployment for the runner. Defaults to type: Recreate as a PVC is bound to it. See `kubectl explain deployment.spec.strategy` for more and [https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#strategy](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#strategy) |
| image.livenessProbe | object | `{"failureThreshold":3,"httpGet":{"httpHeaders":[{"name":"Host","value":"localhost"}],"path":"/installation-details","port":"http"},"initialDelaySeconds":10,"periodSeconds":10,"successThreshold":1,"timeoutSeconds":1}` | Liveness probe. See [https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) |
| image.podAnnotations | object | `{}` | Annotations added to the runner pod |
| image.podSecurityContext | object | `{"fsGroup":1000,"runAsGroup":1000,"runAsUser":1000}` | Pod Security Context for the runner. See [https://kubernetes.io/docs/tasks/configure-pod-container/security-context/#set-the-security-context-for-a-pod](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/#set-the-security-context-for-a-pod) |
| image.pullPolicy | string | `"Always"` | Image Pull Policy for the runner |
| image.readinessProbe | object | `{"failureThreshold":3,"httpGet":{"httpHeaders":[{"name":"Host","value":"localhost"}],"path":"/ready-probe","port":"http"},"initialDelaySeconds":10,"periodSeconds":10,"successThreshold":1,"timeoutSeconds":1}` | Readiness probe. See [https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) |
| image.replicaCount | int | `1` | The number of replicas for the runner |
| image.repository | string | `"axiologic/altimanager"` | The repository of the container image for the runner <!-- # pragma: allowlist secret --> |
| image.securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"privileged":false,"readOnlyRootFilesystem":false,"runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000}` | Security Context for the runner container See [https://kubernetes.io/docs/tasks/configure-pod-container/security-context/#set-the-security-context-for-a-container](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/#set-the-security-context-for-a-container) |
| image.sha | string | `"7927c151d4a4025682f8a94d94f313a3e87fc42bdd75514049c46688296a1aa7"` | sha256 digest of the image. Do not add the prefix "@sha256:" Default to v1.3.1 <!-- # pragma: allowlist secret --> |
| image.tag | string | `"0.1.0"` | Overrides the image tag whose default is the chart appVersion. Default to v1.3.1 |
| imagePullSecrets | list | `[]` | Secret(s) for pulling an container image from a private registry. Used for all images. See [https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/](https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/) |
| ingress.annotations | object | `{}` | Ingress annotations. <br/> For AWS LB Controller, see [https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.3/guide/ingress/annotations/](https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.3/guide/ingress/annotations/) <br/> For Azure Application Gateway Ingress Controller, see [https://azure.github.io/application-gateway-kubernetes-ingress/annotations/](https://azure.github.io/application-gateway-kubernetes-ingress/annotations/) <br/> For NGINX Ingress Controller, see [https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/) <br/> For Traefik Ingress Controller, see [https://doc.traefik.io/traefik/routing/providers/kubernetes-ingress/#annotations](https://doc.traefik.io/traefik/routing/providers/kubernetes-ingress/#annotations) |
| ingress.className | string | `""` | The className specifies the IngressClass object which is responsible for that class. See [https://kubernetes.io/docs/concepts/services-networking/ingress/#ingress-class](https://kubernetes.io/docs/concepts/services-networking/ingress/#ingress-class) <br/> For Kubernetes >= 1.18 it is required to have an existing IngressClass object. If IngressClass object does not exists, omit className and add the deprecated annotation 'kubernetes.io/ingress.class' instead. <br/> For Kubernetes < 1.18 either use className or annotation 'kubernetes.io/ingress.class'. |
| ingress.enabled | bool | `false` | Whether to create ingress or not for the runner. <br/> Note: For ingress an Ingress Controller (e.g. AWS LB Controller, NGINX Ingress Controller, Traefik, ...) is required and service.type should be ClusterIP or NodePort depending on your configuration |
| ingress.hosts | list | `[{"host":"altimanager.some-pharma-company.com","paths":[{"path":"/","pathType":"ImplementationSpecific"}]}]` | A list of hostnames and path(s) to listen at the Ingress Controller |
| ingress.hosts[0].host | string | `"altimanager.some-pharma-company.com"` | The FQDN/hostname |
| ingress.hosts[0].paths[0].path | string | `"/"` | The Ingress Path. See [https://kubernetes.io/docs/concepts/services-networking/ingress/#examples](https://kubernetes.io/docs/concepts/services-networking/ingress/#examples) <br/> Note: For Ingress Controllers like AWS LB Controller see their specific documentation. |
| ingress.hosts[0].paths[0].pathType | string | `"ImplementationSpecific"` | The type of path. This value is required since Kubernetes 1.18. <br/> For Ingress Controllers like AWS LB Controller or Traefik it is usually required to set its value to ImplementationSpecific See [https://kubernetes.io/docs/concepts/services-networking/ingress/#path-types](https://kubernetes.io/docs/concepts/services-networking/ingress/#path-types) and [https://kubernetes.io/blog/2020/04/02/improvements-to-the-ingress-api-in-kubernetes-1.18/](https://kubernetes.io/blog/2020/04/02/improvements-to-the-ingress-api-in-kubernetes-1.18/) |
| ingress.tls | list | `[]` |  |
| kubectl.image.pullPolicy | string | `"Always"` | Image Pull Policy |
| kubectl.image.repository | string | `"bitnami/kubectl"` | The repository of the container image containing kubectl |
| kubectl.image.sha | string | `"bba32da4e7d08ce099e40c573a2a5e4bdd8b34377a1453a69bbb6977a04e8825"` | sha256 digest of the image. Do not add the prefix "@sha256:" <br/> Defaults to image digest for "bitnami/kubectl:1.21.14", see [https://hub.docker.com/layers/kubectl/bitnami/kubectl/1.21.14/images/sha256-f9814e1d2f1be7f7f09addd1d877090fe457d5b66ca2dcf9a311cf1e67168590?context=explore](https://hub.docker.com/layers/kubectl/bitnami/kubectl/1.21.14/images/sha256-f9814e1d2f1be7f7f09addd1d877090fe457d5b66ca2dcf9a311cf1e67168590?context=explore) <!-- # pragma: allowlist secret --> |
| kubectl.image.tag | string | `"1.21.14"` | The Tag of the image containing kubectl. Minor Version should match to your Kubernetes Cluster Version. |
| kubectl.podSecurityContext | object | `{"fsGroup":65534,"runAsGroup":65534,"runAsUser":65534}` | Pod Security Context for the pod running kubectl. See [https://kubernetes.io/docs/tasks/configure-pod-container/security-context/#set-the-security-context-for-a-pod](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/#set-the-security-context-for-a-pod) |
| kubectl.resources | object | `{"limits":{"cpu":"100m","memory":"128Mi"},"requests":{"cpu":"100m","memory":"128Mi"}}` | Resource constraints for the pre-builder and cleanup job |
| kubectl.securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"privileged":false,"readOnlyRootFilesystem":true,"runAsGroup":65534,"runAsNonRoot":true,"runAsUser":65534}` | Security Context for the container running kubectl See [https://kubernetes.io/docs/tasks/configure-pod-container/security-context/#set-the-security-context-for-a-container](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/#set-the-security-context-for-a-container) |
| kubectl.ttlSecondsAfterFinished | int | `300` | Time to keep the Job after finished in case of an error. If no error occured the Jobs will immediately by deleted. If value is not set, then 'ttlSecondsAfterFinished' will not be set. |
| nameOverride | string | `""` | nameOverride replaces the name of the chart in the Chart.yaml file, when this is used to construct Kubernetes object names. From [https://stackoverflow.com/questions/63838705/what-is-the-difference-between-fullnameoverride-and-nameoverride-in-helm](https://stackoverflow.com/questions/63838705/what-is-the-difference-between-fullnameoverride-and-nameoverride-in-helm) |
| namespaceOverride | string | `""` | Override the deployment namespace. Very useful for multi-namespace deployments in combined charts |
| nodeSelector | object | `{}` | Node Selectors in order to assign pods to certain nodes. See [https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/) |
| persistence.accessModes | list | `["ReadWriteOnce"]` | AccessModes for the new PVC. See [https://kubernetes.io/docs/concepts/storage/persistent-volumes/#access-modes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#access-modes) |
| persistence.dataSource | object | `{}` | DataSource option for cloning an existing volume or creating from a snapshot for a new PVC. See [values.yaml](values.yaml) for more details. |
| persistence.deleteOnUninstall | bool | `true` | Boolean flag whether to delete the (new) PVC on uninstall or not. |
| persistence.existingClaim | string | `""` | The name of an existing PVC to use instead of creating a new one. |
| persistence.finalizers | list | `["kubernetes.io/pvc-protection"]` | Finalizers for the new PVC. See [https://kubernetes.io/docs/concepts/storage/persistent-volumes/#storage-object-in-use-protection](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#storage-object-in-use-protection) |
| persistence.selectorLabels | object | `{}` | Selector Labels for the new PVC. See [https://kubernetes.io/docs/concepts/storage/persistent-volumes/#selector](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#selector) |
| persistence.size | string | `"100Gi"` | Size of the volume for the new PVC |
| persistence.storageClassName | string | `""` | Name of the storage class for the new PVC. If empty or not set then storage class will not be set - which means that the default storage class will be used. |
| resources | object | `{}` | Resource constraints for the builder and runner |
| secretProviderClass.apiVersion | string | `"secrets-store.csi.x-k8s.io/v1"` | API Version of the SecretProviderClass |
| secretProviderClass.enabled | bool | `false` | Whether to use CSI Secrets Store (e.g. Azure Key Vault) instead of "traditional" Kubernetes Secret. NOTE: DO ENABLE, NOT TESTED YET! |
| secretProviderClass.spec | object | `{}` | Spec for the SecretProviderClass. Note: The orgAccountJson must be mounted as objectAlias orgAccountJson |
| service.annotations | object | `{}` | Annotations for the service. See AWS, see [https://kubernetes.io/docs/concepts/services-networking/service/#ssl-support-on-aws](https://kubernetes.io/docs/concepts/services-networking/service/#ssl-support-on-aws) For Azure, see [https://kubernetes-sigs.github.io/cloud-provider-azure/topics/loadbalancer/#loadbalancer-annotations](https://kubernetes-sigs.github.io/cloud-provider-azure/topics/loadbalancer/#loadbalancer-annotations) |
| service.loadBalancerIP | string | `""` | A static IP address for the LoadBalancer if type is LoadBalancer. Note: This only applies to certain Cloud providers like Google or [Azure](https://docs.microsoft.com/en-us/azure/aks/static-ip). [https://kubernetes.io/docs/concepts/services-networking/service/#type-loadbalancer](https://kubernetes.io/docs/concepts/services-networking/service/#type-loadbalancer). |
| service.loadBalancerSourceRanges | string | `nil` | A list of CIDR ranges to whitelist for ingress traffic to the service if type is LoadBalancer. If list is empty, Kubernetes allows traffic from 0.0.0.0/0 |
| service.port | int | `80` | Port where the service will be exposed |
| service.type | string | `"ClusterIP"` | Either ClusterIP, NodePort or LoadBalancer for the runner See [https://kubernetes.io/docs/concepts/services-networking/service/](https://kubernetes.io/docs/concepts/services-networking/service/) |
| serviceAccount.annotations | object | `{}` | Annotations to add to the service account |
| serviceAccount.automountServiceAccountToken | bool | `false` | Whether automounting API credentials for a service account is enabled or not. See [https://docs.bridgecrew.io/docs/bc_k8s_35](https://docs.bridgecrew.io/docs/bc_k8s_35) |
| serviceAccount.create | bool | `false` | Specifies whether a service account should be created which is used by builder and runner. |
| serviceAccount.name | string | `""` | The name of the service account to use. If not set and create is true, a name is generated using the fullname template |
| tolerations | list | `[]` | Tolerations for scheduling a pod. See [https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/) |
| volumeSnapshots.apiVersion | string | `"v1"` | API Version of the "snapshot.storage.k8s.io" resource. See [https://kubernetes.io/docs/concepts/storage/volume-snapshots/](https://kubernetes.io/docs/concepts/storage/volume-snapshots/) |
| volumeSnapshots.className | string | `""` | The Volume Snapshot class name to use for the pre-upgrade and the final snapshot. It is stongly recommended to use a class with 'deletionPolicy: Retain' for the pre-upgrade and final snapshots. Otherwise you will loose the snapshot on your storage system if the Kubernetes VolumeSnapshot will be deleted (e.g. if the namespace will be deleted). See [https://kubernetes.io/docs/concepts/storage/volume-snapshot-classes/](https://kubernetes.io/docs/concepts/storage/volume-snapshot-classes/) |
| volumeSnapshots.finalSnapshotEnabled | bool | `false` | Whether to create final snapshot before delete. The name of the VolumeSnapshot will be "<helm release name>-final-<UTC timestamp YYYYMMDDHHMM>", e.g. "altimanager-final-202206221213" |
| volumeSnapshots.preUpgradeEnabled | bool | `false` | Whether to create snapshots before helm upgrading or not. The name of the VolumeSnapshot will be "<helm release name>-upgrade-to-revision-<helm revision>-<UTC timestamp YYYYMMDDHHMM>", e.g. "altimanager-upgrade-to-revision-19-202206221211" |
| volumeSnapshots.waitForReadyToUse | bool | `true` | Whether to wait until the VolumeSnapshot is ready to use. Note: On first snapshot this may take a while. |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.8.1](https://github.com/norwoodj/helm-docs/releases/v1.8.1)