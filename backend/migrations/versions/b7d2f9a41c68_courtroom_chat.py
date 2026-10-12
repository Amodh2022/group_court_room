"""courtroom chat messages

Revision ID: b7d2f9a41c68
Revises: a1c4e7b20f31
Create Date: 2026-10-12 15:30:00.000000
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = 'b7d2f9a41c68'
down_revision = 'a1c4e7b20f31'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'chat_messages',
        sa.Column('id', sa.Uuid(), nullable=False),
        sa.Column('case_id', sa.Uuid(), nullable=False),
        sa.Column('n', sa.Integer(), nullable=False),
        sa.Column('kind', sa.String(length=12), nullable=False),
        sa.Column('author_name', sa.String(length=40), nullable=False),
        sa.Column('author_ref', sa.String(length=16), nullable=False),
        sa.Column('body', sa.Text(), nullable=False),
        sa.Column('meta', sa.JSON().with_variant(
            sa.dialects.postgresql.JSONB(), 'postgresql'), nullable=True),
        sa.Column('hidden_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True),
                  server_default=sa.text('(CURRENT_TIMESTAMP)'), nullable=False),
        sa.ForeignKeyConstraint(['case_id'], ['cases.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('case_id', 'n', name='uq_chat_case_n'),
    )
    with op.batch_alter_table('chat_messages', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_chat_messages_case_id'), ['case_id'], unique=False)
        batch_op.create_index(
            'ix_chat_case_author_created', ['case_id', 'author_ref', 'created_at'], unique=False
        )


def downgrade() -> None:
    with op.batch_alter_table('chat_messages', schema=None) as batch_op:
        batch_op.drop_index('ix_chat_case_author_created')
        batch_op.drop_index(batch_op.f('ix_chat_messages_case_id'))
    op.drop_table('chat_messages')
