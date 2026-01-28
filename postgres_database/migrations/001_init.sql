BEGIN;

-- Extensions used by this schema:
-- - pgcrypto: gen_random_uuid()
-- - citext: case-insensitive unique emails
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

-- Generic "updated_at" trigger helper
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Enums (created in an idempotent way)
DO $$
BEGIN
  CREATE TYPE public.cloud_provider AS ENUM ('aws', 'azure', 'gcp');
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE public.membership_status AS ENUM ('active', 'invited', 'disabled');
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE public.recommendation_status AS ENUM ('open', 'snoozed', 'applied', 'dismissed');
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE public.recommendation_severity AS ENUM ('low', 'medium', 'high', 'critical');
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE public.cloud_account_status AS ENUM ('active', 'disabled', 'error');
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;

-- USERS
CREATE TABLE IF NOT EXISTS public.users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email CITEXT NOT NULL,
  password_hash TEXT NOT NULL,
  full_name TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  is_super_admin BOOLEAN NOT NULL DEFAULT FALSE,
  last_login_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT users_email_not_blank CHECK (length(trim(email::text)) > 0)
);

-- Email uniqueness (case-insensitive via CITEXT)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'users_email_unique'
  ) THEN
    ALTER TABLE public.users
      ADD CONSTRAINT users_email_unique UNIQUE (email);
  END IF;
END $$;

DROP TRIGGER IF EXISTS trg_users_set_updated_at ON public.users;
CREATE TRIGGER trg_users_set_updated_at
BEFORE UPDATE ON public.users
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- ORGANIZATIONS
CREATE TABLE IF NOT EXISTS public.organizations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  slug TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT organizations_slug_not_blank CHECK (length(trim(slug)) > 0)
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'organizations_slug_unique'
  ) THEN
    ALTER TABLE public.organizations
      ADD CONSTRAINT organizations_slug_unique UNIQUE (slug);
  END IF;
END $$;

DROP TRIGGER IF EXISTS trg_organizations_set_updated_at ON public.organizations;
CREATE TRIGGER trg_organizations_set_updated_at
BEFORE UPDATE ON public.organizations
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- ORG MEMBERSHIPS
CREATE TABLE IF NOT EXISTS public.org_memberships (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  status public.membership_status NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'org_memberships_org_user_unique'
  ) THEN
    ALTER TABLE public.org_memberships
      ADD CONSTRAINT org_memberships_org_user_unique UNIQUE (org_id, user_id);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_org_memberships_org_id ON public.org_memberships(org_id);
CREATE INDEX IF NOT EXISTS idx_org_memberships_user_id ON public.org_memberships(user_id);

DROP TRIGGER IF EXISTS trg_org_memberships_set_updated_at ON public.org_memberships;
CREATE TRIGGER trg_org_memberships_set_updated_at
BEFORE UPDATE ON public.org_memberships
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- PERMISSIONS (global catalog)
CREATE TABLE IF NOT EXISTS public.permissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  key TEXT NOT NULL,
  description TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT permissions_key_not_blank CHECK (length(trim(key)) > 0)
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'permissions_key_unique'
  ) THEN
    ALTER TABLE public.permissions
      ADD CONSTRAINT permissions_key_unique UNIQUE (key);
  END IF;
END $$;

DROP TRIGGER IF EXISTS trg_permissions_set_updated_at ON public.permissions;
CREATE TRIGGER trg_permissions_set_updated_at
BEFORE UPDATE ON public.permissions
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- ROLES (org-scoped; supports strict tenant isolation)
CREATE TABLE IF NOT EXISTS public.roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  is_system BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT roles_name_not_blank CHECK (length(trim(name)) > 0),
  CONSTRAINT roles_id_org_unique UNIQUE (id, org_id)
);

-- Case-insensitive uniqueness of role names within an org
CREATE UNIQUE INDEX IF NOT EXISTS roles_org_name_lower_uq
  ON public.roles (org_id, lower(name));

CREATE INDEX IF NOT EXISTS idx_roles_org_id ON public.roles(org_id);

DROP TRIGGER IF EXISTS trg_roles_set_updated_at ON public.roles;
CREATE TRIGGER trg_roles_set_updated_at
BEFORE UPDATE ON public.roles
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- ROLE PERMISSIONS (org-scoped via composite FK to roles)
CREATE TABLE IF NOT EXISTS public.role_permissions (
  role_id UUID NOT NULL,
  org_id UUID NOT NULL,
  permission_id UUID NOT NULL REFERENCES public.permissions(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (role_id, org_id, permission_id),
  CONSTRAINT role_permissions_role_fk
    FOREIGN KEY (role_id, org_id) REFERENCES public.roles(id, org_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_role_permissions_org_id ON public.role_permissions(org_id);
CREATE INDEX IF NOT EXISTS idx_role_permissions_permission_id ON public.role_permissions(permission_id);

-- USER ROLES (assignment is scoped to org; enforced membership requirement)
CREATE TABLE IF NOT EXISTS public.user_roles (
  org_id UUID NOT NULL,
  user_id UUID NOT NULL,
  role_id UUID NOT NULL,
  assigned_by_user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (org_id, user_id, role_id),
  CONSTRAINT user_roles_membership_fk
    FOREIGN KEY (org_id, user_id) REFERENCES public.org_memberships(org_id, user_id) ON DELETE CASCADE,
  CONSTRAINT user_roles_role_fk
    FOREIGN KEY (role_id, org_id) REFERENCES public.roles(id, org_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_user_roles_org_user ON public.user_roles(org_id, user_id);
CREATE INDEX IF NOT EXISTS idx_user_roles_user_id ON public.user_roles(user_id);

-- CLOUD ACCOUNTS
CREATE TABLE IF NOT EXISTS public.cloud_accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  provider public.cloud_provider NOT NULL,
  name TEXT NOT NULL,
  external_id TEXT NOT NULL,
  status public.cloud_account_status NOT NULL DEFAULT 'active',
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT cloud_accounts_name_not_blank CHECK (length(trim(name)) > 0),
  CONSTRAINT cloud_accounts_id_org_unique UNIQUE (id, org_id),
  CONSTRAINT cloud_accounts_org_provider_external_unique UNIQUE (org_id, provider, external_id)
);

CREATE INDEX IF NOT EXISTS idx_cloud_accounts_org_id ON public.cloud_accounts(org_id);
CREATE INDEX IF NOT EXISTS idx_cloud_accounts_org_provider ON public.cloud_accounts(org_id, provider);

DROP TRIGGER IF EXISTS trg_cloud_accounts_set_updated_at ON public.cloud_accounts;
CREATE TRIGGER trg_cloud_accounts_set_updated_at
BEFORE UPDATE ON public.cloud_accounts
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- RESOURCES (org isolated, and forced to match org via composite FK to cloud_accounts)
CREATE TABLE IF NOT EXISTS public.resources (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID NOT NULL,
  cloud_account_id UUID NOT NULL,
  provider public.cloud_provider NOT NULL,
  resource_type TEXT NOT NULL,
  provider_resource_id TEXT NOT NULL,
  region TEXT,
  name TEXT,
  tags JSONB NOT NULL DEFAULT '{}'::jsonb,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  discovered_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT resources_id_org_unique UNIQUE (id, org_id),
  CONSTRAINT resources_org_provider_resource_unique UNIQUE (org_id, provider, provider_resource_id),
  CONSTRAINT resources_cloud_account_fk
    FOREIGN KEY (cloud_account_id, org_id) REFERENCES public.cloud_accounts(id, org_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_resources_org_id ON public.resources(org_id);
CREATE INDEX IF NOT EXISTS idx_resources_org_cloud_account ON public.resources(org_id, cloud_account_id);
CREATE INDEX IF NOT EXISTS idx_resources_org_type ON public.resources(org_id, resource_type);
CREATE INDEX IF NOT EXISTS idx_resources_org_provider ON public.resources(org_id, provider);

-- Common query support for tag filtering
CREATE INDEX IF NOT EXISTS idx_resources_tags_gin ON public.resources USING GIN (tags);
CREATE INDEX IF NOT EXISTS idx_resources_metadata_gin ON public.resources USING GIN (metadata);

DROP TRIGGER IF EXISTS trg_resources_set_updated_at ON public.resources;
CREATE TRIGGER trg_resources_set_updated_at
BEFORE UPDATE ON public.resources
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- COSTS (daily spend facts; org isolated; optionally linked to resource)
CREATE TABLE IF NOT EXISTS public.costs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID NOT NULL,
  cloud_account_id UUID NOT NULL,
  provider public.cloud_provider NOT NULL,
  cost_date DATE NOT NULL,
  service TEXT,
  amount NUMERIC(12,2) NOT NULL,
  currency TEXT NOT NULL DEFAULT 'USD',
  resource_id UUID,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT costs_amount_nonnegative CHECK (amount >= 0),
  CONSTRAINT costs_cloud_account_fk
    FOREIGN KEY (cloud_account_id, org_id) REFERENCES public.cloud_accounts(id, org_id) ON DELETE CASCADE,
  CONSTRAINT costs_resource_fk
    FOREIGN KEY (resource_id, org_id) REFERENCES public.resources(id, org_id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_costs_org_date ON public.costs(org_id, cost_date);
CREATE INDEX IF NOT EXISTS idx_costs_org_account_date ON public.costs(org_id, cloud_account_id, cost_date);
CREATE INDEX IF NOT EXISTS idx_costs_org_service_date ON public.costs(org_id, service, cost_date);

DROP TRIGGER IF EXISTS trg_costs_set_updated_at ON public.costs;
CREATE TRIGGER trg_costs_set_updated_at
BEFORE UPDATE ON public.costs
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- RECOMMENDATIONS (org isolated; linked to resource)
CREATE TABLE IF NOT EXISTS public.recommendations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID NOT NULL,
  resource_id UUID NOT NULL,
  recommendation_type TEXT NOT NULL,
  severity public.recommendation_severity NOT NULL DEFAULT 'medium',
  title TEXT NOT NULL,
  description TEXT,
  status public.recommendation_status NOT NULL DEFAULT 'open',
  potential_savings NUMERIC(12,2) NOT NULL DEFAULT 0,
  currency TEXT NOT NULL DEFAULT 'USD',
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT recommendations_savings_nonnegative CHECK (potential_savings >= 0),
  CONSTRAINT recommendations_resource_fk
    FOREIGN KEY (resource_id, org_id) REFERENCES public.resources(id, org_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_recommendations_org_status ON public.recommendations(org_id, status);
CREATE INDEX IF NOT EXISTS idx_recommendations_org_severity ON public.recommendations(org_id, severity);
CREATE INDEX IF NOT EXISTS idx_recommendations_org_created_at ON public.recommendations(org_id, created_at DESC);

DROP TRIGGER IF EXISTS trg_recommendations_set_updated_at ON public.recommendations;
CREATE TRIGGER trg_recommendations_set_updated_at
BEFORE UPDATE ON public.recommendations
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- AUDIT LOGS (append-only; org isolated)
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  actor_user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  action TEXT NOT NULL,
  entity_type TEXT,
  entity_id UUID,
  ip_address INET,
  user_agent TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT audit_logs_action_not_blank CHECK (length(trim(action)) > 0)
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_org_created_at ON public.audit_logs(org_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_org_actor ON public.audit_logs(org_id, actor_user_id);

-- REFRESH TOKENS (for JWT refresh flow; store hashes only)
CREATE TABLE IF NOT EXISTS public.refresh_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ,
  replaced_by_token_id UUID REFERENCES public.refresh_tokens(id) ON DELETE SET NULL,
  ip_address INET,
  user_agent TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'refresh_tokens_token_hash_unique'
  ) THEN
    ALTER TABLE public.refresh_tokens
      ADD CONSTRAINT refresh_tokens_token_hash_unique UNIQUE (token_hash);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user_expires ON public.refresh_tokens(user_id, expires_at DESC);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_org_user ON public.refresh_tokens(org_id, user_id);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_expires_at ON public.refresh_tokens(expires_at);

-- SESSIONS (optional session metadata; tied 1:1 to a refresh token)
CREATE TABLE IF NOT EXISTS public.sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  refresh_token_id UUID UNIQUE REFERENCES public.refresh_tokens(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  revoked_at TIMESTAMPTZ,
  ip_address INET,
  user_agent TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_sessions_org_user ON public.sessions(org_id, user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_org_last_seen ON public.sessions(org_id, last_seen_at DESC);

COMMIT;
