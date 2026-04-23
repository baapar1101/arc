-- لینک اشتراک فاکتور + فلگ چاپ QR (اجرای دستی روی دیتابیس)
-- PostgreSQL

CREATE TABLE IF NOT EXISTS document_share_links (
    id SERIAL PRIMARY KEY,
    business_id INTEGER NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    document_id INTEGER NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    created_by_user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    revoked_by_user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    code VARCHAR(16) NOT NULL,
    token_hash VARCHAR(128) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT (NOW() AT TIME ZONE 'utc'),
    expires_at TIMESTAMP NULL,
    revoked_at TIMESTAMP NULL,
    last_view_at TIMESTAMP NULL,
    view_count INTEGER NOT NULL DEFAULT 0,
    max_view_count INTEGER NULL,
    options JSON NULL,
    meta JSON NULL,
    CONSTRAINT uq_document_share_links_code UNIQUE (code)
);

CREATE INDEX IF NOT EXISTS ix_document_share_links_code ON document_share_links (code);
CREATE INDEX IF NOT EXISTS ix_document_share_links_document_id ON document_share_links (document_id);
CREATE INDEX IF NOT EXISTS ix_document_share_links_business_id ON document_share_links (business_id);

ALTER TABLE business_print_settings
    ADD COLUMN IF NOT EXISTS show_share_qr BOOLEAN NOT NULL DEFAULT FALSE;
