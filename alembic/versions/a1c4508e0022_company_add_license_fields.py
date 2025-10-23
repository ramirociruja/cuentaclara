"""company:add_license_fields

Revision ID: a1c4508e0022
Revises: 93472bbc5416
Create Date: 2025-10-22 02:12:01.577508

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a1c4508e0022'
down_revision: Union[str, None] = '93472bbc5416'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade():
    op.add_column("companies", sa.Column("service_status", sa.String(length=32), nullable=False, server_default="active"))
    op.add_column("companies", sa.Column("license_expires_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("companies", sa.Column("suspended_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("companies", sa.Column("suspension_reason", sa.String(length=255), nullable=True))
    op.create_index("ix_companies_service_status", "companies", ["service_status"])

def downgrade():
    op.drop_index("ix_companies_service_status", table_name="companies")
    op.drop_column("companies", "suspension_reason")
    op.drop_column("companies", "suspended_at")
    op.drop_column("companies", "license_expires_at")
    op.drop_column("companies", "service_status")