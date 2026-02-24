-- ============================================================================
-- Fix database permissions after restore
-- ============================================================================
-- بعد از ریستور دیتابیس، کاربر hesabix ممکن است دسترسی به جداول را از دست بدهد.
-- این اسکریپت دسترسی‌های لازم را به hesabix برمی‌گرداند.
--
-- نحوه اجرا (با کاربر postgres یا superuser):
--   psql -U postgres -d hesabix -f scripts/fix_db_permissions_after_restore.sql
--
-- یا در psql:
--   \i /opt/hesabix/app/scripts/fix_db_permissions_after_restore.sql
-- ============================================================================

-- دسترسی روی تمام جداول و sequences در schema public
-- (در صورت restore کامل، ممکن است سایر جداول هم دسترسی از دست داده باشند)
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public')
    LOOP
        EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO hesabix', r.tablename);
    END LOOP;
END$$;

-- Sequences
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT sequencename FROM pg_sequences WHERE schemaname = 'public')
    LOOP
        EXECUTE format('GRANT USAGE, SELECT ON SEQUENCE public.%I TO hesabix', r.sequencename);
    END LOOP;
END$$;
