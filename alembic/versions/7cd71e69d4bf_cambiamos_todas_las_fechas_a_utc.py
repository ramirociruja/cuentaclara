"""cambiamos todas las fechas a UTC

Revision ID: 7cd71e69d4bf
Revises: a1c4508e0022
Create Date: 2025-10-27 00:17:18.699163

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '7cd71e69d4bf'
down_revision: Union[str, None] = 'a1c4508e0022'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade():
    # Postgres: usar 'TIMESTAMP WITH TIME ZONE'
    op.alter_column('payments', 'payment_date',
        type_=sa.TIMESTAMP(timezone=True),
        existing_nullable=False)
    op.alter_column('installments', 'due_date',
        type_=sa.TIMESTAMP(timezone=True),
        existing_nullable=False)
    op.alter_column('customers', 'created_at',
        type_=sa.TIMESTAMP(timezone=True),
        existing_nullable=False)
    # ... repetir para voided_at, start_date, updated_at, etc.

def downgrade():
    op.alter_column('payments', 'payment_date',
        type_=sa.TIMESTAMP(timezone=False),
        existing_nullable=False)
    # ... revertir el resto si hiciera falta