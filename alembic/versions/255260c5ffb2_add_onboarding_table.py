"""Add onboarding table

Revision ID: 255260c5ffb2
Revises: 175ff3c3090b
Create Date: 2025-12-16 22:25:46.157426

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = '255260c5ffb2'
down_revision: Union[str, None] = '175ff3c3090b'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade():
    op.create_table(
        "onboarding_import_sessions",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("company_id", sa.Integer(), sa.ForeignKey("companies.id", ondelete="CASCADE"), nullable=False, index=True),
        sa.Column("original_filename", sa.String(length=255), nullable=True),
        sa.Column("status", sa.String(length=32), nullable=False, server_default="validated"),
        sa.Column("payload_json", postgresql.JSONB(), nullable=False),
        sa.Column("summary_json", postgresql.JSONB(), nullable=False),
        sa.Column("errors_json", postgresql.JSONB(), nullable=False),
        sa.Column("warnings_json", postgresql.JSONB(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_onboarding_import_sessions_company_id", "onboarding_import_sessions", ["company_id"])
    op.create_index("ix_onboarding_import_sessions_expires_at", "onboarding_import_sessions", ["expires_at"])

def downgrade():
    op.drop_index("ix_onboarding_import_sessions_expires_at", table_name="onboarding_import_sessions")
    op.drop_index("ix_onboarding_import_sessions_company_id", table_name="onboarding_import_sessions")
    op.drop_table("onboarding_import_sessions")