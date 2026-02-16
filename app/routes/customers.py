from datetime import datetime
import re
from typing import List, Optional
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, or_, and_
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError

from app.database.db import SessionLocal
from app.models.models import Customer, Employee, Installment, Loan
from app.routes.installments import _assert_customer_scoped
from app.routes.loans import loan_is_effective_for_loans
from app.schemas.customers import CustomerCreate, CustomerDashboardOut, CustomerLoanRowOut, CustomerLoansOut, CustomerUpdate, CustomerOut
from app.utils.auth import get_current_user
from app.utils.license import ensure_company_active
from app.utils.time_windows import AR_TZ, local_dates_to_utc_window

router = APIRouter(
    dependencies=[Depends(get_current_user), Depends(ensure_company_active)],
)

# --- DB session helper ---
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# --- Utils ---
def normalize_phone(phone: str | None) -> str | None:
    if not phone:
        return None
    digits = re.sub(r"\D", "", phone)
    if digits.startswith("0"):
        digits = digits[1:]
    if digits.startswith("54") and len(digits) > 10:
        digits = digits[2:]
    return digits

def _404():
    raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Recurso no encontrado")

def _is_admin_or_manager(emp: Employee) -> bool:
    # Ajustá según tus roles reales
    return emp.role in {"admin", "manager", "ADMIN", "MANAGER"}

# ===========================
#        CREATE
# ===========================
@router.post("/", response_model=CustomerOut, status_code=status.HTTP_201_CREATED)
def create_customer(
    payload: CustomerCreate,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    phone_norm = normalize_phone(payload.phone)
    data = payload.model_dump(exclude_unset=True)
    data.pop("created_at", None)
    data["phone"] = phone_norm

    # Forzar scope por empresa desde el token
    data["company_id"] = current.company_id

    # Determinar el owner empleado (unicidad por empleado)
    owner_employee_id: int
    if _is_admin_or_manager(current):
        # Admin/manager puede crear para otro empleado si viene en el body
        owner_employee_id = int(data.get("employee_id") or current.id)
    else:
        # Cobrador: siempre él mismo
        owner_employee_id = current.id
    data["employee_id"] = owner_employee_id  # asegurar consistencia

    # Pre-chequeo de duplicados dentro del EMPLEADO (no por empresa)
    qdup = db.query(Customer).filter(
        Customer.employee_id == owner_employee_id
    )
    or_terms = []
    if data.get("dni"):
        or_terms.append(Customer.dni == data["dni"])
    if phone_norm:
        or_terms.append(Customer.phone == phone_norm)
    if data.get("email"):
        or_terms.append(Customer.email == data["email"])
    if or_terms:
        dups = qdup.filter(or_(*or_terms)).all()
        if dups:
            if any(c.dni == data.get("dni") and data.get("dni") is not None for c in dups) and \
               any(c.phone == phone_norm and phone_norm is not None for c in dups):
                raise HTTPException(status_code=409, detail="DNI y teléfono ya están registrados para este empleado.")
            if any(c.dni == data.get("dni") and data.get("dni") is not None for c in dups):
                raise HTTPException(status_code=409, detail="DNI ya registrado para este empleado.")
            if any(c.phone == phone_norm and phone_norm is not None for c in dups):
                raise HTTPException(status_code=409, detail="Teléfono ya registrado para este empleado.")
            if any(c.email == data.get("email") and data.get("email") is not None for c in dups):
                raise HTTPException(status_code=409, detail="Email ya registrado para este empleado.")

    obj = Customer(**data)
    db.add(obj)
    try:
        db.commit()
    except IntegrityError as e:
        db.rollback()
        # Mapear nombres de constraints por empleado
        constraint = getattr(getattr(e, "orig", None), "diag", None)
        cname = getattr(constraint, "constraint_name", "") if constraint else ""

        # Nuevos únicos por empleado
        if cname in {"ux_customers_employee_dni"}:
            raise HTTPException(status_code=409, detail="DNI ya registrado para este empleado.")
        if cname in {"ux_customers_employee_phone"}:
            raise HTTPException(status_code=409, detail="Teléfono ya registrado para este empleado.")
        if cname in {"ux_customers_employee_email"}:
            raise HTTPException(status_code=409, detail="Email ya registrado para este empleado.")

        # Compatibilidad hacia atrás (por si existe algún resto de constraints viejas)
        if cname in {"uq_customer_company_dni", "customers_company_dni_key", "customers_dni_key"}:
            raise HTTPException(status_code=409, detail="DNI ya registrado.")
        if cname in {"uq_customer_company_phone", "customers_company_phone_key", "customers_phone_key"}:
            raise HTTPException(status_code=409, detail="Teléfono ya registrado.")
        if cname in {"uq_customer_company_email", "customers_company_email_key", "customers_email_key"}:
            raise HTTPException(status_code=409, detail="Email ya registrado.")

        raise HTTPException(status_code=409, detail="Ya existe un cliente con DNI/teléfono/email para este empleado.")
    db.refresh(obj)
    return obj


@router.get("/", response_model=List[CustomerOut])
def list_company_customers(
    created_from: Optional[str] = Query(None),
    created_to: Optional[str] = Query(None),
    employee_id: Optional[int] = Query(None),
    q: Optional[str] = Query(None),
    tz: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    """
    Lista TODOS los clientes de la empresa del usuario logueado.

    Filtros opcionales:
    - created_from / created_to (YYYY-MM-DD) sobre Customer.created_at (ventana local -> UTC)
    - employee_id (owner/cobrador)
    - q: busca por nombre, apellido, DNI o teléfono (normalizado)
    """
    zone = ZoneInfo(tz) if tz else AR_TZ

    def _looks_like_date(s: Optional[str]) -> bool:
        return bool(s) and len(s) == 10 and s[4] == "-" and s[7] == "-"

    qry = db.query(Customer).filter(Customer.company_id == current.company_id)

    if employee_id is not None:
        qry = qry.filter(Customer.employee_id == employee_id)

    if _looks_like_date(created_from) and _looks_like_date(created_to):
        dfrom = datetime.fromisoformat(created_from).date()
        dto = datetime.fromisoformat(created_to).date()
        start_utc, end_utc_excl = local_dates_to_utc_window(dfrom, dto, zone)
        qry = (
            qry.filter(Customer.created_at >= start_utc)
               .filter(Customer.created_at < end_utc_excl)
        )

    if q:
        qn = re.sub(r"\s+", " ", q).strip()
        phone_norm = normalize_phone(qn)
        like = f"%{qn.lower()}%"

        ors = [
            func.lower(Customer.first_name).like(like),
            func.lower(Customer.last_name).like(like),
        ]
        if qn.isdigit():
            ors.append(Customer.dni == qn)
        if phone_norm:
            ors.append(Customer.phone == phone_norm)

        qry = qry.filter(or_(*ors))

    return qry.order_by(Customer.last_name.asc(), Customer.first_name.asc()).all()



@router.get("/{customer_id}/dashboard", response_model=CustomerDashboardOut)
def customer_dashboard(
    customer_id: int,
    tz: str | None = Query(None),
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    _assert_customer_scoped(customer_id, db, current)

    zone = ZoneInfo(tz) if tz else AR_TZ
    today_local = datetime.now(zone).date()
    tzname = tz or "America/Argentina/Tucuman"

    # -----------------------------
    # LOANS: conteos y saldo total
    # -----------------------------
    loans_base = (
        db.query(Loan)
        .filter(Loan.company_id == current.company_id)
        .filter(Loan.customer_id == customer_id)
    )

    loans_total_count = loans_base.with_entities(func.count(Loan.id)).scalar() or 0

    effective_loans = loans_base.filter(loan_is_effective_for_loans(Loan))

    total_due = (
        effective_loans.with_entities(func.coalesce(func.sum(func.coalesce(Loan.total_due, 0.0)), 0.0)).scalar()
        or 0.0
    )

    active_loans_count = (
        effective_loans.filter(func.coalesce(Loan.total_due, 0.0) > 0.0)
        .with_entities(func.count(Loan.id)).scalar()
        or 0
    )

    # -----------------------------
    # INSTALLMENTS: vencidas y próxima
    # (solo de LOANS de este cliente)
    # -----------------------------
    inst_base = (
        db.query(Installment)
        .join(Loan, Installment.loan_id == Loan.id)
        .filter(Loan.company_id == current.company_id)
        .filter(Loan.customer_id == customer_id)
        .filter(loan_is_effective_for_loans(Loan))
    )

    # vencidas (comparación por día local)
    due_local_day = func.date(func.timezone(tzname, Installment.due_date))
    inst_balance = func.greatest(
        func.coalesce(Installment.amount, 0.0) - func.coalesce(Installment.paid_amount, 0.0),
        0.0,
    )

    overdue_q = (
        inst_base
        .filter(Installment.is_paid.is_(False))
        .filter(due_local_day < today_local)
        .filter(Installment.status.notin_(["cancelled", "refinanced", "canceled"]))
    )

    overdue_installments_count = overdue_q.with_entities(func.count(Installment.id)).scalar() or 0

    overdue_amount = (
        overdue_q.with_entities(func.coalesce(func.sum(inst_balance), 0.0)).scalar()
        or 0.0
    )

    # próxima cuota (la más próxima >= hoy local, con saldo)
    next_row = (
        inst_base
        .filter(Installment.is_paid.is_(False))
        .filter(Installment.status.notin_(["cancelled", "refinanced", "canceled"]))
        .filter(inst_balance > 0.0)
        .filter(due_local_day >= today_local)
        .order_by(Installment.due_date.asc(), Installment.number.asc(), Installment.id.asc())
        .with_entities(Installment.due_date, inst_balance)
        .first()
    )

    next_due_date = None
    next_due_amount = None
    if next_row:
        dd, bal = next_row
        # dd es UTC; la mostramos como date local
        dd_local = dd.astimezone(zone).date() if getattr(dd, "astimezone", None) else dd.date()
        next_due_date = dd_local
        next_due_amount = float(bal or 0.0)

    return CustomerDashboardOut(
        customer_id=customer_id,
        total_due=float(total_due or 0.0),
        active_loans_count=int(active_loans_count or 0),
        loans_total_count=int(loans_total_count or 0),
        overdue_installments_count=int(overdue_installments_count or 0),
        overdue_amount=float(overdue_amount or 0.0),
        next_due_date=next_due_date,
        next_due_amount=next_due_amount,
    )




# ===========================
#        GET BY ID
# ===========================
@router.get("/{customer_id}", response_model=CustomerOut)
def get_customer(
    customer_id: int,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    obj = db.query(Customer).filter(Customer.id == customer_id).first()
    # Seguridad por empresa
    if not obj or obj.company_id != current.company_id:
        _404()
    return obj

# ===========================
#        UPDATE
# ===========================
@router.put("/{customer_id}", response_model=CustomerOut)
def update_customer(
    customer_id: int,
    payload: CustomerUpdate,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    obj = db.query(Customer).filter(Customer.id == customer_id).first()
    if not obj or obj.company_id != current.company_id:
        _404()

    changes = payload.model_dump(exclude_unset=True)

    # Normalizar phone si vino
    if "phone" in changes and changes["phone"] is not None:
        changes["phone"] = normalize_phone(changes["phone"])

    # Determinar employee destino para validación de unicidad.
    # - Si sos admin/manager y el payload trae employee_id, validamos contra ese destino.
    # - Si no, se valida contra el employee actual del registro.
    target_employee_id = obj.employee_id
    if _is_admin_or_manager(current) and "employee_id" in changes and changes["employee_id"]:
        target_employee_id = int(changes["employee_id"])

    # Validar duplicados por empleado destino SOLO si cambian esos campos o si cambia employee_id
    def _exists(field: str, value: Optional[str]) -> bool:
        if not value:
            return False
        return db.query(Customer).filter(
            Customer.employee_id == target_employee_id,
            getattr(Customer, field) == value,
            Customer.id != customer_id,
        ).first() is not None

    if "dni" in changes and changes["dni"] != obj.dni and _exists("dni", changes["dni"]):
        raise HTTPException(status_code=409, detail="DNI ya registrado para ese empleado.")
    if "phone" in changes and changes["phone"] != obj.phone and _exists("phone", changes["phone"]):
        raise HTTPException(status_code=409, detail="Teléfono ya registrado para ese empleado.")
    if "email" in changes and changes["email"] != obj.email and _exists("email", changes["email"]):
        raise HTTPException(status_code=409, detail="Email ya registrado para ese empleado.")

    # Si solo cambia employee_id (y no cambió dni/phone/email) igual hay que validar que
    # en el destino no exista un registro con mismos datos.
    if ("employee_id" in changes and int(changes["employee_id"]) != obj.employee_id):
        for fld in ("dni", "phone", "email"):
            val = changes.get(fld, getattr(obj, fld))
            if val and _exists(fld, val):
                raise HTTPException(status_code=409, detail=f"{fld.upper()} ya registrado para ese empleado.")

    # Aplicar cambios permitidos
    for k, v in changes.items():
        setattr(obj, k, v)

    # company_id SIEMPRE el del token
    obj.company_id = current.company_id

    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj


# ===========================
#      BY EMPLOYEE (scope)
# ===========================
@router.get("/employees/{employee_id}", response_model=List[CustomerOut])
def get_customers_by_employee(
    employee_id: int,
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    # Asegurar que el employee pertenece a la misma empresa
    emp = db.query(Employee).filter(Employee.id == employee_id).first()
    if not emp or emp.company_id != current.company_id:
        _404()

    return (
        db.query(Customer)
        .filter(Customer.company_id == current.company_id)
        .order_by(Customer.last_name.asc(), Customer.first_name.asc())
        .all()
    )



@router.get("/{customer_id}/loans", response_model=CustomerLoansOut)
def customer_loans(
    customer_id: int,
    active_only: bool = Query(False),
    tz: str | None = Query(None),
    limit: int = Query(200, ge=1, le=500),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    current: Employee = Depends(get_current_user),
):
    _assert_customer_scoped(customer_id, db, current)

    zone = ZoneInfo(tz) if tz else AR_TZ
    today_local = datetime.now(zone).date()
    tzname = tz or "America/Argentina/Tucuman"

    # -----------------------------
    # Base loans (TODOS)
    # -----------------------------
    loans_q = (
        db.query(Loan)
        .filter(Loan.company_id == current.company_id)
        .filter(Loan.customer_id == customer_id)
    )

    if active_only:
        loans_q = loans_q.filter(loan_is_effective_for_loans(Loan))
        # además excluimos explícitamente pagados por status si existe (defensivo)
        if hasattr(Loan, "status"):
            loans_q = loans_q.filter(func.coalesce(Loan.status, "") != "paid")
        # y/o por saldo (si querés que “activo” sea saldo > 0)
        loans_q = loans_q.filter(func.coalesce(Loan.total_due, 0.0) > 0.0)

    total_count = loans_q.with_entities(func.count(Loan.id)).scalar() or 0

    loans = (
        loans_q
        .order_by(Loan.start_date.desc().nulls_last(), Loan.id.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )

    if not loans:
        return CustomerLoansOut(
            customer_id=customer_id,
            active_only=bool(active_only),
            total_count=int(total_count or 0),
            total_due=0.0,
            overdue_amount=0.0,
            overdue_installments_count=0,
            loans=[],
        )

    loan_ids = [l.id for l in loans]

    # -----------------------------
    # Installments agregados por loan_id
    # overdue_count / overdue_amount / next_due
    # -----------------------------
    due_local_day = func.date(func.timezone(tzname, Installment.due_date))
    inst_balance = func.greatest(
        func.coalesce(Installment.amount, 0.0) - func.coalesce(Installment.paid_amount, 0.0),
        0.0,
    )

    inst_base = (
        db.query(Installment)
        .filter(Installment.loan_id.in_(loan_ids))
    )

    overdue_rows = (
        inst_base
        .filter(Installment.is_paid.is_(False))
        .filter(due_local_day < today_local)
        .filter(Installment.status.notin_(["cancelled", "refinanced", "canceled"]))
        .with_entities(
            Installment.loan_id.label("loan_id"),
            func.count(Installment.id).label("overdue_count"),
            func.coalesce(func.sum(inst_balance), 0.0).label("overdue_amount"),
        )
        .group_by(Installment.loan_id)
        .all()
    )
    overdue_by_loan = {
        int(r.loan_id): {
            "overdue_count": int(r.overdue_count or 0),
            "overdue_amount": float(r.overdue_amount or 0.0),
        }
        for r in overdue_rows
    }

    # próxima cuota por loan: MIN(due_date) con saldo > 0 y due_local_day >= hoy local
    next_rows = (
        inst_base
        .filter(Installment.is_paid.is_(False))
        .filter(inst_balance > 0.0)
        .filter(due_local_day >= today_local)
        .filter(Installment.status.notin_(["cancelled", "refinanced", "canceled"]))
        .with_entities(
            Installment.loan_id.label("loan_id"),
            func.min(Installment.due_date).label("next_due_dt"),
        )
        .group_by(Installment.loan_id)
        .all()
    )
    next_due_dt_by_loan = {int(r.loan_id): r.next_due_dt for r in next_rows}

    # Para obtener el monto de esa cuota “min due_date”, hacemos lookup por (loan_id, due_date)
    # (es eficiente a tu escala; si querés ultra-óptimo lo hacemos con window functions)
    next_amount_by_loan: dict[int, float] = {}
    if next_due_dt_by_loan:
        pairs = [(lid, dt) for lid, dt in next_due_dt_by_loan.items() if dt is not None]
        for lid, dt in pairs:
            row = (
                db.query(inst_balance)
                .filter(Installment.loan_id == lid)
                .filter(Installment.due_date == dt)
                .filter(Installment.is_paid.is_(False))
                .order_by(Installment.number.asc(), Installment.id.asc())
                .first()
            )
            if row:
                next_amount_by_loan[lid] = float(row[0] or 0.0)

    # -----------------------------
    # Collector names (opcional)
    # -----------------------------
    emp_ids = list({int(l.employee_id) for l in loans if l.employee_id is not None})
    emp_map: dict[int, str] = {}
    if emp_ids:
        emps = db.query(Employee.id, Employee.name).filter(Employee.id.in_(emp_ids)).all()
        emp_map = {int(eid): (name or "") for eid, name in emps}

    # -----------------------------
    # Output
    # -----------------------------
    rows_out: list[CustomerLoanRowOut] = []
    total_due = 0.0
    total_overdue_amount = 0.0
    total_overdue_count = 0

    for l in loans:
        od = overdue_by_loan.get(int(l.id), {"overdue_count": 0, "overdue_amount": 0.0})
        next_dt = next_due_dt_by_loan.get(int(l.id))

        next_due_date = None
        if next_dt is not None:
            # next_dt es UTC; convertimos a date local para mostrar
            next_due_date = next_dt.astimezone(zone).date() if getattr(next_dt, "astimezone", None) else next_dt.date()

        next_amt = next_amount_by_loan.get(int(l.id))

        loan_total_due = float(getattr(l, "total_due", 0.0) or 0.0)
        total_due += loan_total_due
        total_overdue_amount += float(od["overdue_amount"] or 0.0)
        total_overdue_count += int(od["overdue_count"] or 0)

        rows_out.append(CustomerLoanRowOut(
            loan_id=int(l.id),
            status=getattr(l, "status", None),

            amount=float(getattr(l, "amount", 0.0) or 0.0),
            total_due=loan_total_due,

            installments_count=getattr(l, "installments_count", None),
            installment_amount=getattr(l, "installment_amount", None),
            installment_interval_days=getattr(l, "installment_interval_days", None),
            start_date=l.start_date.isoformat() if getattr(l, "start_date", None) else None,

            collector_id=getattr(l, "employee_id", None),
            collector_name=emp_map.get(int(l.employee_id), None) if getattr(l, "employee_id", None) else None,
            description=getattr(l, "description", None),

            overdue_installments_count=int(od["overdue_count"] or 0),
            overdue_amount=float(od["overdue_amount"] or 0.0),

            next_due_date=next_due_date,
            next_due_amount=float(next_amt) if next_amt is not None else None,
        ))

    return CustomerLoansOut(
        customer_id=customer_id,
        active_only=bool(active_only),
        total_count=int(total_count or 0),
        total_due=float(total_due or 0.0),
        overdue_amount=float(total_overdue_amount or 0.0),
        overdue_installments_count=int(total_overdue_count or 0),
        loans=rows_out,
    )