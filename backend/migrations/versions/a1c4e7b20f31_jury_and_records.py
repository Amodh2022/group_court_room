"""jury votes, criminal records, and the jury summons token

Revision ID: a1c4e7b20f31
Revises: f8f3d6dd1125
Create Date: 2026-10-12 00:00:00.000000
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = 'a1c4e7b20f31'
down_revision = 'f8f3d6dd1125'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'offenders',
        sa.Column('id', sa.Uuid(), nullable=False),
        sa.Column('owner_id', sa.Uuid(), nullable=False),
        sa.Column('slug', sa.String(length=60), nullable=False),
        sa.Column('display_name', sa.String(length=40), nullable=False),
        sa.Column('cases_total', sa.Integer(), nullable=False),
        sa.Column('convictions', sa.Integer(), nullable=False),
        sa.Column('acquittals', sa.Integer(), nullable=False),
        sa.Column('mistrials', sa.Integer(), nullable=False),
        sa.Column('current_streak', sa.Integer(), nullable=False),
        sa.Column('longest_streak', sa.Integer(), nullable=False),
        sa.Column('last_verdict_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True),
                  server_default=sa.text('(CURRENT_TIMESTAMP)'), nullable=False),
        sa.ForeignKeyConstraint(['owner_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('owner_id', 'slug', name='uq_offenders_owner_slug'),
    )
    with op.batch_alter_table('offenders', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_offenders_owner_id'), ['owner_id'], unique=False)

    op.create_table(
        'jury_votes',
        sa.Column('id', sa.Uuid(), nullable=False),
        sa.Column('case_id', sa.Uuid(), nullable=False),
        sa.Column('voter_key', sa.String(length=64), nullable=False),
        sa.Column('juror_name', sa.String(length=40), nullable=True),
        sa.Column('vote', sa.String(length=16), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True),
                  server_default=sa.text('(CURRENT_TIMESTAMP)'), nullable=False),
        sa.ForeignKeyConstraint(['case_id'], ['cases.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('case_id', 'voter_key', name='uq_jury_votes_case_voter'),
    )
    with op.batch_alter_table('jury_votes', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_jury_votes_case_id'), ['case_id'], unique=False)

    with op.batch_alter_table('cases', schema=None) as batch_op:
        batch_op.add_column(sa.Column('jury_token_hash', sa.String(length=64), nullable=True))
        batch_op.add_column(sa.Column('jury_closed_at', sa.DateTime(timezone=True), nullable=True))
        batch_op.add_column(sa.Column('plaintiff_offender_id', sa.Uuid(), nullable=True))
        batch_op.add_column(sa.Column('defendant_offender_id', sa.Uuid(), nullable=True))
        batch_op.create_unique_constraint('uq_cases_jury_token_hash', ['jury_token_hash'])
        batch_op.create_index('ix_cases_jury_token_hash', ['jury_token_hash'], unique=False)
        batch_op.create_foreign_key(
            'fk_cases_plaintiff_offender', 'offenders',
            ['plaintiff_offender_id'], ['id'], ondelete='SET NULL',
        )
        batch_op.create_foreign_key(
            'fk_cases_defendant_offender', 'offenders',
            ['defendant_offender_id'], ['id'], ondelete='SET NULL',
        )


def downgrade() -> None:
    with op.batch_alter_table('cases', schema=None) as batch_op:
        batch_op.drop_constraint('fk_cases_defendant_offender', type_='foreignkey')
        batch_op.drop_constraint('fk_cases_plaintiff_offender', type_='foreignkey')
        batch_op.drop_index('ix_cases_jury_token_hash')
        batch_op.drop_constraint('uq_cases_jury_token_hash', type_='unique')
        batch_op.drop_column('defendant_offender_id')
        batch_op.drop_column('plaintiff_offender_id')
        batch_op.drop_column('jury_closed_at')
        batch_op.drop_column('jury_token_hash')

    with op.batch_alter_table('jury_votes', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_jury_votes_case_id'))
    op.drop_table('jury_votes')

    with op.batch_alter_table('offenders', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_offenders_owner_id'))
    op.drop_table('offenders')
