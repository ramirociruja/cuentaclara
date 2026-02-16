# app/utils/status.py
from __future__ import annotations

from sqlalchemy.orm import Session
from sqlalchemy import func, case

from app.models.models import Loan, Purchase, Installment
from app.constants import InstallmentStatus, LoanStatus

EPS = 1e-6


def _aggregates_for(
    db: Session,
    *,
    loan_id: int | None = None,
    purchase_id: int | None = None,
):
    """
    Calcula agregados de cuotas y conteos por estado.

    Devuelve:
      total_amount, total_paid,
      cnt_paid, cnt_overdue, cnt_partial, cnt_pending
    """
    q = db.query(
        func.coalesce(func.sum(Installment.amount), 0.0),
        func.coalesce(func.sum(Installment.paid_amount), 0.0),
        func.coalesce(
            func.sum(
                case((Installment.status == InstallmentStatus.PAID.value, 1), else_=0)
            ),
            0,
        ),
        func.coalesce(
            func.sum(
                case((Installment.status == InstallmentStatus.OVERDUE.value, 1), else_=0)
            ),
            0,
        ),
        func.coalesce(
            func.sum(
                case((Installment.status == InstallmentStatus.PARTIAL.value, 1), else_=0)
            ),
            0,
        ),
        func.coalesce(
            func.sum(
                case((Installment.status == InstallmentStatus.PENDING.value, 1), else_=0)
            ),
            0,
        ),
    )

    if loan_id is not None:
        q = q.filter(Installment.loan_id == loan_id)
    if purchase_id is not None:
        q = q.filter(Installment.purchase_id == purchase_id)

    total, paid, cnt_paid, cnt_overdue, cnt_partial, cnt_pending = q.one()
    return (
        float(total or 0.0),
        float(paid or 0.0),
        int(cnt_paid or 0),
        int(cnt_overdue or 0),
        int(cnt_partial or 0),
        int(cnt_pending or 0),
    )


def _derive_loan_status_from_counts(
    *,
    total_amount: float,
    total_paid: float,
    cnt_paid: int,
    cnt_overdue: int,
    cnt_partial: int,
    cnt_pending: int,
) -> str:
    """
    Regla de negocio base para estado del préstamo/venta derivado de sus cuotas:
      - Si todo está pagado (no hay pendientes/partials/overdues) -> PAID
      - Si hay al menos una overdue (y no todo pagado) -> DEFAULTED
      - En otro caso -> ACTIVE
    """
    all_cleared = (total_amount - total_paid) <= EPS and (cnt_pending + cnt_partial + cnt_overdue) == 0
    if all_cleared:
        return LoanStatus.PAID.value

    if cnt_overdue > 0:
        return LoanStatus.DEFAULTED.value

    return LoanStatus.ACTIVE.value


def update_status_if_fully_paid(db: Session, loan_id: int | None, purchase_id: int | None):
    """
    Recalcula estado y total_due para Loan y/o Purchase usando agregados de cuotas.

    Importante:
      - Nunca sobreescribe estados terminales manuales en Loan/Purchase:
          * LoanStatus.CANCELED
          * LoanStatus.REFINANCED
      - Los estados de cuotas (installments) se manejan en sus flujos propios
        (pago parcial/total, marcar vencidas, cancelar/refinanciar).
    """
    # ---------- Loan ----------
    if loan_id is not None:
        # Preferir Session.get si estás en SQLAlchemy 1.4/2.x
        loan = db.query(Loan).get(loan_id)
        if loan:
            total, paid, c_paid, c_overdue, c_partial, c_pending = _aggregates_for(db, loan_id=loan_id)

            # No tocar si el loan fue Cancelado/Refinanciado manualmente
            if loan.status not in (LoanStatus.CANCELED.value, LoanStatus.REFINANCED.value):
                derived = _derive_loan_status_from_counts(
                    total_amount=total,
                    total_paid=paid,
                    cnt_paid=c_paid,
                    cnt_overdue=c_overdue,
                    cnt_partial=c_partial,
                    cnt_pending=c_pending,
                )
                loan.status = derived

            loan.total_due = max(total - paid, 0.0)
            db.add(loan)

    # ---------- Purchase ----------
    if purchase_id is not None:
        purchase = db.query(Purchase).get(purchase_id)
        if purchase:
            total, paid, c_paid, c_overdue, c_partial, c_pending = _aggregates_for(db, purchase_id=purchase_id)

            if purchase.status not in (LoanStatus.CANCELED.value, LoanStatus.REFINANCED.value):
                derived = _derive_loan_status_from_counts(
                    total_amount=total,
                    total_paid=paid,
                    cnt_paid=c_paid,
                    cnt_overdue=c_overdue,
                    cnt_partial=c_partial,
                    cnt_pending=c_pending,
                )
                purchase.status = derived

            purchase.total_due = max(total - paid, 0.0)
            db.add(purchase)

    db.commit()


def normalize_loan_status_filter(raw: str | None) -> str | None:
    """
    Recibe status desde query params (puede venir EN canónico o ES UI/legacy)
    y devuelve el status EN canónico para filtrar en DB.
    """
    if not raw:
        return None

    s = raw.strip().lower()
    if not s:
        return None

    # EN canónico (o variantes)
    if s in {"active", "paid", "defaulted", "refinanced"}:
        return s
    if s in {"canceled", "cancelled"}:
        return LoanStatus.CANCELED.value

    # ES / legacy (como UI)
    mapping = {
        "activo": LoanStatus.ACTIVE.value,
        "pagado": LoanStatus.PAID.value,
        "pagada": LoanStatus.PAID.value,
        "incumplido": LoanStatus.DEFAULTED.value,
        "en mora": LoanStatus.DEFAULTED.value,
        "cancelado": LoanStatus.CANCELED.value,
        "cancelada": LoanStatus.CANCELED.value,
        "refinanciado": LoanStatus.REFINANCED.value,
        "refinanciada": LoanStatus.REFINANCED.value,
    }

    return mapping.get(s)



def normalize_installment_status_filter(raw: str | None) -> str | None:
    """
    Recibe status desde query params (puede venir EN canónico o ES UI/legacy)
    y devuelve el status EN canónico para filtrar en DB.
    """
    if not raw:
        return None

    s = raw.strip().lower()
    if not s:
        return None

    # EN canónico (o variantes)
    if s in {"pending", "partial", "paid", "overdue", "refinanced"}:
        return s
    if s in {"canceled", "cancelled"}:
        return InstallmentStatus.CANCELED.value

    # ES / legacy (como UI)
    mapping = {
        "pendiente": InstallmentStatus.PENDING.value,
        "parcial": InstallmentStatus.PARTIAL.value,
        "parcialmente pagada": InstallmentStatus.PARTIAL.value,
        "pagada": InstallmentStatus.PAID.value,
        "pagado": InstallmentStatus.PAID.value,
        "vencida": InstallmentStatus.OVERDUE.value,
        "vencido": InstallmentStatus.OVERDUE.value,
        "cancelada": InstallmentStatus.CANCELED.value,
        "cancelado": InstallmentStatus.CANCELED.value,
        "refinanciada": InstallmentStatus.REFINANCED.value,
        "refinanciado": InstallmentStatus.REFINANCED.value,
    }

    return mapping.get(s)
