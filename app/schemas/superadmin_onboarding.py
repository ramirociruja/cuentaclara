from pydantic import BaseModel
from typing import Optional, Dict, Any

class OnboardingCommitCounts(BaseModel):
    customers_created: int = 0
    loans_created: int = 0
    payments_created: int = 0
    installments_created: int = 0
    payment_allocations_created: int = 0

class OnboardingCommitOut(BaseModel):
    import_batch_id: str
    created_counts: OnboardingCommitCounts
    created_ids: Optional[Dict[str, int]] = None
    summary: Optional[Dict[str, Any]] = None

class CommitIn(BaseModel):
    batch_token: str