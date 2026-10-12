"""email/password accounts

Revision ID: c3e8a5d71f92
Revises: b7d2f9a41c68
"""
import sqlalchemy as sa
from alembic import op

revision = 'c3e8a5d71f92'
down_revision = 'b7d2f9a41c68'
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table('users', schema=None) as batch_op:
        batch_op.add_column(sa.Column('email', sa.String(), nullable=True))
        batch_op.add_column(sa.Column('password_hash', sa.String(), nullable=True))
        batch_op.create_index(batch_op.f('ix_users_email'), ['email'], unique=True)


def downgrade() -> None:
    with op.batch_alter_table('users', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_users_email'))
        batch_op.drop_column('password_hash')
        batch_op.drop_column('email')
