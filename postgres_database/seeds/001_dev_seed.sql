BEGIN;

-- NOTE: This seed is intended for development only.
-- It is idempotent via ON CONFLICT DO NOTHING and fixed UUIDs for stable references.
-- Password hashes below are placeholders for development (do NOT use in production).

-- Orgs
INSERT INTO public.organizations (id, name, slug)
VALUES
  ('11111111-1111-1111-1111-111111111111', 'Demo Organization', 'demo')
ON CONFLICT (id) DO NOTHING;

-- Users
-- bcrypt hash placeholder (commonly used in dev examples); backend will define exact hashing requirements later.
INSERT INTO public.users (id, email, password_hash, full_name, is_active, is_super_admin)
VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'admin@demo.com', '$2b$10$u9QYzD8XhYh0zJw0Oe5fUe4x7m4sJtYdQqRr2cG1v7o6rY8bH5m9e', 'Demo Admin', TRUE, TRUE),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'viewer@demo.com', '$2b$10$u9QYzD8XhYh0zJw0Oe5fUe4x7m4sJtYdQqRr2cG1v7o6rY8bH5m9e', 'Demo Viewer', TRUE, FALSE)
ON CONFLICT (id) DO NOTHING;

-- Memberships
INSERT INTO public.org_memberships (id, org_id, user_id, status)
VALUES
  ('c0c0c0c0-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'active'),
  ('c0c0c0c0-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'active')
ON CONFLICT (id) DO NOTHING;

-- Permissions catalog (global)
INSERT INTO public.permissions (id, key, description) VALUES
  ('00000000-0000-0000-0000-000000000001', 'org:read', 'Read organization details'),
  ('00000000-0000-0000-0000-000000000002', 'org:write', 'Update organization settings'),
  ('00000000-0000-0000-0000-000000000003', 'users:read', 'Read users'),
  ('00000000-0000-0000-0000-000000000004', 'users:manage', 'Manage users and memberships'),
  ('00000000-0000-0000-0000-000000000005', 'rbac:manage', 'Manage roles and permissions'),
  ('00000000-0000-0000-0000-000000000006', 'cloud_accounts:read', 'Read cloud accounts'),
  ('00000000-0000-0000-0000-000000000007', 'cloud_accounts:write', 'Create/update cloud accounts'),
  ('00000000-0000-0000-0000-000000000008', 'resources:read', 'Read resources'),
  ('00000000-0000-0000-0000-000000000009', 'costs:read', 'Read cost analytics'),
  ('00000000-0000-0000-0000-00000000000a', 'recommendations:read', 'Read optimization recommendations'),
  ('00000000-0000-0000-0000-00000000000b', 'audit:read', 'Read audit logs')
ON CONFLICT (id) DO NOTHING;

-- Roles (org-scoped)
INSERT INTO public.roles (id, org_id, name, description, is_system) VALUES
  ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', 'Owner', 'Full access to org', TRUE),
  ('44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111', 'Admin', 'Administrative access', TRUE),
  ('55555555-5555-5555-5555-555555555555', '11111111-1111-1111-1111-111111111111', 'Viewer', 'Read-only access', TRUE)
ON CONFLICT (id) DO NOTHING;

-- Role permissions
-- Owner: all
INSERT INTO public.role_permissions (role_id, org_id, permission_id) VALUES
  ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000001'),
  ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000002'),
  ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000003'),
  ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000004'),
  ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000005'),
  ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000006'),
  ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000007'),
  ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000008'),
  ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000009'),
  ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-00000000000a'),
  ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-00000000000b')
ON CONFLICT DO NOTHING;

-- Admin: everything except org:write + rbac:manage? (kept powerful for demo; adjust later as product matures)
INSERT INTO public.role_permissions (role_id, org_id, permission_id) VALUES
  ('44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000001'),
  ('44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000003'),
  ('44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000004'),
  ('44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000006'),
  ('44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000007'),
  ('44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000008'),
  ('44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000009'),
  ('44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-00000000000a'),
  ('44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-00000000000b')
ON CONFLICT DO NOTHING;

-- Viewer: read-only
INSERT INTO public.role_permissions (role_id, org_id, permission_id) VALUES
  ('55555555-5555-5555-5555-555555555555', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000001'),
  ('55555555-5555-5555-5555-555555555555', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000003'),
  ('55555555-5555-5555-5555-555555555555', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000006'),
  ('55555555-5555-5555-5555-555555555555', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000008'),
  ('55555555-5555-5555-5555-555555555555', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000009'),
  ('55555555-5555-5555-5555-555555555555', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-00000000000a')
ON CONFLICT DO NOTHING;

-- User role assignments (org-scoped)
INSERT INTO public.user_roles (org_id, user_id, role_id, assigned_by_user_id)
VALUES
  ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  ('11111111-1111-1111-1111-111111111111', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '55555555-5555-5555-5555-555555555555', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
ON CONFLICT DO NOTHING;

-- Cloud account
INSERT INTO public.cloud_accounts (id, org_id, provider, name, external_id, status, metadata)
VALUES
  ('66666666-6666-6666-6666-666666666666', '11111111-1111-1111-1111-111111111111', 'aws', 'Demo AWS Account', '123456789012', 'active', '{"environment":"dev"}'::jsonb)
ON CONFLICT (id) DO NOTHING;

-- Resources
INSERT INTO public.resources (
  id, org_id, cloud_account_id, provider, resource_type, provider_resource_id, region, name, tags, metadata
) VALUES
  ('77777777-7777-7777-7777-777777777777', '11111111-1111-1111-1111-111111111111', '66666666-6666-6666-6666-666666666666', 'aws',
   'ec2_instance', 'i-0abc123def4567890', 'us-east-1', 'demo-web-1',
   '{"app":"web","owner":"platform"}'::jsonb, '{"instanceType":"t3.medium","state":"running"}'::jsonb),
  ('88888888-8888-8888-8888-888888888888', '11111111-1111-1111-1111-111111111111', '66666666-6666-6666-6666-666666666666', 'aws',
   's3_bucket', 'demo-bucket-123', 'us-east-1', 'demo-bucket-123',
   '{"data":"logs"}'::jsonb, '{"versioning":true}'::jsonb)
ON CONFLICT (id) DO NOTHING;

-- Costs (sample daily costs)
INSERT INTO public.costs (
  id, org_id, cloud_account_id, provider, cost_date, service, amount, currency, resource_id, metadata
) VALUES
  ('99999999-9999-9999-9999-999999999991', '11111111-1111-1111-1111-111111111111', '66666666-6666-6666-6666-666666666666', 'aws',
   CURRENT_DATE - 2, 'AmazonEC2', 12.34, 'USD', '77777777-7777-7777-7777-777777777777', '{}'::jsonb),
  ('99999999-9999-9999-9999-999999999992', '11111111-1111-1111-1111-111111111111', '66666666-6666-6666-6666-666666666666', 'aws',
   CURRENT_DATE - 1, 'AmazonS3', 3.21, 'USD', '88888888-8888-8888-8888-888888888888', '{}'::jsonb),
  ('99999999-9999-9999-9999-999999999993', '11111111-1111-1111-1111-111111111111', '66666666-6666-6666-6666-666666666666', 'aws',
   CURRENT_DATE, 'AmazonEC2', 15.67, 'USD', '77777777-7777-7777-7777-777777777777', '{}'::jsonb)
ON CONFLICT (id) DO NOTHING;

-- Recommendations
INSERT INTO public.recommendations (
  id, org_id, resource_id, recommendation_type, severity, title, description, status, potential_savings, currency, metadata
) VALUES
  ('abababab-abab-abab-abab-abababababab', '11111111-1111-1111-1111-111111111111', '77777777-7777-7777-7777-777777777777',
   'rightsizing', 'high', 'Downsize EC2 instance', 'Instance appears underutilized. Consider t3.small.', 'open', 8.50, 'USD',
   '{"current":"t3.medium","recommended":"t3.small"}'::jsonb)
ON CONFLICT (id) DO NOTHING;

-- Audit log (example)
INSERT INTO public.audit_logs (
  id, org_id, actor_user_id, action, entity_type, entity_id, ip_address, user_agent, metadata
) VALUES
  ('adadadad-adad-adad-adad-adadadadadad', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'seed:init', 'organization', '11111111-1111-1111-1111-111111111111', '127.0.0.1', 'seed-script', '{"note":"Initial dev seed applied"}'::jsonb)
ON CONFLICT (id) DO NOTHING;

-- Refresh token + session (demo; token_hash is a placeholder hash)
INSERT INTO public.refresh_tokens (
  id, org_id, user_id, token_hash, expires_at, ip_address, user_agent, metadata
) VALUES
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'seed_refresh_token_hash_admin', now() + interval '30 days', '127.0.0.1', 'seed-script', '{}'::jsonb)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.sessions (
  id, org_id, user_id, refresh_token_id, last_seen_at, ip_address, user_agent, metadata
) VALUES
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'dddddddd-dddd-dddd-dddd-dddddddddddd', now(), '127.0.0.1', 'seed-script', '{}'::jsonb)
ON CONFLICT (id) DO NOTHING;

COMMIT;
