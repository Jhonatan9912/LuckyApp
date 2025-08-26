from pydantic import BaseModel
from datetime import datetime
from typing import Optional, List

class ReferralItem(BaseModel):
    id: int
    referred_user_id: Optional[int] = None
    referred_name: Optional[str] = None
    referred_email: Optional[str] = None
    status: str
    created_at: Optional[datetime] = None
    # flag de suscripción PRO del referido
    pro_active: bool = False

    class Config:
        from_attributes = True


class ReferralSummary(BaseModel):
    total: int
    activos: int         # con PRO activo
    inactivos: int       # total - activos
