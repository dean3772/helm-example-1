#!/bin/bash

# Create a new directory for the chart
mkdir mlflow-chart
cd mlflow-chart

# Create the Chart.yaml file
cat <<EOF > Chart.yaml
apiVersion: v2
name: mlflow
version: 0.1.0
appVersion: 1.0.0
description: A Helm chart for deploying mlflow on Kubernetes

dependencies:
- name: postgresql
  version: 9.6.17
  repository: https://charts.bitnami.com/bitnami
- name: nginx-ingress
  version: 1.41.2
  repository: https://charts.helm.sh/stable

values:
  image:
    repository: larribas/mlflow
    tag: latest
  service:
    type: ClusterIP
    port: 80
  ingress:
    enabled: true
    hosts:
    - mlflow.example.com
  postgresql:
    enabled: true
    persistence:
      enabled: true
      size: 8Gi
    postgresqlDatabase: mlflow
    postgresqlUsername: mlflow
    postgresqlPassword: mlflowpassword
  artifacts:
    destination: s3
    s3:
      bucket: mlflow-artifacts

templates:
- path: mlflow-deployment.yaml
  kind: Deployment
- path: mlflow-service.yaml
  kind: Service
- path: mlflow-ingress.yaml
  kind: Ingress
- path: postgresql-deployment.yaml
  kind: Deployment
- path: postgresql-service.yaml
  kind: Service
EOF

# Create the values.yaml file
cat <<EOF > values.yaml
postgresql:
  postgresqlPassword: mlflowpassword
  postgresqlUsername: mlflow
  postgresqlDatabase: mlflow
  persistence:
    size: 8Gi
    enabled: true
  enabled: true
ingress:
  enabled: true
  hosts:
  - mlflow.example.com
service:
  type: ClusterIP
  port: 80
image:
  repository: larribas/mlflow
  tag: latest
artifacts:
  destination: s3
  s3:
    bucket: mlflow-artifacts
backend-store-uri: {postgres-connection-string}
serve-artifacts: true
artifacts-destination: {s3 or some local path}
EOF

# Create the templates directory
mkdir templates

# Create the mlflow-deployment.yaml file
cat <<EOF > templates/mlflow-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mlflow
  labels:
    app: mlflow
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mlflow
  template:
    metadata:
      labels:
        app: mlflow
    spec:
      containers:
      - name: mlflow
        image: "        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        command: ["mlflow", "server", "--host=0.0.0.0", "--port=80", "--backend-store-uri={{ .Values.backend-store-uri }}", "--serve-artifacts", "--artifacts-destination={{ .Values.artifacts.destination }}"]
        ports:
        - containerPort: 80
        resources:
          limits:
            cpu: "1"
            memory: "1Gi"
          requests:
            cpu: "0.5"
            memory: "500Mi"
      {{- if .Values.postgresql.enabled }}
      - name: postgresql
        image: "postgres:{{ .Values.postgresql.version }}"
        env:
        - name: POSTGRES_USER
          value: "{{ .Values.postgresql.postgresqlUsername }}"
        - name: POSTGRES_PASSWORD
          value: "{{ .Values.postgresql.postgresqlPassword }}"
        - name: POSTGRES_DB
          value: "{{ .Values.postgresql.postgresqlDatabase }}"
        {{- if .Values.postgresql.persistence.enabled }}
        volumeMounts:
        - name: postgresql-data
          mountPath: /var/lib/postgresql/data
        {{- end }}
      {{- end }}
      {{- if .Values.postgresql.persistence.enabled }}
      volumes:
      - name: postgresql-data
        persistentVolumeClaim:
          claimName: mlflow-postgresql-pv-claim
      {{- end }}
---

# Create the mlflow-service.yaml file
cat <<EOF > templates/mlflow-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: mlflow
  labels:
    app: mlflow
spec:
  selector:
    app: mlflow
  ports:
  - name: http
    port: 80
    targetPort: 80
  type: {{ .Values.service.type }}
---

# Create the mlflow-ingress.yaml file
cat <<EOF > templates/mlflow-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: mlflow-ingress
  labels:
    app: mlflow
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: {{ .Values.ingress.hosts | join "," }}
    http:
      paths:
      - path: /mlflow
        pathType: Prefix
        path: /
        pathType: Prefix
        backend:
          service:
            name: mlflow
            port:
              name: http
---

# Create the postgresql-deployment.yaml file
cat <<EOF > templates/postgresql-deployment
cat <<EOF > templates/postgresql-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgresql
  labels:
    app: postgresql
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgresql
  template:
    metadata:
      labels:
        app: postgresql
    spec:
      containers:
      - name: postgresql
        image: "postgres:{{ .Values.postgresql.version }}"
        env:
        - name: POSTGRES_USER
          value: "{{ .Values.postgresql.postgresqlUsername }}"
        - name: POSTGRES_PASSWORD
          value: "{{ .Values.postgresql.postgresqlPassword }}"
        - name: POSTGRES_DB
          value: "{{ .Values.postgresql.postgresqlDatabase }}"
        ports:
        - containerPort: 5432
        {{- if .Values.postgresql.persistence.enabled }}
        volumeMounts:
        - name: postgresql-data
          mountPath: /var/lib/postgresql/data
        {{- end }}
      {{- if .Values.postgresql.persistence.enabled }}
      volumes:
      - name: postgresql-data
        persistentVolumeClaim:
          claimName: mlflow-postgresql-pv-claim
      {{- end }}
---

# Create the postgresql-service.yaml file
cat <<EOF > templates/postgresql-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: postgresql
  labels:
    app: postgresql
spec:
  selector:
    app: postgresql
  ports:
  - name: postgresql
    port: 5432
    targetPort: 5432
  type: ClusterIP
EOF

# Package the chart
helm package .
helm dependency build
helm install mlflow $(pwd)/mlflow-chart
helm dependency build