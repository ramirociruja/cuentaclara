"""add refinance links to loans

Revision ID: 8fbf76635f01
Revises: 89e55475b17f
Create Date: 2026-01-23 10:40:26.711494

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '8fbf76635f01'
down_revision: Union[str, None] = '89e55475b17f'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    pass


def downgrade() -> None:
    """Downgrade schema."""
    pass
