"""جداول احراز هویت: api_keys, captchas, password_resets, email_verification_tokens, mobile_verification_tokens, otp_login_sessions"""
from alembic import op
import sqlalchemy as sa


def upgrade():
    # جدول api_keys
    op.create_table(
        'api_keys',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('key_hash', sa.String(length=128), nullable=False),
        sa.Column('key_type', sa.String(length=16), nullable=False),
        sa.Column('name', sa.String(length=100), nullable=True),
        sa.Column('scopes', sa.String(length=500), nullable=True),
        sa.Column('device_id', sa.String(length=100), nullable=True),
        sa.Column('user_agent', sa.String(length=255), nullable=True),
        sa.Column('ip', sa.String(length=64), nullable=True),
        sa.Column('expires_at', sa.DateTime(), nullable=True),
        sa.Column('last_used_at', sa.DateTime(), nullable=True),
        sa.Column('revoked_at', sa.DateTime(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_api_keys_user_id'), 'api_keys', ['user_id'], unique=False)
    op.create_index(op.f('ix_api_keys_key_hash'), 'api_keys', ['key_hash'], unique=True)

    # جدول captchas
    op.create_table(
        'captchas',
        sa.Column('id', sa.String(length=40), nullable=False),
        sa.Column('code_hash', sa.String(length=128), nullable=False),
        sa.Column('expires_at', sa.DateTime(), nullable=False),
        sa.Column('attempts', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.PrimaryKeyConstraint('id')
    )

    # جدول password_resets
    op.create_table(
        'password_resets',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('token_hash', sa.String(length=128), nullable=False),
        sa.Column('expires_at', sa.DateTime(), nullable=False),
        sa.Column('used_at', sa.DateTime(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_password_resets_user_id'), 'password_resets', ['user_id'], unique=False)
    op.create_index(op.f('ix_password_resets_token_hash'), 'password_resets', ['token_hash'], unique=True)

    # جدول email_verification_tokens
    op.create_table(
        'email_verification_tokens',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('email', sa.String(length=255), nullable=False),
        sa.Column('token_hash', sa.String(length=128), nullable=False),
        sa.Column('expires_at', sa.DateTime(), nullable=False),
        sa.Column('used_at', sa.DateTime(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_email_verification_tokens_user_id'), 'email_verification_tokens', ['user_id'], unique=False)
    op.create_index(op.f('ix_email_verification_tokens_email'), 'email_verification_tokens', ['email'], unique=False)
    op.create_index(op.f('ix_email_verification_tokens_token_hash'), 'email_verification_tokens', ['token_hash'], unique=True)

    # جدول mobile_verification_tokens
    op.create_table(
        'mobile_verification_tokens',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('mobile', sa.String(length=32), nullable=False),
        sa.Column('otp_code_hash', sa.String(length=128), nullable=False),
        sa.Column('expires_at', sa.DateTime(), nullable=False),
        sa.Column('verified_at', sa.DateTime(), nullable=True),
        sa.Column('attempts', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_mobile_verification_tokens_user_id'), 'mobile_verification_tokens', ['user_id'], unique=False)
    op.create_index(op.f('ix_mobile_verification_tokens_mobile'), 'mobile_verification_tokens', ['mobile'], unique=False)
    op.create_index(op.f('ix_mobile_verification_tokens_otp_code_hash'), 'mobile_verification_tokens', ['otp_code_hash'], unique=False)
    op.create_index(op.f('ix_mobile_verification_tokens_expires_at'), 'mobile_verification_tokens', ['expires_at'], unique=False)
    op.create_index('ix_mobile_verification_validity', 'mobile_verification_tokens', ['expires_at', 'verified_at'], unique=False)

    # جدول otp_login_sessions
    op.create_table(
        'otp_login_sessions',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('session_id', sa.String(length=128), nullable=False),
        sa.Column('mobile', sa.String(length=32), nullable=True),
        sa.Column('email', sa.String(length=255), nullable=True),
        sa.Column('channel', sa.String(length=20), nullable=False, server_default='sms'),
        sa.Column('user_id', sa.Integer(), nullable=True),
        sa.Column('otp_code_hash', sa.String(length=128), nullable=False),
        sa.Column('attempts', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('expires_at', sa.DateTime(), nullable=False),
        sa.Column('verified_at', sa.DateTime(), nullable=True),
        sa.Column('ip_address', sa.String(length=64), nullable=True),
        sa.Column('user_agent', sa.String(length=255), nullable=True),
        sa.Column('last_otp_sent_at', sa.DateTime(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_otp_login_sessions_session_id'), 'otp_login_sessions', ['session_id'], unique=True)
    op.create_index(op.f('ix_otp_login_sessions_mobile'), 'otp_login_sessions', ['mobile'], unique=False)
    op.create_index(op.f('ix_otp_login_sessions_email'), 'otp_login_sessions', ['email'], unique=False)
    op.create_index(op.f('ix_otp_login_sessions_user_id'), 'otp_login_sessions', ['user_id'], unique=False)
    op.create_index(op.f('ix_otp_login_sessions_expires_at'), 'otp_login_sessions', ['expires_at'], unique=False)
    op.create_index('ix_otp_login_validity', 'otp_login_sessions', ['expires_at', 'verified_at'], unique=False)


def downgrade():
    op.drop_index('ix_otp_login_validity', table_name='otp_login_sessions')
    op.drop_index(op.f('ix_otp_login_sessions_expires_at'), table_name='otp_login_sessions')
    op.drop_index(op.f('ix_otp_login_sessions_user_id'), table_name='otp_login_sessions')
    op.drop_index(op.f('ix_otp_login_sessions_email'), table_name='otp_login_sessions')
    op.drop_index(op.f('ix_otp_login_sessions_mobile'), table_name='otp_login_sessions')
    op.drop_index(op.f('ix_otp_login_sessions_session_id'), table_name='otp_login_sessions')
    op.drop_table('otp_login_sessions')
    
    op.drop_index('ix_mobile_verification_validity', table_name='mobile_verification_tokens')
    op.drop_index(op.f('ix_mobile_verification_tokens_expires_at'), table_name='mobile_verification_tokens')
    op.drop_index(op.f('ix_mobile_verification_tokens_otp_code_hash'), table_name='mobile_verification_tokens')
    op.drop_index(op.f('ix_mobile_verification_tokens_mobile'), table_name='mobile_verification_tokens')
    op.drop_index(op.f('ix_mobile_verification_tokens_user_id'), table_name='mobile_verification_tokens')
    op.drop_table('mobile_verification_tokens')
    
    op.drop_index(op.f('ix_email_verification_tokens_token_hash'), table_name='email_verification_tokens')
    op.drop_index(op.f('ix_email_verification_tokens_email'), table_name='email_verification_tokens')
    op.drop_index(op.f('ix_email_verification_tokens_user_id'), table_name='email_verification_tokens')
    op.drop_table('email_verification_tokens')
    
    op.drop_index(op.f('ix_password_resets_token_hash'), table_name='password_resets')
    op.drop_index(op.f('ix_password_resets_user_id'), table_name='password_resets')
    op.drop_table('password_resets')
    
    op.drop_table('captchas')
    
    op.drop_index(op.f('ix_api_keys_key_hash'), table_name='api_keys')
    op.drop_index(op.f('ix_api_keys_user_id'), table_name='api_keys')
    op.drop_table('api_keys')

