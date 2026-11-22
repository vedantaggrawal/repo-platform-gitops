{{/* Authentik blueprint for one tenant. Mirrors manifests/authentik/local/blueprints/demo-tenant.yaml. */}}
{{- define "tenant.blueprint" -}}
{{- $n := include "tenant.name" . -}}
{{- $cid := include "tenant.apiClientId" . -}}
# Tenant "{{ $n }}" + the API provider the gateway validates tokens against.
# Issuer: {{ .Values.authentik.baseUrl }}/application/o/{{ $cid }}/
# JWKS:   {{ .Values.authentik.baseUrl }}/application/o/{{ $cid }}/jwks/
# Token (JWT, RS256): sub, aud={{ $cid }}, tenant_id, tier (no profile/groups).
version: 1
metadata:
  name: platform - {{ $n }} tenant
entries:
  # Tenant admins manage their own tenant's membership in Authentik (self-serve).
  # The role is held by the tenant-{{ $n }}-admin group; the object permissions on
  # each tenant-{{ $n }}* group below scope it to this tenant. Picking a user needs
  # view_user, which Authentik only grants per user or globally, so tenant
  # admins can list all users (all are allowlisted GitHub accounts, see
  # federation.yaml). Memberships added here are not source-linked, so GitHub
  # login sync leaves them alone.
  - model: authentik_rbac.role
    id: role-tenant-{{ $n }}-admin
    identifiers: { name: tenant-{{ $n }}-admin }
    attrs:
      permissions: [authentik_core.view_user]

  # Tenant = a group carrying tenant_id/tier attributes.
  - model: authentik_core.group
    identifiers: { name: tenant-{{ $n }} }
    attrs:
      attributes: { tenant_id: {{ $n }}, tier: {{ .Values.tier }} }
    permissions:
      - { role: !KeyOf role-tenant-{{ $n }}-admin, permission: view_group }
      - { role: !KeyOf role-tenant-{{ $n }}-admin, permission: add_user_to_group }
      - { role: !KeyOf role-tenant-{{ $n }}-admin, permission: remove_user_from_group }

  # Per-tenant roles (access model: Argo CD AppProject roles, Grafana org roles,
  # k8s RoleBindings bind to these names). Emitted in the `groups` claim by the
  # built-in profile scope. tenant-{{ $n }} stays: the tenant claim above reads it.
{{- range $k := (list "admin" "developer" "viewer") }}
{{- $r := index $.Values.roles $k }}
  - model: authentik_core.group
    identifiers: { name: tenant-{{ $n }}-{{ $r.argocdGroup }} }
    attrs:
      attributes: { tenant_id: {{ $n }}, role: {{ $r.argocdGroup }} }
{{- if eq $k "admin" }}
      roles: [!KeyOf role-tenant-{{ $n }}-admin]
{{- end }}
    permissions:
      - { role: !KeyOf role-tenant-{{ $n }}-admin, permission: view_group }
      - { role: !KeyOf role-tenant-{{ $n }}-admin, permission: add_user_to_group }
      - { role: !KeyOf role-tenant-{{ $n }}-admin, permission: remove_user_from_group }
{{- end }}

  # Emits tenant_id + tier from the user's first group (by name) that has a
  # tenant_id attribute. No such group => no claims (fail closed: the gateway
  # must reject tokens without tenant_id).
  - model: authentik_providers_oauth2.scopemapping
    id: scope-tenant
    identifiers: { name: tenant }
    attrs:
      scope_name: tenant
      description: Tenant id and tier
      expression: |
        for group in request.user.groups.all().order_by("name"):
            tenant_id = group.attributes.get("tenant_id")
            if tenant_id:
                return {"tenant_id": tenant_id, "tier": group.attributes.get("tier", "free")}
        return {}
{{- if .Values.authentik.api.enabled }}

  # Public client (PKCE). client_credentials is deliberately absent: in 2026.8
  # it needs the provider's client secret (token/client_credentials.py) and runs
  # as a generated service user with no groups, hence no tenant claim. Machine
  # clients get their own confidential provider + tenant group later.
  - model: authentik_providers_oauth2.oauth2provider
    id: provider-{{ $cid }}
    identifiers: { name: {{ $cid }} }
    attrs:
      client_type: public
      client_id: {{ $cid }}
      grant_types: [authorization_code, refresh_token]
      authorization_flow: !Find [authentik_flows.flow, [slug, default-provider-authorization-implicit-consent]]
      invalidation_flow: !Find [authentik_flows.flow, [slug, default-invalidation-flow]]
      # RSA keypair => RS256; public key served at the JWKS URL above.
      signing_key: !Find [authentik_crypto.certificatekeypair, [name, authentik Self-signed Certificate]]
      # Access token is a JWT carrying the id_token claims.
      include_claims_in_id_token: true
      access_token_validity: {{ .Values.authentik.api.accessTokenValidity }}
      property_mappings:
        - !Find [authentik_providers_oauth2.scopemapping, [managed, goauthentik.io/providers/oauth2/scope-openid]]
        # Claim-less; the refresh_token grant requires this scope (token/refresh_token.py).
        - !Find [authentik_providers_oauth2.scopemapping, [managed, goauthentik.io/providers/oauth2/scope-offline_access]]
        - !KeyOf scope-tenant
      redirect_uris:
{{- range $u := .Values.authentik.api.redirectUris }}
        - { matching_mode: {{ $u.matching_mode }}, url: '{{ $u.url }}' }
{{- end }}
  - model: authentik_core.application
    identifiers: { slug: {{ $cid }} }
    attrs: { name: {{ include "tenant.apiDisplayName" . }}, provider: !KeyOf provider-{{ $cid }} }
{{- end }}
{{- end -}}
