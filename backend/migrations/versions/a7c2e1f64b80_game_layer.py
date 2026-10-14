"""the game layer: xp, coins, streaks, quests, badges

Revision ID: a7c2e1f64b80
Revises: e5b1c7d93a24
"""
import sqlalchemy as sa
from alembic import op

revision = 'a7c2e1f64b80'
down_revision = 'e5b1c7d93a24'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'player_profiles',
        sa.Column('user_id', sa.Uuid(), nullable=False),
        sa.Column('xp', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('coins', sa.Integer(), nullable=False, server_default='100'),
        sa.Column('streak_days', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('longest_streak_days', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('last_active_on', sa.Date(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True),
                  server_default=sa.text('(CURRENT_TIMESTAMP)'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True),
                  server_default=sa.text('(CURRENT_TIMESTAMP)'), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('user_id'),
    )

    op.create_table(
        'player_badges',
        sa.Column('id', sa.Uuid(), nullable=False),
        sa.Column('user_id', sa.Uuid(), nullable=False),
        sa.Column('code', sa.String(length=40), nullable=False),
        sa.Column('awarded_at', sa.DateTime(timezone=True),
                  server_default=sa.text('(CURRENT_TIMESTAMP)'), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('user_id', 'code', name='uq_player_badges_user_code'),
    )
    with op.batch_alter_table('player_badges', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_player_badges_user_id'), ['user_id'], unique=False)

    op.create_table(
        'daily_quests',
        sa.Column('id', sa.Uuid(), nullable=False),
        sa.Column('user_id', sa.Uuid(), nullable=False),
        sa.Column('quest_date', sa.Date(), nullable=False),
        sa.Column('code', sa.String(length=40), nullable=False),
        sa.Column('progress', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('target', sa.Integer(), nullable=False, server_default='1'),
        sa.Column('xp', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('completed_at', sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('user_id', 'quest_date', 'code', name='uq_daily_quests_slot'),
    )
    with op.batch_alter_table('daily_quests', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_daily_quests_user_id'), ['user_id'], unique=False)
        batch_op.create_index(
            batch_op.f('ix_daily_quests_quest_date'), ['quest_date'], unique=False
        )

    op.create_table(
        'game_events',
        sa.Column('id', sa.Uuid(), nullable=False),
        sa.Column('user_id', sa.Uuid(), nullable=False),
        sa.Column('case_id', sa.Uuid(), nullable=True),
        sa.Column('kind', sa.String(length=40), nullable=False),
        sa.Column('detail', sa.String(length=120), nullable=False, server_default=''),
        sa.Column('xp', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('coins', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('badge_code', sa.String(length=40), nullable=True),
        sa.Column('level_reached', sa.Integer(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True),
                  server_default=sa.text('(CURRENT_TIMESTAMP)'), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['case_id'], ['cases.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    with op.batch_alter_table('game_events', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_game_events_user_id'), ['user_id'], unique=False)
        batch_op.create_index(batch_op.f('ix_game_events_case_id'), ['case_id'], unique=False)

    with op.batch_alter_table('cases', schema=None) as batch_op:
        batch_op.add_column(
            sa.Column('petty_level', sa.Integer(), nullable=False, server_default='1')
        )
        batch_op.add_column(
            sa.Column('game_settled_at', sa.DateTime(timezone=True), nullable=True)
        )

    with op.batch_alter_table('jury_votes', schema=None) as batch_op:
        batch_op.add_column(sa.Column('juror_user_id', sa.Uuid(), nullable=True))
        batch_op.create_foreign_key(
            'fk_jury_votes_juror_user', 'users', ['juror_user_id'], ['id'], ondelete='SET NULL'
        )
        batch_op.create_index(
            batch_op.f('ix_jury_votes_juror_user_id'), ['juror_user_id'], unique=False
        )


def downgrade() -> None:
    with op.batch_alter_table('jury_votes', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_jury_votes_juror_user_id'))
        batch_op.drop_constraint('fk_jury_votes_juror_user', type_='foreignkey')
        batch_op.drop_column('juror_user_id')

    with op.batch_alter_table('cases', schema=None) as batch_op:
        batch_op.drop_column('game_settled_at')
        batch_op.drop_column('petty_level')

    op.drop_table('game_events')
    op.drop_table('daily_quests')
    op.drop_table('player_badges')
    op.drop_table('player_profiles')
