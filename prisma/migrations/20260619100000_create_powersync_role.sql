-- Create a role/user with replication privileges for PowerSync
CREATE ROLE powersync_role WITH REPLICATION BYPASSRLS LOGIN PASSWORD 'IalwaysWIN256!';

-- Grant read-only (SELECT) access on all existing tables in the public schema
GRANT SELECT ON ALL TABLES IN SCHEMA public TO powersync_role;

-- Grant SELECT on all future tables added to the public schema
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO powersync_role;

-- Create a publication to replicate tables. The publication must be named "powersync"
CREATE PUBLICATION powersync FOR ALL TABLES;
