{{- define "annotate.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "annotate.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "annotate.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "annotate.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "annotate.selectorLabels" -}}
app.kubernetes.io/name: {{ include "annotate.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "annotate.cloudflareWhitelist" -}}
173.245.48.0/20,103.21.244.0/22,103.22.200.0/22,103.31.4.0/22,141.101.64.0/18,108.162.192.0/18,190.93.240.0/20,188.114.96.0/20,197.234.240.0/22,198.41.128.0/17,162.158.0.0/15,104.16.0.0/13,104.24.0.0/14,172.64.0.0/13,131.0.72.0/22,2400:cb00::/32,2606:4700::/32,2803:f800::/32,2405:b500::/32,2405:8100::/32,2a06:98c0::/29,2c0f:f248::/32
{{- end }}

{{- define "annotate.backendEnv" -}}
- name: DB_HOST
  value: {{ .Values.database.host | quote }}
- name: DB_PORT
  value: {{ .Values.database.port | quote }}
- name: DB_USER
  valueFrom:
    secretKeyRef:
      name: {{ .Values.secrets.name }}
      key: {{ .Values.secrets.keys.dbUser }}
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.secrets.name }}
      key: {{ .Values.secrets.keys.dbPassword }}
- name: DB_NAME
  value: {{ .Values.database.name | quote }}
# Fleet dashboard (fleet.noizu.com) daily metrics push. The key secretKeyRef
# is optional: until START_APP_FLEET_INGEST_KEY lands in the synced secret the
# pod starts without it and FleetPush no-ops (logs once, exits :ok).
- name: FLEET_INGEST_URL
  value: {{ .Values.fleetIngest.url | quote }}
- name: FLEET_INGEST_KEY
  valueFrom:
    secretKeyRef:
      name: {{ .Values.secrets.name }}
      key: {{ .Values.secrets.keys.fleetIngestKey }}
      optional: true
{{- if .Values.secrets.keys.databaseUrl }}
- name: DATABASE_URL
  valueFrom:
    secretKeyRef:
      name: {{ .Values.secrets.name }}
      key: {{ .Values.secrets.keys.databaseUrl }}
{{- end }}
- name: SECRET_KEY_BASE
  valueFrom:
    secretKeyRef:
      name: {{ .Values.secrets.name }}
      key: {{ .Values.secrets.keys.secretKeyBase }}
- name: GUARDIAN_SECRET_KEY
  valueFrom:
    secretKeyRef:
      name: {{ .Values.secrets.name }}
      key: {{ .Values.secrets.keys.guardianSecretKey }}
- name: REDIS_URL
  valueFrom:
    secretKeyRef:
      name: {{ .Values.secrets.name }}
      key: {{ .Values.secrets.keys.redisUrl }}
- name: PHX_HOST
  value: {{ .Values.domain | quote }}
- name: FRONTEND_URL
  value: "https://{{ .Values.appDomain | default .Values.domain }}"
- name: PHX_SERVER
  value: "true"
- name: PORT
  value: {{ .Values.backend.port | quote }}
{{- if .Values.secrets.keys.sendgridApiKey }}
- name: SENDGRID_API_KEY
  valueFrom:
    secretKeyRef:
      name: {{ .Values.secrets.name }}
      key: {{ .Values.secrets.keys.sendgridApiKey }}
{{- end }}
- name: MAIL_FROM_NAME
  value: {{ .Values.mail.fromName | default .Values.domain | quote }}
- name: MAIL_FROM_ADDRESS
  value: {{ .Values.mail.fromAddress | default (printf "noreply@%s" .Values.domain) | quote }}
{{- if .Values.sso.oidc.issuer }}
- name: OIDC_ISSUER
  value: {{ .Values.sso.oidc.issuer | quote }}
- name: OIDC_CLIENT_ID
  valueFrom:
    secretKeyRef:
      name: {{ .Values.secrets.name }}
      key: {{ .Values.secrets.keys.oidcClientId }}
- name: OIDC_CLIENT_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ .Values.secrets.name }}
      key: {{ .Values.secrets.keys.oidcClientSecret }}
- name: OIDC_REDIRECT_URI
  value: {{ .Values.sso.oidc.redirectUri | default (printf "https://%s/auth/oidc/callback" .Values.domain) | quote }}
- name: EMBED_OIDC_REDIRECT_URI
  value: {{ printf "https://%s/embed/callback" (.Values.appDomain | default .Values.domain) | quote }}
{{- end }}
{{- if .Values.sso.domains }}
- name: SSO_DOMAINS
  value: {{ .Values.sso.domains | quote }}
{{- end }}
{{- if .Values.sso.autoApproveDomains }}
- name: SSO_AUTO_APPROVE_DOMAINS
  value: {{ .Values.sso.autoApproveDomains | quote }}
{{- end }}
{{- if .Values.secrets.keys.googleClientId }}
- name: GOOGLE_CLIENT_ID
  valueFrom:
    secretKeyRef:
      name: {{ .Values.secrets.name }}
      key: {{ .Values.secrets.keys.googleClientId }}
- name: GOOGLE_CLIENT_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ .Values.secrets.name }}
      key: {{ .Values.secrets.keys.googleClientSecret }}
{{- end }}
{{- if .Values.secrets.keys.facebookClientId }}
- name: FACEBOOK_CLIENT_ID
  valueFrom:
    secretKeyRef:
      name: {{ .Values.secrets.name }}
      key: {{ .Values.secrets.keys.facebookClientId }}
- name: FACEBOOK_CLIENT_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ .Values.secrets.name }}
      key: {{ .Values.secrets.keys.facebookClientSecret }}
{{- end }}
{{- if .Values.secrets.keys.githubClientId }}
- name: GITHUB_CLIENT_ID
  valueFrom:
    secretKeyRef:
      name: {{ .Values.secrets.name }}
      key: {{ .Values.secrets.keys.githubClientId }}
- name: GITHUB_CLIENT_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ .Values.secrets.name }}
      key: {{ .Values.secrets.keys.githubClientSecret }}
{{- end }}
{{- if .Values.secrets.keys.linkedinClientId }}
- name: LINKEDIN_CLIENT_ID
  valueFrom:
    secretKeyRef:
      name: {{ .Values.secrets.name }}
      key: {{ .Values.secrets.keys.linkedinClientId }}
- name: LINKEDIN_CLIENT_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ .Values.secrets.name }}
      key: {{ .Values.secrets.keys.linkedinClientSecret }}
{{- end }}
{{- $samlMetadataFile := .Values.sso.saml.idpMetadataFile | default .Values.sso.saml.idpMetadataUrl }}
{{- if or .Values.sso.saml.idpMetadata $samlMetadataFile }}
{{- if .Values.sso.saml.idpMetadata }}
- name: SAML_IDP_METADATA
  value: {{ .Values.sso.saml.idpMetadata | quote }}
{{- else }}
- name: SAML_IDP_METADATA_FILE
  value: {{ $samlMetadataFile | quote }}
{{- end }}
- name: SAML_SP_ENTITY_ID
  value: {{ .Values.sso.saml.spEntityId | default (printf "https://%s" .Values.domain) | quote }}
- name: SAML_SP_BASE_URL
  value: "https://{{ .Values.domain }}/sso/saml"
- name: SAML_SP_CERT
  valueFrom:
    secretKeyRef:
      name: {{ .Values.secrets.name }}
      key: {{ .Values.secrets.keys.samlSpCert }}
- name: SAML_SP_KEY
  valueFrom:
    secretKeyRef:
      name: {{ .Values.secrets.name }}
      key: {{ .Values.secrets.keys.samlSpKey }}
{{- end }}
{{- if .Values.sso.requireInvite }}
- name: SSO_REQUIRE_INVITE
  value: "true"
{{- end }}
{{- end }}

{{- define "annotate.otelEnv" -}}
{{- $obs := .Values.otel -}}
{{- if $obs.enabled }}
{{- $serviceVersion := $obs.serviceVersion | default (splitList ":" .Values.backend.image | last) }}
{{- $deploymentEnvironment := $obs.deploymentEnvironment | default .Release.Namespace }}
- name: OTEL_EXPORTER_OTLP_ENDPOINT
  value: {{ $obs.collectorEndpoint | quote }}
- name: OTEL_EXPORTER_OTLP_PROTOCOL
  value: {{ $obs.protocol | default "http/protobuf" | quote }}
- name: OTEL_SERVICE_NAME
  value: {{ $obs.fleetSiteKey | quote }}
- name: OTEL_TRACES_SAMPLER
  value: {{ $obs.sampler | default "parentbased_traceidratio" | quote }}
- name: OTEL_TRACES_SAMPLER_ARG
  value: {{ $obs.samplerArg | default "1.0" | quote }}
- name: OTEL_RESOURCE_ATTRIBUTES
  value: {{ printf "service.namespace=%s,deployment.environment=%s,service.version=%s"
      ($obs.serviceNamespace | default "portfolio") $deploymentEnvironment $serviceVersion | quote }}
{{- end }}
{{- end }}

{{- define "annotate.storageEnv" -}}
{{- if .Values.storage.enabled }}
- name: S3_BUCKET
  value: {{ .Values.storage.bucket | quote }}
- name: S3_REGION
  value: {{ .Values.storage.region | quote }}
{{- if .Values.storage.endpoint }}
- name: S3_ENDPOINT
  value: {{ .Values.storage.endpoint | quote }}
{{- end }}
- name: S3_SCHEME
  value: {{ .Values.storage.scheme | quote }}
- name: AWS_ACCESS_KEY_ID
  valueFrom:
    secretKeyRef:
      name: {{ .Values.secrets.name }}
      key: {{ .Values.secrets.keys.awsAccessKeyId | default "AWS_ACCESS_KEY_ID" }}
- name: AWS_SECRET_ACCESS_KEY
  valueFrom:
    secretKeyRef:
      name: {{ .Values.secrets.name }}
      key: {{ .Values.secrets.keys.awsSecretAccessKey | default "AWS_SECRET_ACCESS_KEY" }}
{{- end }}
{{- end }}
