# app/utils/normalize.py
from typing import Optional
from app.constants import (
    NORMALIZE_INSTALLMENT_STATUS, NORMALIZE_LOAN_STATUS,
    InstallmentStatus, LoanStatus
)

def norm_installment_status(raw: Optional[str]) -> InstallmentStatus:
    if not raw:
        return InstallmentStatus.PENDING
    key = raw.strip().lower()
    return NORMALIZE_INSTALLMENT_STATUS.get(key, InstallmentStatus.PENDING)

def norm_loan_status(raw: Optional[str]) -> LoanStatus:
    if not raw:
        return LoanStatus.ACTIVE
    key = raw.strip().lower()
    return NORMALIZE_LOAN_STATUS.get(key, LoanStatus.ACTIVE)
