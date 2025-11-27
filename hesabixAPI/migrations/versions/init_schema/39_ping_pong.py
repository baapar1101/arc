"""جدول ping_pong_scores"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


def upgrade():
    op.create_table(
        'ping_pong_scores',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('score', sa.Integer(), nullable=False),
        sa.Column('survival_time', sa.Integer(), nullable=False, comment='زمان زنده ماندن به ثانیه'),
        sa.Column('hero_mode_uses', sa.Integer(), nullable=False, server_default='0', comment='تعداد استفاده از حالت قهرمان'),
        sa.Column('difficulty_level', sa.Float(), nullable=False, server_default='1.0', comment='آخرین سطح سختی'),
        sa.Column('played_at', sa.DateTime(), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_ping_pong_scores_user_id'), 'ping_pong_scores', ['user_id'], unique=False)
    op.create_index(op.f('ix_ping_pong_scores_score'), 'ping_pong_scores', ['score'], unique=False)
    op.create_index(op.f('ix_ping_pong_scores_played_at'), 'ping_pong_scores', ['played_at'], unique=False)
    # Indexes with postgresql_ops
    op.create_index('idx_ping_pong_score', 'ping_pong_scores', ['score'], unique=False, postgresql_ops={'score': 'DESC'})
    op.create_index('idx_ping_pong_user_score', 'ping_pong_scores', ['user_id', 'score'], unique=False)


def downgrade():
    op.drop_index('idx_ping_pong_user_score', table_name='ping_pong_scores')
    op.drop_index('idx_ping_pong_score', table_name='ping_pong_scores')
    op.drop_index(op.f('ix_ping_pong_scores_played_at'), table_name='ping_pong_scores')
    op.drop_index(op.f('ix_ping_pong_scores_score'), table_name='ping_pong_scores')
    op.drop_index(op.f('ix_ping_pong_scores_user_id'), table_name='ping_pong_scores')
    op.drop_table('ping_pong_scores')

