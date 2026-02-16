"""add change_at and status_reason in Loan and Purchase

Revision ID: 9641df439cf6
Revises: 6f5525675ad6
Create Date: 2026-01-26 15:33:20.498792

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '9641df439cf6'
down_revision: Union[str, None] = '6f5525675ad6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade():
    op.add_column("loans", sa.Column("status_changed_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("loans", sa.Column("status_reason", sa.Text(), nullable=True))

    op.add_column("purchases", sa.Column("status_changed_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("purchases", sa.Column("status_reason", sa.Text(), nullable=True))

def downgrade():
    op.drop_column("purchases", "status_reason")
    op.drop_column("purchases", "status_changed_at")
    op.drop_column("loans", "status_reason")
    op.drop_column("loans", "status_changed_at")
