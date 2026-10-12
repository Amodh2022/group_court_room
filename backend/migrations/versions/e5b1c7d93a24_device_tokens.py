"""push device tokens

Revision ID: e5b1c7d93a24
Revises: d4a9b6c28e13
"""
import sqlalchemy as sa
from alembic import op

revision = 'e5b1c7d93a24'
down_revision = 'd4a9b6c28e13'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'device_tokens',
        sa.Column('id', sa.Uuid(), nullable=False),
        sa.Column('user_id', sa.Uuid(), nullable=False),
        sa.Column('token', sa.String(length=512), nullable=False),
        sa.Column('platform', sa.String(length=16), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True),
                  server_default=sa.text('(CURRENT_TIMESTAMP)'), nullable=False),
        sa.Column('last_seen_at', sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    with op.batch_alter_table('device_tokens', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_device_tokens_user_id'), ['user_id'], unique=False)
        batch_op.create_index(batch_op.f('ix_device_tokens_token'), ['token'], unique=True)


def downgrade() -> None:
    with op.batch_alter_table('device_tokens', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_device_tokens_token'))
        batch_op.drop_index(batch_op.f('ix_device_tokens_user_id'))
    op.drop_table('device_tokens')
