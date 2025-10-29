from datetime import datetime, date, time, timedelta, timezone
from zoneinfo import ZoneInfo

AR_TZ = ZoneInfo("America/Argentina/Buenos_Aires")

def local_dates_to_utc_window(dfrom: date, dto: date, tz: ZoneInfo = AR_TZ):
    """
    Recibe fechas (locales) y devuelve (start_utc, end_utc_exclusive) aware.
    [dfrom 00:00:00 local, dto 24:00:00 local) → UTC
    """
    start_local = datetime.combine(dfrom, time.min).replace(tzinfo=tz)
    end_local_excl = datetime.combine(dto, time.min).replace(tzinfo=tz) + timedelta(days=1)

    return start_local.astimezone(timezone.utc), end_local_excl.astimezone(timezone.utc)

def parse_iso_aware_utc(s: str | None) -> datetime | None:
    """
    Parsea ISO-8601 (admite 'Z') y devuelve datetime aware en UTC.
    """
    if not s:
        return None
    try:
        dt = datetime.fromisoformat(s.replace("Z", "+00:00"))
        return dt.astimezone(timezone.utc)
    except Exception:
        return None
