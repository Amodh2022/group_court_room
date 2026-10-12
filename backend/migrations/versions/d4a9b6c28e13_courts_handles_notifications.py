"""handles, courts, case members, notifications

Revision ID: d4a9b6c28e13
Revises: c3e8a5d71f92
"""
import sqlalchemy as sa
from alembic import op

revision = 'd4a9b6c28e13'
down_revision = 'c3e8a5d71f92'
branch_labels = None
depends_on = None

_TS = dict(server_default=sa.text('(CURRENT_TIMESTAMP)'), nullable=False)


def upgrade() -> None:
    with op.batch_alter_table('users', schema=None) as batch_op:
        batch_op.add_column(sa.Column('handle', sa.String(length=20), nullable=True))
        batch_op.create_index(batch_op.f('ix_users_handle'), ['handle'], unique=True)

    op.create_table(
        'courts',
        sa.Column('id', sa.Uuid(), nullable=False),
        sa.Column('name', sa.String(length=40), nullable=False),
        sa.Column('invite_code', sa.String(length=16), nullable=False),
        sa.Column('owner_id', sa.Uuid(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), **_TS),
        sa.ForeignKeyConstraint(['owner_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_courts_invite_code', 'courts', ['invite_code'], unique=True)
    op.create_index('ix_courts_owner_id', 'courts', ['owner_id'])

    op.create_table(
        'court_members',
        sa.Column('id', sa.Uuid(), nullable=False),
        sa.Column('court_id', sa.Uuid(), nullable=False),
        sa.Column('user_id', sa.Uuid(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), **_TS),
        sa.ForeignKeyConstraint(['court_id'], ['courts.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('court_id', 'user_id', name='uq_court_member'),
    )
    op.create_index('ix_court_members_court_id', 'court_members', ['court_id'])
    op.create_index('ix_court_members_user_id', 'court_members', ['user_id'])

    with op.batch_alter_table('cases', schema=None) as batch_op:
        batch_op.add_column(sa.Column('court_id', sa.Uuid(), nullable=True))
        batch_op.create_index(batch_op.f('ix_cases_court_id'), ['court_id'], unique=False)
        batch_op.create_foreign_key(
            'fk_cases_court_id', 'courts', ['court_id'], ['id'], ondelete='SET NULL'
        )

    op.create_table(
        'case_members',
        sa.Column('id', sa.Uuid(), nullable=False),
        sa.Column('case_id', sa.Uuid(), nullable=False),
        sa.Column('user_id', sa.Uuid(), nullable=False),
        sa.Column('role', sa.String(length=16), nullable=False),
        sa.Column('access_token', sa.String(length=128), nullable=False),
        sa.Column('token_hash', sa.String(length=64), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), **_TS),
        sa.ForeignKeyConstraint(['case_id'], ['cases.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('case_id', 'user_id', name='uq_case_member'),
    )
    op.create_index('ix_case_members_case_id', 'case_members', ['case_id'])
    op.create_index('ix_case_members_user_id', 'case_members', ['user_id'])
    op.create_index('ix_case_members_token_hash', 'case_members', ['token_hash'], unique=True)

    op.create_table(
        'notifications',
        sa.Column('id', sa.Uuid(), nullable=False),
        sa.Column('user_id', sa.Uuid(), nullable=False),
        sa.Column('kind', sa.String(length=24), nullable=False),
        sa.Column('text', sa.Text(), nullable=False),
        sa.Column('case_id', sa.Uuid(), nullable=True),
        sa.Column('court_id', sa.Uuid(), nullable=True),
        sa.Column('read', sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column('created_at', sa.DateTime(timezone=True), **_TS),
        sa.Column('read_at', sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['case_id'], ['cases.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['court_id'], ['courts.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_notifications_user_id', 'notifications', ['user_id'])


def downgrade() -> None:
    op.drop_index('ix_notifications_user_id', table_name='notifications')
    op.drop_table('notifications')
    op.drop_table('case_members')
    with op.batch_alter_table('cases', schema=None) as batch_op:
        batch_op.drop_constraint('fk_cases_court_id', type_='foreignkey')
        batch_op.drop_index(batch_op.f('ix_cases_court_id'))
        batch_op.drop_column('court_id')
    op.drop_table('court_members')
    op.drop_table('courts')
    with op.batch_alter_table('users', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_users_handle'))
        batch_op.drop_column('handle')
