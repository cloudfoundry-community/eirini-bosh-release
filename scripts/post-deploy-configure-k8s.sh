#!/usr/bin/env bash

set -euo pipefail

LB_CA_CERT="$1"
SYSTEM_DOMAIN="$2"

BOSH_ENV_NAME="${BOSH_ENV_NAME:-$(bosh env --json | jq .Tables[0].Rows[0].name -r)}"
DOPPLER_ADDRESS="$(bosh -d cf vms | grep doppler | cut -d$'\t' -f4 | head -n 1)"

echo "Creating secret for the load balancer CA cert..."
kubectl apply -f <(kubectl create secret generic lb-ca-cert \
  --from-literal=ca.crt="$LB_CA_CERT" \
  --dry-run \
  --save-config \
  -o yaml)
kubectl apply -f <(cat <<EOD
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: add-lb-cert-to-nodes
  namespace: default
spec:
  selector:
    matchLabels:
      name: add-lb-cert-to-nodes
  updateStrategy:
    type: RollingUpdate
  template:
    metadata:
      labels:
        name: add-lb-cert-to-nodes
    spec:
      initContainers:
      - name: create-docker-certs-directory-on-node
        image: ubuntu:xenial
        securityContext:
          runAsUser: 0
          privileged: true
        volumeMounts:
        - name: etcdocker
          mountPath: /etc/docker
        command: ["bash"]
        args: ["-cx", "mkdir -p /etc/docker/certs.d/registry.${SYSTEM_DOMAIN}"]
      containers:
      - name: add-ca-cert-to-nodes-docker-trust
        image: ubuntu:xenial
        securityContext:
          runAsUser: 0
          privileged: true
        volumeMounts:
        - name: etcdocker
          mountPath: /etc/docker
        - name: lb-ca-cert
          mountPath: /etc/lb-ca-cert
        command: ["bash"]
        args: ["-cx", "cp /etc/lb-ca-cert/ca.crt /etc/docker/certs.d/registry.${SYSTEM_DOMAIN}/ && sleep infinity"]
      volumes:
      - name: etcdocker
        hostPath:
          path: /etc/docker
      - name: lb-ca-cert
        secret:
          secretName: lb-ca-cert
EOD)

echo "Creating loggregator certs secret..."
kubectl apply -f <(kubectl create secret generic loggregator-tls-certs-secret \
  --from-literal=internal-ca-cert="$(credhub get -n /${BOSH_ENV_NAME}/cf/loggregator_tls_agent -j | jq -r .value.ca)" \
  --from-literal=loggregator-agent-cert-key="$(credhub get -n /${BOSH_ENV_NAME}/cf/loggregator_tls_agent -j | jq -r .value.private_key)" \
  --from-literal=loggregator-agent-cert="$(credhub get -n /${BOSH_ENV_NAME}/cf/loggregator_tls_agent -j | jq -r .value.certificate)" \
  --dry-run \
  --save-config \
  -o yaml)

echo "Creating loggregator fluentd ConfigMap..."
kubectl apply -f <(cat <<EOD
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluentd-conf
data:
  fluentd-conf-contents: |
    <match fluent.**>
      @type null
    </match>

    <source>
      @type tail
      @id in_tail_container_logs
      path /var/log/containers/*.log
      pos_file /var/log/fluentd-containers.log.pos
      tag kubernetes.*
      format json
      read_from_head true
      refresh_interval 1
      time_format %Y-%m-%dT%H:%M:%S.%N%:z
    </source>

    <filter kubernetes.**>
      @type kubernetes_metadata
    </filter>

    <match **>
      type loggregator
      loggregator_target localhost:3458
      loggregator_cert_file /fluentd/certs/agent.crt
      loggregator_key_file /fluentd/certs/agent.key
      loggregator_ca_file /fluentd/certs/ca.crt
      eirini_namespace eirini
    </match>

    <match kubernetes.var.log.containers.**eirini**.log>
      @type stdout
    </match>

    <match kubernetes.var.log.containers.**.log>
      @type null
    </match>
EOD)

echo "Creating loggregator fluentd DaemonSet..."
kubectl apply -f <(cat <<EOD
---
apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  name: loggregator-fluentd
spec:
  selector:
    matchLabels:
      name: loggregator-fluentd
  updateStrategy:
    type: RollingUpdate
  template:
    metadata:
      labels:
        name: loggregator-fluentd
    spec:
      serviceAccountName: "opi-service-account"
      initContainers:
      - name: config-copier
        image: alpine:latest
        command: [ "/bin/sh", "-c", "cp /input/fluent.conf /output" ]
        volumeMounts:
        - name: fluentd-conf
          mountPath: /input
        - name: config-volume
          mountPath: /output
          readOnly: false
      containers:
      - name: loggregator-fluentd
        image: eirini/loggregator-fluentd:0.2.0
        imagePullPolicy: Always
        env:
        - name: FLUENT_UID
          value: "0"
        - name: GRPC_VERBOSITY
          value: DEBUG
        resources:
          limits:
            memory: 200Mi
          requests:
            cpu: 100m
            memory: 200Mi
        volumeMounts:
        - name: vardata
          mountPath: /var/data
        - name: varlog
          mountPath: /var/log
        - name: containers
          mountPath: /var/lib/docker/containers
        - name: bosh-docker-containers
          mountPath: /var/vcap/store/docker/docker/containers
        - name: config-volume
          mountPath: /fluentd/etc/
          readOnly: false
        - name: loggregator-tls-certs
          mountPath: /fluentd/certs
          readOnly: true
      - name: loggregator-agent
        image: loggregator/agent
        imagePullPolicy: Always
        env:
        - name: AGENT_METRIC_SOURCE_ID
          value: scf/daemonset/loggregator-fluentd
        - name: ROUTER_ADDR
          value: ${DOPPLER_ADDRESS}:8082
        - name: ROUTER_ADDR_WITH_AZ
          value: ${DOPPLER_ADDRESS}:8082
        - name: AGENT_PPROF_PORT
          value: "6062"
        - name: AGENT_HEALTH_ENDPOINT_PORT
          value: "6063"
        ports:
        - name: health
          containerPort: 6063
        volumeMounts:
        - name: loggregator-tls-certs
          mountPath: /srv/certs
          readOnly: true
      terminationGracePeriodSeconds: 30
      volumes:
      - name: vardata
        hostPath:
          path: /var/data
      - name: config-volume
        emptyDir: {}
      - name: varlog
        hostPath:
          path: /var/log
      - name: containers
        hostPath:
          path: /var/lib/docker/containers
      - name: bosh-docker-containers
        hostPath:
          path: /var/vcap/store/docker/docker/containers
      - name: fluentd-conf
        configMap:
          name: fluentd-conf
          items:
          - key: fluentd-conf-contents
            path: fluent.conf
      - name: loggregator-tls-certs
        secret:
          secretName: loggregator-tls-certs-secret
          items:
            - key: loggregator-agent-cert
              path: agent.crt
            - key: loggregator-agent-cert-key
              path: agent.key
            - key: internal-ca-cert
              path: ca.crt
EOD)

echo "Done"
